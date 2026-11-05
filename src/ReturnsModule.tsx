import { FormEvent, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, any>;
type ReturnLine = Row & { product_name: string; unit_name: string; returned_quantity: number; return_quantity: string; return_to_stock: boolean };

export default function ReturnsModule({ db, tenantId, currentRole }: { db: SupabaseClient; tenantId: string; currentRole: string }) {
  const [invoices, setInvoices] = useState<Row[]>([]);
  const [salesOrders, setSalesOrders] = useState<Row[]>([]);
  const [selectedCustomerId, setSelectedCustomerId] = useState("");
  const [selectedOrderId, setSelectedOrderId] = useState("");
  const [customers, setCustomers] = useState<Row[]>([]);
  const [notes, setNotes] = useState<Row[]>([]);
  const [invoiceId, setInvoiceId] = useState("");
  const [invoiceLines, setInvoiceLines] = useState<ReturnLine[]>([]);
  const [reason, setReason] = useState("");
  const [noteDate, setNoteDate] = useState(new Date().toISOString().slice(0,10));
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [printNote,setPrintNote] = useState<Row|null>(null);
  const [printLines,setPrintLines] = useState<Row[]>([]);
  const canPost = ["owner","admin","manager","accounts"].includes(currentRole);
  const money = (v: number) => "PKR " + Number(v || 0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});

  async function load() {
    setLoading(true); setNotice("");
    try {
      const [i,o,c,n] = await Promise.all([
        db.from("sales_invoices").select("id,invoice_number,invoice_date,customer_id,sales_order_id,grand_total,status").eq("tenant_id",tenantId).eq("status","posted").order("invoice_date",{ascending:false}).limit(500),
        db.from("sales_orders").select("id,order_number,customer_id,order_date,status").eq("tenant_id",tenantId).order("order_date",{ascending:false}).limit(500),
        db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",["customer","both"]).order("name"),
        db.from("sales_credit_notes").select("id,credit_note_number,credit_note_date,sales_invoice_id,customer_id,reason,status,grand_total,created_at").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(100)
      ]);
      const err=i.error||o.error||c.error||n.error;if(err)throw err;
      setInvoices(i.data||[]);setSalesOrders(o.data||[]);setCustomers(c.data||[]);setNotes(n.data||[]);
    } catch(e) { setNotice(e instanceof Error?e.message:"Returns could not be loaded."); }
    setLoading(false);
  }
  useEffect(()=>{void load();},[tenantId]);

  async function selectInvoice(id:string) {
    setInvoiceId(id);setInvoiceLines([]);setNotice("");
    if(!id)return;
    try {
      const {data:lines,error}=await db.from("sales_invoice_lines").select("id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total").eq("tenant_id",tenantId).eq("sales_invoice_id",id);
      if(error)throw error;
      if(!lines?.length)throw new Error("This invoice has no returnable lines.");
      const {data:existing,error:existingError}=await db.from("sales_credit_notes").select("id,status").eq("tenant_id",tenantId).eq("sales_invoice_id",id);
      if(existingError)throw existingError;
      const postedIds=(existing||[]).filter(x=>x.status==="posted").map(x=>x.id);
      let returned:Row[]=[];
      if(postedIds.length){const {data,error:lineError}=await db.from("sales_credit_note_lines").select("sales_invoice_line_id,quantity").eq("tenant_id",tenantId).in("credit_note_id",postedIds);if(lineError)throw lineError;returned=data||[];}
      const returnedMap=new Map<string,number>();
      returned.forEach(x=>returnedMap.set(x.sales_invoice_line_id,(returnedMap.get(x.sales_invoice_line_id)||0)+Number(x.quantity)));
      const productIds=[...new Set(lines.map(x=>x.product_id))],unitIds=[...new Set(lines.map(x=>x.unit_id))];
      const [p,u]=await Promise.all([db.from("products").select("id,name,sku,barcode").eq("tenant_id",tenantId).in("id",productIds),db.from("units_of_measure").select("id,name,symbol").eq("tenant_id",tenantId).in("id",unitIds)]);
      if(p.error)throw p.error;if(u.error)throw u.error;
      setInvoiceLines(lines.map(x=>({...x,product_name:p.data?.find(y=>y.id===x.product_id)?.name||x.product_id,unit_name:u.data?.find(y=>y.id===x.unit_id)?.symbol||u.data?.find(y=>y.id===x.unit_id)?.name||"",returned_quantity:returnedMap.get(x.id)||0,return_quantity:"0",return_to_stock:true})));
    } catch(e){setNotice(e instanceof Error?e.message:"Invoice lines could not be loaded.");}
  }

  function updateLine(id:string,key:"return_quantity"|"return_to_stock",value:string|boolean){
    setInvoiceLines(old=>old.map(x=>x.id===id?{...x,[key]:value}:x));
  }

  async function createDraft(e:FormEvent){
    e.preventDefault();setSaving(true);setNotice("");
    try{
      const lines=invoiceLines.filter(x=>Number(x.return_quantity)>0);
      if(!invoiceId||!reason.trim()||!lines.length)throw new Error("Select an invoice, enter a reason and enter at least one returned quantity.");
      for(const line of lines){if(!Number.isFinite(Number(line.return_quantity))||Number(line.return_quantity)<=0||Number(line.return_quantity)>Number(line.quantity)-line.returned_quantity+0.000001)throw new Error("A return quantity is invalid or exceeds the remaining invoiced quantity.");}
      const {data,error}=await db.rpc("create_sales_credit_note",{p_invoice_id:invoiceId,p_lines:lines.map(x=>({invoice_line_id:x.id,quantity:Number(x.return_quantity),return_to_stock:x.return_to_stock})),p_reason:reason.trim(),p_credit_note_date:noteDate});
      if(error)throw error;
      setNotice("Credit note draft created: "+String(data).slice(0,8)+". Post it after review.");
      setInvoiceId("");setInvoiceLines([]);setSelectedOrderId("");setSelectedCustomerId("");setReason("");await load();
    }catch(e){setNotice(e instanceof Error?e.message:"Credit note could not be created.");}
    setSaving(false);
  }

  async function preparePrint(note:Row){
    try{
      const {data,error}=await db.from("sales_credit_note_lines").select("product_id,unit_id,quantity,unit_price,tax_rate,discount_amount,line_total,return_to_stock").eq("tenant_id",tenantId).eq("credit_note_id",note.id);
      if(error)throw error;
      const productIds=[...new Set((data??[]).map(x=>x.product_id))],unitIds=[...new Set((data??[]).map(x=>x.unit_id))];
      const [p,u]=await Promise.all([db.from("products").select("id,name,sku").eq("tenant_id",tenantId).in("id",productIds),db.from("units_of_measure").select("id,name,symbol").eq("tenant_id",tenantId).in("id",unitIds)]);
      if(p.error)throw p.error;if(u.error)throw u.error;
      setPrintLines((data??[]).map(x=>({...x,product_name:p.data?.find(y=>y.id===x.product_id)?.name||x.product_id,unit_name:u.data?.find(y=>y.id===x.unit_id)?.symbol||""})));
      setPrintNote(note);
    }catch(e){setNotice(e instanceof Error?e.message:"Credit note print preview could not be prepared.");}
  }

  async function postNote(id:string){
    setSaving(true);setNotice("");
    try{const {data,error}=await db.rpc("post_sales_credit_note",{p_credit_note_id:id});if(error)throw error;if(data?.success!==true)throw new Error("Credit note posting was not confirmed.");setNotice("Credit note posted. Customer balance and returned stock/accounting have been updated.");await load();}
    catch(e){setNotice(e instanceof Error?e.message:"Credit note posting failed.");}
    setSaving(false);
  }

  const invoice=invoices.find(x=>x.id===invoiceId);
  const estimate=invoiceLines.reduce((sum,x)=>{const q=Number(x.return_quantity)||0;const gross=q*Number(x.unit_price);const tax=gross*Number(x.tax_rate)/100;const discount=Number(x.quantity)>0?Number(x.discount_amount)*(q/Number(x.quantity)):0;return sum+gross+tax-discount;},0);

  return <section className="module-page">
    <div className="module-toolbar"><div><h2>Sales Returns & Credit Notes</h2><p>Record customer returns against posted invoices, issue credit notes and restore accepted goods to stock.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
    {notice&&<div className="notice">{notice}</div>}
    <form className="transaction-form" onSubmit={createDraft}>
      <h3>Create customer return / credit note</h3>
      <div className="form-grid">
        <label>Customer<select required value={selectedCustomerId} onChange={e=>{setSelectedCustomerId(e.target.value);setSelectedOrderId("");setInvoiceId("");setInvoiceLines([]);}}><option value="">Select customer</option>{customers.map(x=><option key={x.id} value={x.id}>{x.name} · {x.party_code}</option>)}</select></label>
        <label>Sales Order<select required value={selectedOrderId} onChange={e=>{setSelectedOrderId(e.target.value);setInvoiceId("");setInvoiceLines([]);}} disabled={!selectedCustomerId}><option value="">Select sales order</option>{salesOrders.filter(x=>x.customer_id===selectedCustomerId).map(x=><option key={x.id} value={x.id}>{x.order_number} · {x.order_date?.slice(0,10)}</option>)}</select></label>
        <label>Posted invoice<select required value={invoiceId} onChange={e=>void selectInvoice(e.target.value)} disabled={!selectedOrderId}><option value="">Select invoice</option>{invoices.filter(x=>x.customer_id===selectedCustomerId&&x.sales_order_id===selectedOrderId).map(x=><option key={x.id} value={x.id}>{x.invoice_number} · {money(x.grand_total)}</option>)}</select></label>
        <label>Credit note date<input type="date" value={noteDate} onChange={e=>setNoteDate(e.target.value)}/></label>
        <label>Reason<input required value={reason} onChange={e=>setReason(e.target.value)} placeholder="Damaged goods, short supply, expiry…"/></label>
      </div>
      {invoice&&<p className="module-footnote">Invoice: {invoice.invoice_number} · Customer: {customers.find(c=>c.id===invoice.customer_id)?.name||"—"} · Original total: {money(invoice.grand_total)}</p>}
      {invoiceLines.length>0&&<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Product</th><th>Invoiced</th><th>Already credited</th><th>Return qty</th><th>Restock?</th><th>Credit estimate</th></tr></thead><tbody>
        {invoiceLines.map(x=><tr key={x.id}><td>{x.product_name} · {x.unit_name}</td><td>{x.quantity}</td><td>{x.returned_quantity}</td><td><input type="number" min="0" max={Math.max(0,Number(x.quantity)-x.returned_quantity)} step="0.001" value={x.return_quantity} onChange={e=>updateLine(x.id,"return_quantity",e.target.value)}/></td><td><input type="checkbox" checked={x.return_to_stock} onChange={e=>updateLine(x.id,"return_to_stock",e.target.checked)}/> Accepted goods</td><td>{money(Math.max(0,Number(x.return_quantity)||0)*Number(x.unit_price)*(1+Number(x.tax_rate)/100)-Number(x.discount_amount)*(Number(x.return_quantity)||0)/Number(x.quantity))}</td></tr>)}
      </tbody></table><div className="table-tools"><strong>Estimated credit note: {money(estimate)}</strong></div></div>}
      <button disabled={saving||!invoiceLines.length}>{saving?"Saving…":"Save credit note draft"}</button>
      <p className="module-footnote">Posting is restricted to owner, admin, manager and accounts roles. Accepted returns add stock at the original dispatch cost; price-only credits do not change stock.</p>
    </form>
    <h3>Credit note register</h3>
    {loading?<div className="table-empty">Loading credit notes…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Credit note</th><th>Date</th><th>Invoice</th><th>Customer</th><th>Reason</th><th>Amount</th><th>Status / action</th></tr></thead><tbody>
      {notes.map(n=><tr key={n.id}><td>{n.credit_note_number}</td><td>{n.credit_note_date}</td><td>{invoices.find(i=>i.id===n.sales_invoice_id)?.invoice_number||n.sales_invoice_id}</td><td>{customers.find(c=>c.id===n.customer_id)?.name||n.customer_id}</td><td>{n.reason}</td><td>{money(n.grand_total)}</td><td><button onClick={()=>void preparePrint(n)}>Print</button> {n.status==="draft"&&canPost?<button disabled={saving} onClick={()=>void postNote(n.id)}>Post credit note</button>:n.status==="draft"?"Awaiting accounts posting":n.status}</td></tr>)}
      {!notes.length&&<tr><td colSpan={7} className="table-empty">No credit notes recorded yet.</td></tr>}
    </tbody></table></div>}
    {printNote&&<section className="print-document"><div className="print-top"><h2>EBS PRO V.01</h2><strong>SALES CREDIT NOTE</strong><p>Wholesale & Distribution</p></div><div className="print-meta"><div><b>Customer</b><br/>{customers.find(c=>c.id===printNote.customer_id)?.name||"—"}</div><div><b>Credit note</b><br/>{printNote.credit_note_number}<br/>{printNote.credit_note_date}<br/>Status: {printNote.status}</div></div><p>Reason: {printNote.reason}</p><table className="print-table"><thead><tr><th>Product</th><th>Qty</th><th>Rate</th><th>Tax</th><th>Discount</th><th>Total</th></tr></thead><tbody>{printLines.map((line,i)=><tr key={i}><td>{line.product_name}<small>Barcode: {products.find(p=>p.id===line.product_id)?.barcode||"—"}</small></td><td>{line.quantity} {line.unit_name}</td><td>{money(line.unit_price)}</td><td>{line.tax_rate}%</td><td>{money(line.discount_amount)}</td><td>{money(line.line_total)}</td></tr>)}</tbody></table><div className="print-total">Credit total: {money(printNote.grand_total)}</div><div className="print-actions"><button onClick={()=>window.print()}>Print</button><button onClick={()=>setPrintNote(null)}>Close</button></div></section>}
  </section>;
}
