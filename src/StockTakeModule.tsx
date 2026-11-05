import {useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Row=Record<string,any>;
const today=()=>new Date().toISOString().slice(0,10);
const money=(n:number)=>"PKR "+Number(n||0).toLocaleString("en-PK",{maximumFractionDigits:2});
export default function StockTakeModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [warehouses,setWarehouses]=useState<Row[]>([]),[takes,setTakes]=useState<Row[]>([]),[snapshot,setSnapshot]=useState<Row[]>([]),[lines,setLines]=useState<Row[]>([]),[products,setProducts]=useState<Row[]>([]);
 const [warehouseId,setWarehouseId]=useState(""),[countDate,setCountDate]=useState(today()),[notes,setNotes]=useState(""),[selectedTake,setSelectedTake]=useState<Row|null>(null);
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const canEdit=["owner","admin","manager","warehouse"].includes(currentRole);
 async function load(){
  setLoading(true);setNotice("");
  const [w,t]=await Promise.all([db.from("warehouses").select("id,code,name,is_active").eq("tenant_id",tenantId).eq("is_active",true).order("name"),db.from("stock_takes").select("id,warehouse_id,stock_take_number,count_date,status,notes,created_at").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(50)]);
  const err=w.error||t.error;if(err)setNotice(err.message);else{setWarehouses(w.data||[]);setTakes(t.data||[]);if(!warehouseId&&w.data?.[0])setWarehouseId(w.data[0].id);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 async function loadSnapshot(){
  if(!warehouseId){setNotice("Select a warehouse first.");return;}
  setSaving(true);setNotice("");
  const {data,error}=await db.rpc("get_stock_take_snapshot",{p_tenant_id:tenantId,p_warehouse_id:warehouseId});
  if(error)setNotice(error.message);else{setSnapshot((data||[]).map((x:Row)=>({...x,counted_quantity:String(x.expected_quantity??0)})));setNotice((data||[]).length+" product/batch balances loaded for physical verification.");}
  setSaving(false);
 }
 function updateSnapshot(index:number,value:string){setSnapshot(rows=>rows.map((x,i)=>i===index?{...x,counted_quantity:value}:x));}
 async function createDraft(){
  if(!canEdit||!snapshot.length)return;
  setSaving(true);setNotice("");
  try{
   const payload=snapshot.map(x=>({product_id:x.product_id,batch_number:x.batch_number,expiry_date:x.expiry_date,counted_quantity:Number(x.counted_quantity)}));
   if(payload.some(x=>!Number.isFinite(x.counted_quantity)||x.counted_quantity<0))throw new Error("Every physical count must be a valid non-negative quantity.");
   const {data,error}=await db.rpc("create_stock_take",{p_tenant_id:tenantId,p_warehouse_id:warehouseId,p_count_date:countDate,p_lines:payload,p_notes:notes.trim()||null});
   if(error)throw error;
   setNotice("Draft stock take created. Review the saved count before posting adjustments.");
   setSnapshot([]);setNotes("");await load();
   const found=(await db.from("stock_takes").select("id,warehouse_id,stock_take_number,count_date,status,notes,created_at").eq("tenant_id",tenantId).eq("id",data).single());
   if(!found.error&&found.data)await openTake(found.data);
  }catch(e){setNotice(e instanceof Error?e.message:"Stock take draft could not be created.");}
  finally{setSaving(false);}
 }
 async function openTake(take:Row){
  setSelectedTake(take);setLines([]);setProducts([]);
  const {data,error}=await db.from("stock_take_lines").select("id,product_id,batch_number,expiry_date,expected_quantity,counted_quantity,variance_quantity,unit_cost").eq("tenant_id",tenantId).eq("stock_take_id",take.id).order("product_id");
  if(error){setNotice(error.message);return;}
  setLines(data||[]);
  const ids=[...new Set((data||[]).map((x:Row)=>x.product_id))];
  if(ids.length){const result=await db.from("products").select("id,sku,name").eq("tenant_id",tenantId).in("id",ids);if(!result.error)setProducts(result.data||[]);}
 }
 function updateLine(id:string,value:string){setLines(rows=>rows.map(x=>x.id===id?{...x,counted_quantity:value,variance_quantity:Number(value)-Number(x.expected_quantity)}:x));}
 async function saveCounts(){
  if(!selectedTake||selectedTake.status!=="draft"||!canEdit)return;
  setSaving(true);setNotice("");
  try{
   const payload=lines.map(x=>({id:x.id,counted_quantity:Number(x.counted_quantity)}));
   if(payload.some(x=>!Number.isFinite(x.counted_quantity)||x.counted_quantity<0))throw new Error("Physical count must be a valid non-negative quantity.");
   const {error}=await db.rpc("update_stock_take_counts",{p_stock_take_id:selectedTake.id,p_lines:payload});
   if(error)throw error;setNotice("Physical counts saved. Ledger variances have been recalculated.");await openTake(selectedTake);
  }catch(e){setNotice(e instanceof Error?e.message:"Physical counts could not be saved.");}
  finally{setSaving(false);}
 }
 async function postTake(){
  if(!selectedTake||selectedTake.status!=="draft"||!canEdit)return;
  if(!window.confirm("Post this stock take? The variance will create permanent stock ledger adjustments."))return;
  setSaving(true);setNotice("");
  try{
   const {error}=await db.rpc("post_stock_take",{p_stock_take_id:selectedTake.id});
   if(error)throw error;setNotice("Stock take posted. Physical count variances are now reflected in the warehouse stock ledger.");await load();const refreshed=await db.from("stock_takes").select("id,warehouse_id,stock_take_number,count_date,status,notes,created_at").eq("tenant_id",tenantId).eq("id",selectedTake.id).single();if(!refreshed.error&&refreshed.data)await openTake(refreshed.data);
  }catch(e){setNotice(e instanceof Error?e.message:"Stock take could not be posted.");}
  finally{setSaving(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Physical Stock Taking</h2><p>Compare counted warehouse quantities against the live batch ledger, then post only the verified variance.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  <div className="transaction-form"><h3>Start a physical count</h3><div className="form-grid"><label>Warehouse<select value={warehouseId} onChange={e=>{setWarehouseId(e.target.value);setSnapshot([]);}}><option value="">Select warehouse</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.code} · {w.name}</option>)}</select></label><label>Count date<input type="date" value={countDate} readOnly/></label><label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Optional count reference"/></label></div><div className="table-tools"><button disabled={!canEdit||saving||!warehouseId} onClick={()=>void loadSnapshot()}>Load live stock snapshot</button>{snapshot.length>0&&<button disabled={!canEdit||saving} onClick={()=>void createDraft()}>{saving?"Saving…":"Create draft stock take"}</button>}</div>
   {snapshot.length>0&&<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Product</th><th>Batch</th><th>Expiry</th><th>Ledger qty</th><th>Physical count</th><th>Variance</th></tr></thead><tbody>{snapshot.map((x,i)=>{const variance=Number(x.counted_quantity)-Number(x.expected_quantity);return <tr key={x.product_id+"|"+x.batch_number+"|"+x.expiry_date}><td>{x.sku} · {x.product_name}</td><td>{x.batch_number||"—"}</td><td>{x.expiry_date||"—"}</td><td>{Number(x.expected_quantity).toLocaleString("en-PK")}</td><td><input type="number" min="0" step="0.001" value={x.counted_quantity} onChange={e=>updateSnapshot(i,e.target.value)}/></td><td>{variance>0?"+":""}{variance.toLocaleString("en-PK")}</td></tr>})}</tbody></table></div>}
  </div>
  <div className="data-table-wrap"><h3>Recent stock takes</h3><table className="data-table"><thead><tr><th>Reference</th><th>Warehouse</th><th>Date</th><th>Status</th><th>Action</th></tr></thead><tbody>{takes.map(t=><tr key={t.id}><td>{t.stock_take_number}</td><td>{warehouses.find(w=>w.id===t.warehouse_id)?.name||t.warehouse_id}</td><td>{t.count_date}</td><td>{t.status}</td><td><button onClick={()=>void openTake(t)}>Open</button></td></tr>)}{!takes.length&&<tr><td colSpan={5} className="table-empty">No stock takes recorded yet.</td></tr>}</tbody></table></div>
  {selectedTake&&<div className="transaction-form"><div className="module-toolbar"><div><h3>{selectedTake.stock_take_number}</h3><p>{selectedTake.status==="draft"?"Draft count — verify quantities before posting.":"Posted count — ledger adjustments are locked."}</p></div><span>{selectedTake.status.toUpperCase()}</span></div><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Product</th><th>Batch</th><th>Expiry</th><th>Ledger qty</th><th>Counted qty</th><th>Variance</th><th>Unit cost</th></tr></thead><tbody>{lines.map(x=>{const variance=Number(x.counted_quantity)-Number(x.expected_quantity);return <tr key={x.id}><td>{products.find(p=>p.id===x.product_id)?.sku} · {products.find(p=>p.id===x.product_id)?.name}</td><td>{x.batch_number||"—"}</td><td>{x.expiry_date||"—"}</td><td>{Number(x.expected_quantity).toLocaleString("en-PK")}</td><td>{selectedTake.status==="draft"?<input type="number" min="0" step="0.001" value={x.counted_quantity} onChange={e=>updateLine(x.id,e.target.value)}/>:Number(x.counted_quantity).toLocaleString("en-PK")}</td><td>{variance>0?"+":""}{variance.toLocaleString("en-PK")}</td><td>{money(Number(x.unit_cost))}</td></tr>})}</tbody></table></div>{selectedTake.status==="draft"&&<div className="table-tools"><button disabled={!canEdit||saving} onClick={()=>void saveCounts()}>Save physical counts</button><button className="primary-action" disabled={!canEdit||saving} onClick={()=>void postTake()}>Post stock adjustments</button></div>}</div>}
  <p className="module-footnote">Posting is transactional: the system rechecks that ledger stock has not changed since the count was started. Expired batches cannot be added back into saleable inventory; record them through the damage/write-off workflow.</p>
 </section>;
}
