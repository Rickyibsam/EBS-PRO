import {fetchAllRowsResult} from "./lib/fetchAllRows";
import {FormEvent,useEffect,useState,useRef} from "react";
import type {PointerEvent as ReactPointerEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {isTransientNetworkError} from "./lib/network";
import {getQueuedDeliveryVisits,queueDeliveryVisit,removeQueuedDeliveryVisit,cacheDeliverySnapshot,getDeliverySnapshot} from "./deliveryOfflineQueue";
type Row=Record<string,any>;
let deferredInstallPrompt:any=null;
if(typeof window!=="undefined")window.addEventListener("beforeinstallprompt",(event:Event)=>{event.preventDefault();deferredInstallPrompt=event;});
export default function DeliveryManModule({db,tenantId}:{db:SupabaseClient;tenantId:string}){
 const [authUserId,setAuthUserId]=useState(""),[employee,setEmployee]=useState<Row|null>(null),[deliveries,setDeliveries]=useState<Row[]>([]),[orders,setOrders]=useState<Row[]>([]),[customers,setCustomers]=useState<Row[]>([]),[products,setProducts]=useState<Row[]>([]),[lines,setLines]=useState<Row[]>([]),[visits,setVisits]=useState<Row[]>([]);
 const [form,setForm]=useState({delivery_id:"",visit_status:"delivered",notes:""}),[lineQuantities,setLineQuantities]=useState<Record<string,{delivered:string;marketReturn:string;returnBatch:string;returnExpiry:string}>>({}),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const [pendingVisitCount,setPendingVisitCount]=useState(0),[syncingQueue,setSyncingQueue]=useState(false);
 const syncingVisits=useRef(false);
 const [signaturePoints,setSignaturePoints]=useState<Array<{x:number;y:number;move:boolean}>>([]);
 const signatureCanvas=useRef<HTMLCanvasElement|null>(null),signatureDrawing=useRef(false);
 const [installPrompt,setInstallPrompt]=useState<any>(deferredInstallPrompt);
 useEffect(()=>{const handler=(event:Event)=>{event.preventDefault();setInstallPrompt(event as any);};window.addEventListener("beforeinstallprompt",handler);return()=>window.removeEventListener("beforeinstallprompt",handler);},[]);
 async function load(){
  setLoading(true);setNotice("");
  try{
   const {data:user}=await db.auth.getUser();if(!user.user)throw new Error("Please sign in again.");setAuthUserId(user.user.id);
   const {data:emp,error:empError}=await db.from("employees").select("id,full_name,employee_code").eq("tenant_id",tenantId).eq("user_id",user.user.id).maybeSingle();
   if(empError)throw empError;if(!emp)throw new Error("Your login is not linked to an active deliveryman employee record. Ask the administrator to link your staff account.");
   setEmployee(emp);
   const {data:d,error:dError}=await fetchAllRowsResult<any>((from,to)=>db.from("deliveries").select("id,delivery_number,sales_order_id,delivery_date,status,route_id,vehicle_number").eq("tenant_id",tenantId).eq("delivery_man_employee_id",emp.id).order("delivery_date",{ascending:false}).order("id",{ascending:true}).range(from,to));
   if(dError)throw dError;const deliveryRows=d??[];setDeliveries(deliveryRows);
   const ids=deliveryRows.map(x=>x.sales_order_id),deliveryIds=deliveryRows.map(x=>x.id);
   if(ids.length){
    const [o,l,v]=await Promise.all([
     db.from("sales_orders").select("id,order_number,customer_id,order_date").eq("tenant_id",tenantId).in("id",ids),
     db.from("delivery_lines").select("id,delivery_id,product_id,quantity_base,picked_quantity_base,delivered_quantity_base").eq("tenant_id",tenantId).in("delivery_id",deliveryIds),
     db.from("delivery_shop_visits").select("id,delivery_id,customer_id,visit_at,visit_status,notes,line_quantities,proof_of_delivery_signature,latitude,longitude").eq("tenant_id",tenantId).in("delivery_id",deliveryIds).order("visit_at",{ascending:false})
    ]);
    const err=o.error||l.error||v.error;if(err)throw err;setOrders(o.data??[]);setLines(l.data??[]);setVisits(v.data??[]);
    const customerIds=[...new Set((o.data??[]).map(x=>x.customer_id))],productIds=[...new Set((l.data??[]).map(x=>x.product_id))];
    const [cu,pr]=await Promise.all([
     customerIds.length?db.from("parties").select("id,name,phone,address").eq("tenant_id",tenantId).in("id",customerIds):Promise.resolve({data:[],error:null}),
     productIds.length?db.from("products").select("id,name,sku,barcode").eq("tenant_id",tenantId).in("id",productIds):Promise.resolve({data:[],error:null})
    ]);
    if(cu.error)throw cu.error;if(pr.error)throw pr.error;setCustomers(cu.data??[]);setProducts(pr.data??[]);
   await cacheDeliverySnapshot(tenantId,user.user.id,{employee:emp,deliveries:deliveryRows,orders:o.data??[],lines:l.data??[],visits:v.data??[],customers:cu.data??[],products:pr.data??[]});
   }else{setOrders([]);setLines([]);setVisits([]);setCustomers([]);setProducts([]);await cacheDeliverySnapshot(tenantId,user.user.id,{employee:emp,deliveries:[],orders:[],lines:[],visits:[],customers:[],products:[]});}
  }catch(e){
   if(!navigator.onLine||/fetch|network|offline|connection|timeout/i.test(e instanceof Error?e.message:"")){
    try{const {data:{session}}=await db.auth.getSession();const offlineUserId=session?.user.id||"";if(!offlineUserId)throw new Error("Sign in on this device before viewing offline delivery assignments.");setAuthUserId(offlineUserId);const cached=await getDeliverySnapshot(tenantId,offlineUserId);const d=cached?.data;if(d){setEmployee((d.employee as Row)||null);setDeliveries((d.deliveries as Row[])||[]);setOrders((d.orders as Row[])||[]);setLines((d.lines as Row[])||[]);setVisits((d.visits as Row[])||[]);setCustomers((d.customers as Row[])||[]);setProducts((d.products as Row[])||[]);setNotice("Offline mode: showing the last saved assigned deliveries. New visits are queued on this device until connection returns.");}else setNotice("Offline and no delivery assignment snapshot is saved. Connect once to download your assignments.");}
    catch(cacheError){setNotice(cacheError instanceof Error?cacheError.message:"Offline delivery data could not be loaded.");}
   }else setNotice(e instanceof Error?e.message:"Assigned deliveries could not be loaded.");
  }
  setLoading(false);
 }
 function signaturePoint(e:ReactPointerEvent<HTMLCanvasElement>){
  const canvas=e.currentTarget,rect=canvas.getBoundingClientRect();
  return {x:(e.clientX-rect.left)*(canvas.width/rect.width),y:(e.clientY-rect.top)*(canvas.height/rect.height)};
 }
 function beginSignature(e:ReactPointerEvent<HTMLCanvasElement>){
  const canvas=e.currentTarget,point=signaturePoint(e),ctx=canvas.getContext("2d");if(!ctx)return;
  canvas.setPointerCapture(e.pointerId);signatureDrawing.current=true;ctx.lineWidth=2.4;ctx.lineCap="round";ctx.lineJoin="round";ctx.strokeStyle="#163e43";ctx.beginPath();ctx.moveTo(point.x,point.y);setSignaturePoints(old=>old.length<4000?[...old,{...point,move:true}]:old);
 }
 function moveSignature(e:ReactPointerEvent<HTMLCanvasElement>){
  if(!signatureDrawing.current||signaturePoints.length>=4000)return;
  const canvas=e.currentTarget,point=signaturePoint(e),ctx=canvas.getContext("2d");if(!ctx)return;
  ctx.lineTo(point.x,point.y);ctx.stroke();setSignaturePoints(old=>old.length<4000?[...old,{...point,move:false}]:old);
 }
 function endSignature(){signatureDrawing.current=false;}
 function clearSignature(){const canvas=signatureCanvas.current;if(canvas){const ctx=canvas.getContext("2d");ctx?.clearRect(0,0,canvas.width,canvas.height);}setSignaturePoints([]);}
 async function syncPendingVisits(){
  if(!navigator.onLine||syncingVisits.current)return;
  syncingVisits.current=true;setSyncingQueue(true);
  try{
   const {data:{session}}=await db.auth.getSession();const userId=session?.user.id||authUserId;if(!userId)return;const pending=await getQueuedDeliveryVisits(tenantId,userId);setPendingVisitCount(pending.length);
   let synchronized=0;
   for(const item of pending){
    const {error}=await db.rpc("record_van_delivery_visit",{p_delivery_id:item.delivery_id,p_visit_status:item.visit_status,p_line_quantities:item.line_quantities,p_notes:item.notes,p_idempotency_key:item.idempotency_key,p_signature:item.proof_of_delivery_signature||[],p_latitude:item.latitude??null,p_longitude:item.longitude??null});
    if(error)throw error;
    await removeQueuedDeliveryVisit(item.id);synchronized+=1;setPendingVisitCount(Math.max(0,pending.length-synchronized));
   }
   if(pending.length)setNotice(pending.length+" offline delivery visit(s) synchronized.");
  }catch(e){setNotice(e instanceof Error?"Offline sync pending: "+e.message:"Offline sync will retry when connected.");}
  finally{syncingVisits.current=false;setSyncingQueue(false);}
 }
 useEffect(()=>{void load();if(navigator.onLine)void syncPendingVisits();const onOnline=()=>{void syncPendingVisits().then(()=>load());};window.addEventListener("online",onOnline);return()=>window.removeEventListener("online",onOnline);},[tenantId]);
 useEffect(()=>{
  if(!navigator.onLine||saving||syncingQueue||pendingVisitCount===0)return;
  const retry=window.setTimeout(()=>void syncPendingVisits(),30000);
  return()=>window.clearTimeout(retry);
 },[pendingVisitCount,saving,syncingQueue,tenantId]);
 async function saveVisit(e:FormEvent){
  e.preventDefault();if(!employee)return;setSaving(true);setNotice("");
  try{
   const d=deliveries.find(x=>x.id===form.delivery_id),o=orders.find(x=>x.id===d?.sales_order_id);
   if(!d||!o)throw new Error("Select one of your assigned deliveries.");
   const {data:{session}}=await db.auth.getSession();
   if(!session?.user?.id)throw new Error("Your signed-in session is not available on this device. Sign in once while online before saving offline visits.");
   if(!navigator.geolocation)throw new Error("GPS is not supported by this device/browser. Enable location services and retry.");
   const position=await new Promise<GeolocationPosition>((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,reject,{enableHighAccuracy:true,timeout:15000,maximumAge:30000}));
   const latitude=position.coords.latitude,longitude=position.coords.longitude;
   if(!Number.isFinite(latitude)||!Number.isFinite(longitude))throw new Error("The device did not return valid GPS coordinates.");
   const selectedLines=lines.filter(x=>x.delivery_id===d.id);
   const quantityReport=selectedLines.map(x=>({delivery_line_id:x.id,product_id:x.product_id,picked_quantity_base:Number(x.picked_quantity_base||0),delivered_quantity_base:Number(lineQuantities[x.id]?.delivered??x.picked_quantity_base??0),market_return_quantity_base:Number(lineQuantities[x.id]?.marketReturn||0),return_batch_number:lineQuantities[x.id]?.returnBatch||null,return_expiry_date:lineQuantities[x.id]?.returnExpiry||null}));
   for(const q of quantityReport){if(!Number.isFinite(q.delivered_quantity_base)||q.delivered_quantity_base<0||q.delivered_quantity_base>q.picked_quantity_base)throw new Error("Delivered quantity must be between zero and picked quantity.");if(!Number.isFinite(q.market_return_quantity_base)||q.market_return_quantity_base<0||q.market_return_quantity_base>q.delivered_quantity_base)throw new Error("Market return quantity cannot exceed delivered quantity.");}
   if(["delivered","short_delivered"].includes(form.visit_status)&&signaturePoints.length<2)throw new Error("Customer signature is required before a delivered or short-delivered visit can be posted.");
   const payload={idempotency_key:crypto.randomUUID(),vehicle_number:d.vehicle_number||"",user_id:authUserId,tenant_id:tenantId,delivery_id:d.id,delivery_man_employee_id:employee.id,customer_id:o.customer_id,visit_status:form.visit_status,shops_visited:1,line_quantities:quantityReport,notes:form.notes.trim()||null,created_by:session.user.id,queued_at:new Date().toISOString(),proof_of_delivery_signature:signaturePoints,latitude,longitude};
   if(!navigator.onLine){
    await queueDeliveryVisit({...payload,id:crypto.randomUUID(),created_by:payload.created_by||null});
    setNotice("No internet: delivery visit safely queued on this device. It will sync when connection returns.");
   }else{
    const {data:result,error}=await db.rpc("record_van_delivery_visit",{p_delivery_id:d.id,p_visit_status:form.visit_status,p_line_quantities:quantityReport,p_notes:form.notes.trim()||null,p_idempotency_key:payload.idempotency_key,p_signature:signaturePoints,p_latitude:latitude,p_longitude:longitude});
    if(error){
     if(isTransientNetworkError(error)){
      await queueDeliveryVisit({...payload,id:crypto.randomUUID(),created_by:payload.created_by||null});
      setNotice("Connection interrupted: delivery visit queued for automatic synchronization.");
     }else throw error;
    }else {setNotice(result?.invoice_number?"Delivery completed. Invoice "+result.invoice_number+" posted · PKR "+Number(result.invoice_total||0).toLocaleString("en-PK")+". Van stock, returns, COGS and customer signature were saved atomically.":"Delivery outcome saved. Returned stock and vehicle ledger are synchronized.");}
   }setForm({delivery_id:"",visit_status:"delivered",notes:""});setLineQuantities({});clearSignature();if(navigator.onLine)await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Shop visit could not be saved.");}
  setSaving(false);
 }
 const customerFor=(delivery:Row)=>customers.find(x=>x.id===orders.find(o=>o.id===delivery.sales_order_id)?.customer_id);
 const selectedDeliveryLines=lines.filter(x=>x.delivery_id===form.delivery_id);
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Delivery Man App</h2><p>Assigned deliveries, customer stops, product quantities and visit outcomes, with offline assignment snapshots and queued synchronization.</p></div>{installPrompt&&<button onClick={async()=>{await installPrompt.prompt();setInstallPrompt(null);}}>Install Delivery App</button>}{!installPrompt&&<button title="iPhone/iPad: Share → Add to Home Screen. Chrome/Edge: browser menu → Install app." onClick={()=>setNotice("Install on iPhone/iPad: open Share and choose Add to Home Screen. On Chrome/Edge, use the browser menu and choose Install app.")}>Install help</button>}<button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {loading?<div className="table-empty">Loading assigned deliveries…</div>:!employee?<div className="notice">Employee account is not linked.</div>:<>
   <p className="module-footnote">Signed in as {employee.full_name} · {employee.employee_code}</p>
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Delivery</th><th>Sales order</th><th>Customer</th><th>Route</th><th>Status</th><th>Items</th></tr></thead><tbody>
    {deliveries.map(d=><tr key={d.id}><td>{d.delivery_number}</td><td>{orders.find(o=>o.id===d.sales_order_id)?.order_number||"—"}</td><td>{customerFor(d)?.name||"—"}</td><td>{d.route_id||"—"}</td><td>{d.status}</td><td>{lines.filter(l=>l.delivery_id===d.id).map(l=><div key={l.id}>{products.find(p=>p.id===l.product_id)?.name||l.product_id} · Picked {Number(l.picked_quantity_base||0)} / Delivered {Number(l.delivered_quantity_base||0)} base</div>)}</td></tr>)}
    {!deliveries.length&&<tr><td colSpan={6} className="table-empty">No deliveries are currently assigned to your account.</td></tr>}
   </tbody></table></div>
   <form className="transaction-form" onSubmit={saveVisit}><h3>Record customer shop visit</h3><div className="form-grid">
    <label>Assigned delivery / customer<select required value={form.delivery_id} onChange={e=>{const id=e.target.value;setForm(x=>({...x,delivery_id:id}));const d=deliveries.find(x=>x.id===id);const failedVisit=form.visit_status==="not_available"||form.visit_status==="refused";setLineQuantities(Object.fromEntries(lines.filter(x=>x.delivery_id===id).map(x=>[x.id,{delivered:failedVisit?"0":String(x.picked_quantity_base||0),marketReturn:"0",returnBatch:"",returnExpiry:""}])));}}><option value="">Select delivery</option>{deliveries.map(d=><option key={d.id} value={d.id}>{d.delivery_number} · {customerFor(d)?.name||orders.find(o=>o.id===d.sales_order_id)?.order_number||"Customer"} · {d.vehicle_number||"No vehicle"}</option>)}</select></label>
    <label>Visit result<select value={form.visit_status} onChange={e=>{const visitStatus=e.target.value;setForm(x=>({...x,visit_status:visitStatus}));if(visitStatus==="not_available"||visitStatus==="refused"){setLineQuantities(current=>Object.fromEntries(selectedDeliveryLines.map(line=>[line.id,{...(current[line.id]||{}),delivered:"0",marketReturn:"0"}])));}}}><option value="delivered">Delivered</option><option value="short_delivered">Short delivered</option><option value="not_available">Shop not available</option><option value="market_return">Market return</option><option value="refused">Customer refused</option></select></label>
    <label>Notes<input value={form.notes} onChange={e=>setForm(x=>({...x,notes:e.target.value}))} placeholder="Reason, returned items, customer remarks"/></label>
   </div><div className="pod-signature"><div><b>Proof of delivery · Customer signature</b><span>Required for delivered and short-delivered outcomes; saved atomically with stock and invoice posting.</span></div><canvas ref={signatureCanvas} width={520} height={140} onPointerDown={beginSignature} onPointerMove={moveSignature} onPointerUp={endSignature} onPointerCancel={endSignature} className="signature-canvas"/><button type="button" onClick={clearSignature}>Clear signature</button></div>{selectedDeliveryLines.map(line=>{const p=products.find(x=>x.id===line.product_id),q=lineQuantities[line.id]||{delivered:String(line.picked_quantity_base||0),marketReturn:"0",returnBatch:"",returnExpiry:""};return <div className="form-grid" key={line.id}><label>{p?.name||p?.sku||"Product"} · Picked {line.picked_quantity_base}<input type="number" min="0" max={line.picked_quantity_base} step="0.001" value={q.delivered} onChange={e=>setLineQuantities(x=>({...x,[line.id]:{...q,delivered:e.target.value}}))}/></label><label>Customer return quantity<input type="number" min="0" max={q.delivered||0} step="0.001" value={q.marketReturn} onChange={e=>setLineQuantities(x=>({...x,[line.id]:{...q,marketReturn:e.target.value}}))}/></label>{Number(q.marketReturn)>0&&<><label>Return batch number<input value={q.returnBatch} onChange={e=>setLineQuantities(x=>({...x,[line.id]:{...q,returnBatch:e.target.value}}))}/></label><label>Return expiry date<input type="date" value={q.returnExpiry} onChange={e=>setLineQuantities(x=>({...x,[line.id]:{...q,returnExpiry:e.target.value}}))}/></label></>}</div>})}<button disabled={saving||!form.delivery_id||deliveries.find(x=>x.id===form.delivery_id)?.status!=="dispatched"}>{saving?"Saving…":"Save delivery & stock movements"}</button></form>
   <h3>Visit history</h3><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Delivery</th><th>Customer</th><th>Result</th><th>GPS</th><th>Proof</th><th>Notes</th></tr></thead><tbody>{visits.map(v=><tr key={v.id}><td>{new Date(v.visit_at).toLocaleString("en-PK")}</td><td>{deliveries.find(d=>d.id===v.delivery_id)?.delivery_number||"—"}</td><td>{customers.find(c=>c.id===v.customer_id)?.name||"—"}</td><td>{v.visit_status.replaceAll("_"," ")}{Array.isArray(v.line_quantities)&&v.line_quantities.length>0?<div>{v.line_quantities.map((q:Row,i:number)=><div key={i}>Delivered {q.delivered_quantity_base} · Market return {q.market_return_quantity_base}</div>)}</div>:null}</td><td>{v.latitude!=null&&v.longitude!=null&&Number.isFinite(Number(v.latitude))&&Number.isFinite(Number(v.longitude))?Number(v.latitude).toFixed(5)+", "+Number(v.longitude).toFixed(5):"—"}</td><td>{v.proof_of_delivery_signature?.length?"Signature saved":"—"}</td><td>{v.notes||"—"}</td></tr>)}{!visits.length&&<tr><td colSpan={7} className="table-empty">No visits recorded yet.</td></tr>}</tbody></table></div>
  </>}
  <p className="module-footnote">Assigned delivery data is cached locally for offline viewing on this device. Delivery visits, quantity reports and customer signature proofs are queued locally and replayed with idempotent server sync when online. Delivered quantities and returns post to the van ledger transactionally; the system generates the posted sales invoice and revenue journal automatically when there is a sale.</p>
 </section>;
}