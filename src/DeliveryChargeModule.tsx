import {useEffect,useState,type FormEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Row=Record<string,any>;
const money=(n:number)=>"PKR "+Number(n||0).toLocaleString("en-PK",{maximumFractionDigits:2});
export default function DeliveryChargeModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const canManage=["owner","admin","manager"].includes(currentRole),canCollect=canManage||["accounts","delivery_man"].includes(currentRole);
 const [routes,setRoutes]=useState<Row[]>([]),[deliveries,setDeliveries]=useState<Row[]>([]),[orders,setOrders]=useState<Row[]>([]),[parties,setParties]=useState<Row[]>([]),[rules,setRules]=useState<Row[]>([]),[charges,setCharges]=useState<Row[]>([]);
 const [form,setForm]=useState({route_id:"",customer_id:"",charge_type:"fixed",amount:"0",min_order_amount:"0",free_delivery_above:"",priority:"0",notes:""});
 const [collection,setCollection]=useState<Record<string,string>>({}),[method,setMethod]=useState<Record<string,string>>({}),[reference,setReference]=useState<Record<string,string>>({});
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 async function load(){
  setLoading(true);setNotice("");
  const [r,d,o,p,ru,ch]=await Promise.all([
   db.from("sales_routes").select("id,route_code,name,area_description").eq("tenant_id",tenantId).eq("is_active",true).order("name"),
   db.from("deliveries").select("id,delivery_number,sales_order_id,route_id,delivery_date,status,delivery_man_employee_id").eq("tenant_id",tenantId).order("delivery_date",{ascending:false}).limit(150),
   db.from("sales_orders").select("id,order_number,customer_id,grand_total").eq("tenant_id",tenantId),
   db.from("parties").select("id,name").eq("tenant_id",tenantId).in("party_type",["customer","both"]),
   db.from("delivery_charge_rules").select("*").eq("tenant_id",tenantId).order("priority",{ascending:false}),
   db.from("delivery_charges").select("*").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(150)
  ]);
  const err=[r,d,o,p,ru,ch].find(x=>x.error);if(err)setNotice(err.error.message);else{setRoutes(r.data||[]);setDeliveries(d.data||[]);setOrders(o.data||[]);setParties(p.data||[]);setRules(ru.data||[]);setCharges(ch.data||[]);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 async function saveRule(e:FormEvent){
  e.preventDefault();if(!canManage)return;setSaving(true);setNotice("");
  const {data:{session}}=await db.auth.getSession();
  const {error}=await db.from("delivery_charge_rules").insert({tenant_id:tenantId,route_id:form.route_id||null,customer_id:form.customer_id||null,charge_type:form.charge_type,amount:Number(form.amount),min_order_amount:Number(form.min_order_amount||0),free_delivery_above:form.free_delivery_above?Number(form.free_delivery_above):null,priority:Number(form.priority||0),is_active:true,notes:form.notes.trim()||null,created_by:session?.user.id||null});
  if(error)setNotice(error.message);else{setNotice("Delivery charge rule saved.");setForm({route_id:"",customer_id:"",charge_type:"fixed",amount:"0",min_order_amount:"0",free_delivery_above:"",priority:"0",notes:""});await load();}setSaving(false);
 }
 async function applyRule(deliveryId:string){
  setSaving(true);const {data,error}=await db.rpc("apply_delivery_charge_rule",{p_delivery_id:deliveryId});if(error)setNotice(error.message);else setNotice("Delivery charge calculated: "+money(Number(data?.charge_amount||0))+" ("+data?.status+").");await load();setSaving(false);
 }
 async function collect(charge:Row){
  const amount=Number(collection[charge.id]||0);if(!amount)return;setSaving(true);
  const {error}=await db.rpc("settle_delivery_charge",{p_charge_id:charge.id,p_amount:amount,p_payment_method:method[charge.id]||"cash",p_payment_reference:reference[charge.id]||null,p_waive:false});
  if(error)setNotice(error.message);else{setNotice("Delivery charge collection recorded.");setCollection(x=>({...x,[charge.id]:""}));await load();}setSaving(false);
 }
 async function waive(charge:Row){
  if(!canManage||!window.confirm("Waive this delivery charge?"))return;setSaving(true);
  const {error}=await db.rpc("settle_delivery_charge",{p_charge_id:charge.id,p_amount:0,p_payment_method:null,p_payment_reference:null,p_waive:true});
  if(error)setNotice(error.message);else{setNotice("Delivery charge waived by manager.");await load();}setSaving(false);
 }
 const chargeFor=(id:string)=>charges.find(x=>x.delivery_id===id),deliveryName=(id:string)=>deliveries.find(x=>x.id===id)?.delivery_number||id,customerName=(id:string)=>parties.find(x=>x.id===id)?.name||"—";
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Delivery Charges</h2><p>Route/customer charge rules, order-value thresholds, collections and waivers.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {canManage&&<form className="transaction-form" onSubmit={saveRule}><h3>Configure delivery charge rule</h3><div className="form-grid"><label>Route (optional)<select value={form.route_id} onChange={e=>setForm({...form,route_id:e.target.value})}><option value="">All routes</option>{routes.map(x=><option key={x.id} value={x.id}>{x.route_code} · {x.name}</option>)}</select></label><label>Customer (optional)<select value={form.customer_id} onChange={e=>setForm({...form,customer_id:e.target.value})}><option value="">All customers</option>{parties.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select></label><label>Charge method<select value={form.charge_type} onChange={e=>setForm({...form,charge_type:e.target.value})}><option value="fixed">Fixed amount</option><option value="percentage">Percentage of order</option></select></label><label>{form.charge_type==="fixed"?"Charge amount (PKR)":"Charge rate (%)"}<input required type="number" min="0" step="0.01" value={form.amount} onChange={e=>setForm({...form,amount:e.target.value})}/></label><label>Minimum order value (PKR)<input type="number" min="0" step="0.01" value={form.min_order_amount} onChange={e=>setForm({...form,min_order_amount:e.target.value})}/></label><label>Free delivery above (PKR)<input type="number" min="0" step="0.01" value={form.free_delivery_above} onChange={e=>setForm({...form,free_delivery_above:e.target.value})} placeholder="Optional"/></label><label>Priority<input type="number" step="1" value={form.priority} onChange={e=>setForm({...form,priority:e.target.value})}/></label><label>Notes<input value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label></div><button className="primary-action" disabled={saving}>Save charge rule</button></form>}
  <div className="data-table-wrap"><h3>Active charge rules</h3><table className="data-table"><thead><tr><th>Scope</th><th>Method</th><th>Amount / Rate</th><th>Minimum order</th><th>Free above</th><th>Priority</th><th>Status</th></tr></thead><tbody>{rules.map(x=><tr key={x.id}><td>{x.customer_id?customerName(x.customer_id):"All customers"} · {x.route_id?routes.find(r=>r.id===x.route_id)?.name||"Route":"All routes"}</td><td>{x.charge_type}</td><td>{x.charge_type==="fixed"?money(x.amount):Number(x.amount)+"%"}</td><td>{money(x.min_order_amount)}</td><td>{x.free_delivery_above?money(x.free_delivery_above):"—"}</td><td>{x.priority}</td><td>{x.is_active?"Active":"Inactive"}</td></tr>)}{!rules.length&&<tr><td colSpan={7} className="table-empty">No delivery charge rules configured.</td></tr>}</tbody></table></div>
  <div className="data-table-wrap"><h3>Delivery charge register</h3><table className="data-table"><thead><tr><th>Delivery</th><th>Customer</th><th>Route</th><th>Order value</th><th>Charge</th><th>Collected</th><th>Balance</th><th>Status / action</th></tr></thead><tbody>{charges.map(x=><tr key={x.id}><td>{deliveryName(x.delivery_id)}</td><td>{customerName(x.customer_id)}</td><td>{routes.find(r=>r.id===x.route_id)?.name||"—"}</td><td>{money(x.base_order_value)}</td><td>{money(x.charge_amount)}</td><td>{money(x.collected_amount)}</td><td>{money(Number(x.charge_amount)-Number(x.collected_amount))}</td><td><div>{x.status}</div>{canCollect&&["pending","partially_paid"].includes(x.status)&&<div className="inline-form"><input type="number" min="0.01" max={Number(x.charge_amount)-Number(x.collected_amount)} step="0.01" placeholder="Collect" value={collection[x.id]||""} onChange={e=>setCollection(v=>({...v,[x.id]:e.target.value}))}/><select value={method[x.id]||"cash"} onChange={e=>setMethod(v=>({...v,[x.id]:e.target.value}))}><option value="cash">Cash</option><option value="bank">Bank</option><option value="other">Other</option></select><input placeholder="Reference" value={reference[x.id]||""} onChange={e=>setReference(v=>({...v,[x.id]:e.target.value}))}/><button disabled={saving} onClick={()=>void collect(x)}>Collect</button>{canManage&&<button disabled={saving} onClick={()=>void waive(x)}>Waive</button>}</div>}</td></tr>)}{!charges.length&&<tr><td colSpan={8} className="table-empty">No delivery charges recorded yet.</td></tr>}</tbody></table></div>
  <div className="data-table-wrap"><h3>Apply charge rules to deliveries</h3><table className="data-table"><thead><tr><th>Delivery</th><th>Customer</th><th>Order total</th><th>Route</th><th>Status</th><th>Charge</th></tr></thead><tbody>{deliveries.filter(d=>!chargeFor(d.id)).map(d=>{const o=orders.find(x=>x.id===d.sales_order_id);return <tr key={d.id}><td>{d.delivery_number}</td><td>{customerName(o?.customer_id)}</td><td>{money(o?.grand_total||0)}</td><td>{routes.find(r=>r.id===d.route_id)?.name||"—"}</td><td>{d.status}</td><td><button disabled={saving||!rules.length} onClick={()=>void applyRule(d.id)}>Apply matching rule</button></td></tr>})}{!deliveries.some(d=>!chargeFor(d.id))&&<tr><td colSpan={6} className="table-empty">Every listed delivery already has a charge record, or there are no deliveries.</td></tr>}</tbody></table></div>
  <p className="module-footnote">Charges are calculated from the most specific matching customer/route rule and can be partially collected, paid or waived. This register records collections; it does not yet post delivery-charge revenue into the general ledger or add it to the sales invoice total.</p>
 </section>;
}
