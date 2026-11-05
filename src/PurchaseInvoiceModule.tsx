import {FormEvent,useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Row=Record<string,any>;
export default function PurchaseInvoiceModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [grns,setGrns]=useState<Row[]>([]),[orders,setOrders]=useState<Row[]>([]),[parties,setParties]=useState<Row[]>([]),[invoices,setInvoices]=useState<Row[]>([]);
 const [selectedGrn,setSelectedGrn]=useState(""),[invoiceNo,setInvoiceNo]=useState(""),[invoiceDate,setInvoiceDate]=useState(new Date().toISOString().slice(0,10)),[dueDate,setDueDate]=useState(""),[tax,setTax]=useState("0"),[notes,setNotes]=useState("");
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const canCreate=["owner","admin","manager","purchase"].includes(currentRole),canPost=["owner","admin","manager","accounts"].includes(currentRole);
 const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
 async function load(){
  setLoading(true);setNotice("");
  const [g,o,p,i]=await Promise.all([
   db.from("goods_receipts").select("id,grn_number,received_date,purchase_order_id,status").eq("tenant_id",tenantId).eq("status","posted").order("received_date",{ascending:false}).limit(300),
   db.from("purchase_orders").select("id,po_number,supplier_id").eq("tenant_id",tenantId),
   db.from("parties").select("id,party_code,name").eq("tenant_id",tenantId).in("party_type",["supplier","both"]).order("name"),
   db.from("purchase_invoices").select("id,goods_receipt_id,supplier_id,supplier_invoice_no,invoice_date,due_date,subtotal,tax_amount,grand_total,status,posted_at").eq("tenant_id",tenantId).order("invoice_date",{ascending:false}).limit(300)
  ]);
  const err=g.error||o.error||p.error||i.error;if(err)setNotice(err.message);else{setGrns(g.data??[]);setOrders(o.data??[]);setParties(p.data??[]);setInvoices(i.data??[]);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 const availableGrns=grns.filter(g=>!invoices.some(i=>i.goods_receipt_id===g.id));
 async function create(e:FormEvent){
  e.preventDefault();if(!canCreate)return;setSaving(true);setNotice("");
  try{
   if(!selectedGrn||!invoiceNo.trim())throw new Error("Select a posted GRN and enter the supplier's invoice number.");
   const amount=Number(tax);if(!Number.isFinite(amount)||amount<0)throw new Error("Tax amount must be zero or greater.");
   const {data,error}=await db.rpc("create_purchase_invoice",{p_goods_receipt_id:selectedGrn,p_supplier_invoice_no:invoiceNo.trim(),p_invoice_date:invoiceDate,p_due_date:dueDate||null,p_tax_amount:amount,p_notes:notes.trim()||null});
   if(error)throw error;if(data?.success!==true)throw new Error("Supplier invoice draft was not confirmed.");
   setNotice("Supplier invoice matched to GRN. Net value "+money(data.subtotal)+", total "+money(data.grand_total)+".");
   setSelectedGrn("");setInvoiceNo("");setTax("0");setDueDate("");setNotes("");await load();
  }catch(err){setNotice(err instanceof Error?err.message:"Supplier invoice could not be created.");}
  finally{setSaving(false);}
 }
 async function post(id:string){
  setSaving(true);setNotice("");
  try{const {data,error}=await db.rpc("post_purchase_invoice",{p_purchase_invoice_id:id});if(error)throw error;if(data?.success!==true)throw new Error("Supplier invoice posting was not confirmed.");setNotice("Supplier invoice posted. GRNI cleared and accounts payable recognized.");await load();}
  catch(err){setNotice(err instanceof Error?err.message:"Supplier invoice posting failed.");}finally{setSaving(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Supplier Invoices & Accounts Payable</h2><p>Match supplier bills to posted goods receipts, recognize tax and post the payable control ledger.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {canCreate&&<form className="transaction-form" onSubmit={create}><h3>Match a supplier invoice to a posted GRN</h3><div className="form-grid">
   <label>Posted goods receipt<select required value={selectedGrn} onChange={e=>setSelectedGrn(e.target.value)}><option value="">Select uninvoiced GRN</option>{availableGrns.map(g=>{const po=orders.find(x=>x.id===g.purchase_order_id),supplier=parties.find(x=>x.id===po?.supplier_id);return <option key={g.id} value={g.id}>{g.grn_number} · {supplier?.name||"Supplier"} · {g.received_date}</option>;})}</select></label>
   <label>Supplier invoice number<input required value={invoiceNo} onChange={e=>setInvoiceNo(e.target.value)}/></label>
   <label>Invoice date<input type="date" required value={invoiceDate} onChange={e=>setInvoiceDate(e.target.value)}/></label>
   <label>Due date<input type="date" min={invoiceDate} value={dueDate} onChange={e=>setDueDate(e.target.value)}/></label>
   <label>Input tax amount (PKR)<input type="number" min="0" step="0.01" value={tax} onChange={e=>setTax(e.target.value)}/></label>
   <label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)}/></label>
  </div><p className="module-footnote">The invoice net amount is matched to accepted GRN quantities and costs. Differences must be corrected in the GRN/PO before posting; input tax is recorded separately.</p><button disabled={saving||!availableGrns.length}>{saving?"Creating…":"Create matched invoice draft"}</button></form>}
  <h3>Supplier invoice register</h3>
  {loading?<div className="table-empty">Loading supplier invoices…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Supplier</th><th>GRN</th><th>Supplier invoice</th><th>Date</th><th>Due</th><th>Net</th><th>Tax</th><th>Total</th><th>Status</th><th>Action</th></tr></thead><tbody>{invoices.map(i=>{const g=grns.find(x=>x.id===i.goods_receipt_id);const supplier=parties.find(x=>x.id===i.supplier_id);return <tr key={i.id}><td>{supplier?.name||i.supplier_id}</td><td>{g?.grn_number||"—"}</td><td>{i.supplier_invoice_no}</td><td>{i.invoice_date}</td><td>{i.due_date||"—"}</td><td>{money(i.subtotal)}</td><td>{money(i.tax_amount)}</td><td>{money(i.grand_total)}</td><td>{i.status}</td><td>{i.status==="draft"&&canPost?<button disabled={saving} onClick={()=>void post(i.id)}>Post to AP</button>:i.status==="posted"?"Posted":"—"}</td></tr>;})}{!invoices.length&&<tr><td colSpan={10} className="table-empty">No supplier invoices have been matched yet.</td></tr>}</tbody></table></div>}
 </section>;
}
