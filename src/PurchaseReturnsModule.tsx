import {FormEvent,useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {useModuleAction} from "./lib/modulePermissionContext";
type Row=Record<string,any>;
export default function PurchaseReturnsModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [grns,setGrns]=useState<Row[]>([]),[orders,setOrders]=useState<Row[]>([]),[parties,setParties]=useState<Row[]>([]),[products,setProducts]=useState<Row[]>([]),[notes,setNotes]=useState<Row[]>([]),[lines,setLines]=useState<Row[]>([]);
 const [selectedGrn,setSelectedGrn]=useState(""),[reason,setReason]=useState(""),[noteDate,setNoteDate]=useState(new Date().toISOString().slice(0,10));
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[show,setShow]=useState(false),[notice,setNotice]=useState("");
 const canCreate=useModuleAction("purchase_supplier","create",["owner","admin","manager","purchase"].includes(currentRole));
 const canPost=useModuleAction("purchase_supplier","update",["owner","admin","manager","accounts","warehouse"].includes(currentRole));
 const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
 async function load(){
  setLoading(true);setNotice("");
  const [g,o,p,pr,n,l]=await Promise.all([
   db.from("goods_receipts").select("id,grn_number,received_date,purchase_order_id,warehouse_id,status").eq("tenant_id",tenantId).eq("status","posted").order("received_date",{ascending:false}).limit(300),
   db.from("purchase_orders").select("id,po_number,supplier_id").eq("tenant_id",tenantId),
   db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",["supplier","both"]).order("name"),
   db.from("products").select("id,name,sku").eq("tenant_id",tenantId),
   db.from("purchase_debit_notes").select("id,goods_receipt_id,supplier_id,debit_note_number,note_date,reason,status,subtotal,warehouse_id").eq("tenant_id",tenantId).order("note_date",{ascending:false}).limit(300),
   db.from("purchase_debit_note_lines").select("goods_receipt_line_id,quantity").eq("tenant_id",tenantId)
  ]);
  const err=g.error||o.error||p.error||pr.error||n.error||l.error;if(err)setNotice(err.message);else{setGrns(g.data??[]);setOrders(o.data??[]);setParties(p.data??[]);setProducts(pr.data??[]);setNotes(n.data??[]);setLines(l.data??[]);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 async function chooseGrn(id:string){
  setSelectedGrn(id);setNotice("");if(!id){setLines([]);return;}
  const {data,error}=await db.from("goods_receipt_lines").select("id,product_id,unit_id,quantity,conversion_to_base,accepted_quantity,unit_cost,batch_number,expiry_date").eq("tenant_id",tenantId).eq("goods_receipt_id",id).gt("accepted_quantity",0);
  if(error){setNotice(error.message);return;}
  const used=new Map<string,number>();const {data:old,error:oldError}=await db.from("purchase_debit_note_lines").select("goods_receipt_line_id,quantity,purchase_debit_notes!inner(status)").eq("tenant_id",tenantId).in("goods_receipt_line_id",(data??[]).map(x=>x.id));
  if(oldError){setNotice(oldError.message);return;}
  for(const x of old??[]){if(["draft","posted"].includes(x.purchase_debit_notes?.[0]?.status))used.set(x.goods_receipt_line_id,(used.get(x.goods_receipt_line_id)||0)+Number(x.quantity));}
  setLines((data??[]).map(x=>({...x,already_returned:used.get(x.id)||0,return_quantity:"0"})));
 }
 async function create(e:FormEvent){
  e.preventDefault();if(!canCreate)return;setSaving(true);setNotice("");
  try{
   const selected=lines.filter(x=>Number(x.return_quantity)>0);
   if(!selectedGrn||!reason.trim()||!selected.length)throw new Error("Select a GRN, enter the return reason and at least one return quantity.");
   if(selected.some(x=>Number(x.return_quantity)>Number(x.accepted_quantity)-Number(x.already_returned)))throw new Error("Return quantity exceeds the unreturned accepted quantity.");
   const {data,error}=await db.rpc("create_purchase_debit_note",{p_goods_receipt_id:selectedGrn,p_lines:selected.map(x=>({goods_receipt_line_id:x.id,quantity:Number(x.return_quantity)})),p_reason:reason.trim(),p_note_date:noteDate});
   if(error)throw error;if(data?.success!==true)throw new Error("Purchase return draft was not confirmed.");
   setNotice("Vendor debit note "+data.debit_note_number+" created for "+money(data.subtotal)+".");setShow(false);setReason("");setSelectedGrn("");setLines([]);await load();
  }catch(err){setNotice(err instanceof Error?err.message:"Purchase return could not be created.");}finally{setSaving(false);}
 }
 async function post(id:string){
  if(!canPost)return;
  setSaving(true);setNotice("");
  try{const {data,error}=await db.rpc("post_purchase_debit_note",{p_debit_note_id:id});if(error)throw error;if(data?.success!==true)throw new Error("Vendor return posting was not confirmed.");setNotice("Vendor debit note posted. Stock and GRNI/AP accounting updated.");await load();}
  catch(err){setNotice(err instanceof Error?err.message:"Vendor return posting failed.");}finally{setSaving(false);}
 }
 const availableGrns=grns;
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Purchase Returns & Vendor Debit Notes</h2><p>Return accepted goods against posted GRNs, validate quantities and reverse inventory and supplier liability.</p></div>{canCreate&&<button className="primary-action" onClick={()=>setShow(!show)}>{show?"Close form":"+ Create purchase return"}</button>}<button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {show&&<form className="transaction-form" onSubmit={create}><h3>New supplier return</h3><div className="form-grid">
   <label>Posted GRN<select required value={selectedGrn} onChange={e=>void chooseGrn(e.target.value)}><option value="">Select goods receipt</option>{availableGrns.map(g=>{const po=orders.find(x=>x.id===g.purchase_order_id),supplier=parties.find(x=>x.id===po?.supplier_id);return <option key={g.id} value={g.id}>{g.grn_number} · {supplier?.name||"Vendor"} · {g.received_date}</option>;})}</select></label>
   <label>Return date<input type="date" required value={noteDate} onChange={e=>setNoteDate(e.target.value)}/></label>
   <label>Reason<input required value={reason} onChange={e=>setReason(e.target.value)} placeholder="Damaged / expired / quality issue"/></label></div><p className="module-footnote">For correct supplier payable accounting, post the matched supplier invoice first; the debit note then reduces AP and removes stock from its original batch.</p><div className="form-grid">
  </div>
  {lines.length>0&&<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Product</th><th>Batch</th><th>Expiry</th><th>Accepted</th><th>Already returned</th><th>Return qty</th><th>Value</th></tr></thead><tbody>{lines.map(x=><tr key={x.id}><td>{products.find(p=>p.id===x.product_id)?.sku} · {products.find(p=>p.id===x.product_id)?.name||x.product_id}</td><td>{x.batch_number||"—"}</td><td>{x.expiry_date||"—"}</td><td>{x.accepted_quantity}</td><td>{x.already_returned}</td><td><input type="number" min="0" max={Number(x.accepted_quantity)-Number(x.already_returned)} step="0.001" value={x.return_quantity} onChange={e=>setLines(old=>old.map(y=>y.id===x.id?{...y,return_quantity:e.target.value}:y))}/></td><td>{money(Number(x.return_quantity||0)*Number(x.unit_cost||0))}</td></tr>)}</tbody></table></div>}
  <button disabled={saving||!lines.length}>{saving?"Creating…":"Create debit note draft"}</button></form>}
  <h3>Purchase return register</h3>
  {loading?<div className="table-empty">Loading supplier returns…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Debit note</th><th>Vendor</th><th>GRN</th><th>Date</th><th>Reason</th><th>Value</th><th>Status</th><th>Action</th></tr></thead><tbody>{notes.map(n=>{const g=grns.find(x=>x.id===n.goods_receipt_id),po=orders.find(x=>x.id===g?.purchase_order_id),supplier=parties.find(x=>x.id===n.supplier_id||x.id===po?.supplier_id);return <tr key={n.id}><td>{n.debit_note_number}</td><td>{supplier?.name||"—"}</td><td>{g?.grn_number||"—"}</td><td>{n.note_date}</td><td>{n.reason}</td><td>{money(n.subtotal)}</td><td>{n.status}</td><td>{n.status==="draft"&&canPost?<button disabled={saving} onClick={()=>void post(n.id)}>Post return</button>:n.status==="posted"?"Posted":"—"}</td></tr>;})}{!notes.length&&<tr><td colSpan={8} className="table-empty">No supplier returns recorded.</td></tr>}</tbody></table></div>}
 </section>;
}
