import {FormEvent,useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {getQueuedDeliveryVisits,queueDeliveryVisit,removeQueuedDeliveryVisit,cacheDeliverySnapshot,getDeliverySnapshot} from "./deliveryOfflineQueue";
type Row=Record<string,any>;
export default function DeliveryManModule({db,tenantId}:{db:SupabaseClient;tenantId:string}){
 const [employee,setEmployee]=useState<Row|null>(null),[deliveries,setDeliveries]=useState<Row[]>([]),[orders,setOrders]=useState<Row[]>([]),[customers,setCustomers]=useState<Row[]>([]),[products,setProducts]=useState<Row[]>([]),[lines,setLines]=useState<Row[]>([]),[visits,setVisits]=useState<Row[]>([]);
 const [form,setForm]=useState({delivery_id:"",visit_status:"delivered",notes:""}),[lineQuantities,setLineQuantities]=useState<Record<string,{delivered:string;marketReturn:string}>>({}),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 async function load(){
  setLoading(true);setNotice("");
  try{
   const {data:user}=await db.auth.getUser();if(!user.user)throw new Error("Please sign in again.");
   const {data:emp,error:empError}=await db.from("employees").select("id,full_name,employee_code").eq("tenant_id",tenantId).eq("user_id",user.user.id).maybeSingle();
   if(empError)throw empError;if(!emp)throw new Error("Your login is not linked to an active deliveryman employee record. Ask the administrator to link your staff account.");
   setEmployee(emp);
   const {data:d,error:dError}=await db.from("deliveries").select("id,delivery_number,sales_order_id,delivery_date,status,route_id").eq("tenant_id",tenantId).eq("delivery_man_employee_id",emp.id).order("delivery_date",{ascending:false}).limit(100);
   if(dError)throw dError;const deliveryRows=d??[];setDeliveries(deliveryRows);
   const ids=deliveryRows.map(x=>x.sales_order_id),deliveryIds=deliveryRows.map(x=>x.id);
   if(ids.length){
    const [o,l,v]=await Promise.all([
     db.from("sales_orders").select("id,order_number,customer_id,order_date").eq("tenant_id",tenantId).in("id",ids),
     db.from("delivery_lines").select("id,delivery_id,product_id,quantity_base,picked_quantity_base,delivered_quantity_base").eq("tenant_id",tenantId).in("delivery_id",deliveryIds),
     db.from("delivery_shop_visits").select("id,delivery_id,customer_id,visit_at,visit_status,notes,line_quantities").eq("tenant_id",tenantId).in("delivery_id",deliveryIds).order("visit_at",{ascending:false})
    ]);
    const err=o.error||l.error||v.error;if(err)throw err;setOrders(o.data??[]);setLines(l.data??[]);setVisits(v.data??[]);
    const customerIds=[...new Set((o.data??[]).map(x=>x.customer_id))],productIds=[...new Set((l.data??[]).map(x=>x.product_id))];
    const [cu,pr]=await Promise.all([
     customerIds.length?db.from("parties").select("id,name,phone,address").eq("tenant_id",tenantId).in("id",customerIds):Promise.resolve({data:[],error:null}),
     productIds.length?db.from("products").select("id,name,sku,barcode").eq("tenant_id",tenantId).in("id",productIds):Promise.resolve({data:[],error:null})
    ]);
    if(cu.error)throw cu.error;if(pr.error)throw pr.error;setCustomers(cu.data??[]);setProducts(pr.data??[]);
   await cacheDeliverySnapshot(tenantId,{employee:emp,deliveries:deliveryRows,orders:o.data??[],lines:l.data??[],visits:v.data??[],customers:cu.data??[],products:pr.data??[]});
   }else{setOrders([]);setLines([]);setVisits([]);setCustomers([]);setProducts([]);}
  }catch(e){
   if(!navigator.onLine){
    try{const cached=await getDeliverySnapshot(tenantId);const d=cached?.data;if(d){setEmployee((d.employee as Row)||null);setDeliveries((d.deliveries as Row[])||[]);setOrders((d.orders as Row[])||[]);setLines((d.lines as Row[])||[]);setVisits((d.visits as Row[])||[]);setCustomers((d.customers as Row[])||[]);setProducts((d.products as Row[])||[]);setNotice("Offline mode: showing the last saved assigned deliveries. New visits are queued on this device until connection returns.");}else setNotice("Offline and no delivery assignment snapshot is saved. Connect once to download your assignments.");}
    catch(cacheError){setNotice(cacheError instanceof Error?cacheError.message:"Offline delivery data could not be loaded.");}
   }else setNotice(e instanceof Error?e.message:"Assigned deliveries could not be loaded.");
  }
  setLoading(false);
 }
 async function syncPendingVisits(){
  if(!navigator.onLine)return;
  try{
   const pending=await getQueuedDeliveryVisits(tenantId);
   for(const item of pending){
    const {error}=await db.from("delivery_shop_visits").upsert({tenant_id:item.tenant_id,delivery_id:item.delivery_id,delivery_man_employee_id:item.delivery_man_employee_id,customer_id:item.customer_id,visit_status:item.visit_status,shops_visited:item.shops_visited,line_quantities:item.line_quantities,notes:item.notes,created_by:item.created_by},{onConflict:"tenant_id,delivery_id"});
    if(error)throw error;
    await removeQueuedDeliveryVisit(item.id);
   }
   if(pending.length)setNotice(pending.length+" offline delivery visit(s) synchronized.");
  }catch(e){setNotice(e instanceof Error?"Offline sync pending: "+e.message:"Offline sync will retry when connected.");}
 }
 useEffect(()=>{void load();const onOnline=()=>{void syncPendingVisits().then(()=>load());};window.addEventListener("online",onOnline);return()=>window.removeEventListener("online",onOnline);},[tenantId]);
 async function saveVisit(e:FormEvent){
  e.preventDefault();if(!employee)return;setSaving(true);setNotice("");
  try{
   const d=deliveries.find(x=>x.id===form.delivery_id),o=orders.find(x=>x.id===d?.sales_order_id);
   if(!d||!o)throw new Error("Select one of your assigned deliveries.");
   const {data:user}=await db.auth.getUser();
   const selectedLines=lines.filter(x=>x.delivery_id===d.id);
   const quantityReport=selectedLines.map(x=>({delivery_line_id:x.id,product_id:x.product_id,picked_quantity_base:Number(x.picked_quantity_base||0),delivered_quantity_base:Number(lineQuantities[x.id]?.delivered||0),market_return_quantity_base:Number(lineQuantities[x.id]?.marketReturn||0)}));
   for(const q of quantityReport){if(!Number.isFinite(q.delivered_quantity_base)||q.delivered_quantity_base<0||q.delivered_quantity_base>q.picked_quantity_base)throw new Error("Delivered quantity must be between zero and picked quantity.");if(!Number.isFinite(q.market_return_quantity_base)||q.market_return_quantity_base<0||q.market_return_quantity_base>q.delivered_quantity_base)throw new Error("Market return quantity cannot exceed delivered quantity.");}
   const payload={tenant_id:tenantId,delivery_id:d.id,delivery_man_employee_id:employee.id,customer_id:o.customer_id,visit_status:form.visit_status,shops_visited:1,line_quantities:quantityReport,notes:form.notes.trim()||null,created_by:user.user?.id??null};
   if(!navigator.onLine){
    await queueDeliveryVisit({id:crypto.randomUUID(),...payload,created_by:payload.created_by||null,queued_at:new Date().toISOString()});
    setNotice("No internet: delivery visit safely queued on this device. It will sync when connection returns.");
   }else{
    const {error}=await db.from("delivery_shop_visits").upsert(payload,{onConflict:"tenant_id,delivery_id"});
    if(error){
     if(/fetch|network|offline|connection/i.test(error.message||"")){
      await queueDeliveryVisit({id:crypto.randomUUID(),...payload,created_by:payload.created_by||null,queued_at:new Date().toISOString()});
      setNotice("Connection interrupted: delivery visit queued for automatic synchronization.");
     }else throw error;
    }else setNotice("Shop visit saved. Delivered quantities and invoice are finalized by the warehouse/manager confirmation.");
   }setForm({delivery_id:"",visit_status:"delivered",notes:""});setLineQuantities({});if(navigator.onLine)await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Shop visit could not be saved.");}
  setSaving(false);
 }
 const customerFor=(delivery:Row)=>customers.find(x=>x.id===orders.find(o=>o.id===delivery.sales_order_id)?.customer_id);
 const selectedDeliveryLines=lines.filter(x=>x.delivery_id===form.delivery_id);
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Delivery Man App</h2><p>Assigned deliveries, customer stops, product quantities and visit outcomes, with offline assignment snapshots and queued synchronization.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {loading?<div className="table-empty">Loading assigned deliveries…</div>:!employee?<div className="notice">Employee account is not linked.</div>:<>
   <p className="module-footnote">Signed in as {employee.full_name} · {employee.employee_code}</p>
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Delivery</th><th>Sales order</th><th>Customer</th><th>Route</th><th>Status</th><th>Items</th></tr></thead><tbody>
    {deliveries.map(d=><tr key={d.id}><td>{d.delivery_number}</td><td>{orders.find(o=>o.id===d.sales_order_id)?.order_number||"—"}</td><td>{customerFor(d)?.name||"—"}</td><td>{d.route_id||"—"}</td><td>{d.status}</td><td>{lines.filter(l=>l.delivery_id===d.id).map(l=><div key={l.id}>{products.find(p=>p.id===l.product_id)?.name||l.product_id} · Picked {Number(l.picked_quantity_base||0)} / Delivered {Number(l.delivered_quantity_base||0)} base</div>)}</td></tr>)}
    {!deliveries.length&&<tr><td colSpan={6} className="table-empty">No deliveries are currently assigned to your account.</td></tr>}
   </tbody></table></div>
   <form className="transaction-form" onSubmit={saveVisit}><h3>Record customer shop visit</h3><div className="form-grid">
    <label>Assigned delivery / customer<select required value={form.delivery_id} onChange={e=>setForm(x=>({...x,delivery_id:e.target.value}))}><option value="">Select delivery</option>{deliveries.map(d=><option key={d.id} value={d.id}>{d.delivery_number} · {customerFor(d)?.name||orders.find(o=>o.id===d.sales_order_id)?.order_number||"Customer"}</option>)}</select></label>
    <label>Visit result<select value={form.visit_status} onChange={e=>setForm(x=>({...x,visit_status:e.target.value}))}><option value="delivered">Delivered</option><option value="short_delivered">Short delivered</option><option value="not_available">Shop not available</option><option value="market_return">Market return</option><option value="refused">Customer refused</option></select></label>
    <label>Notes<input value={form.notes} onChange={e=>setForm(x=>({...x,notes:e.target.value}))} placeholder="Reason, returned items, customer remarks"/></label>
   </div><button disabled={saving||!form.delivery_id}>{saving?"Saving…":"Save shop visit"}</button></form>
   <h3>Visit history</h3><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Delivery</th><th>Customer</th><th>Result</th><th>Notes</th></tr></thead><tbody>{visits.map(v=><tr key={v.id}><td>{new Date(v.visit_at).toLocaleString("en-PK")}</td><td>{deliveries.find(d=>d.id===v.delivery_id)?.delivery_number||"—"}</td><td>{customers.find(c=>c.id===v.customer_id)?.name||"—"}</td><td>{v.visit_status.replaceAll("_"," ")}{Array.isArray(v.line_quantities)&&v.line_quantities.length>0?<div>{v.line_quantities.map((q:Row,i:number)=><div key={i}>Delivered {q.delivered_quantity_base} · Market return {q.market_return_quantity_base}</div>)}</div>:null}</td><td>{v.notes||"—"}</td></tr>)}{!visits.length&&<tr><td colSpan={5} className="table-empty">No visits recorded yet.</td></tr>}</tbody></table></div>
  </>}
  <p className="module-footnote">Assigned delivery data is cached locally for offline viewing on this device. Visit updates are queued and replayed with the tenant+delivery unique key when online. Final inventory issue, returns and invoice posting remain controlled by warehouse/manager confirmation.</p>
 </section>;
}