import {FormEvent,useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Row=Record<string,any>;
export default function VendorCatalogModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [rows,setRows]=useState<Row[]>([]),[suppliers,setSuppliers]=useState<Row[]>([]),[products,setProducts]=useState<Row[]>([]);
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState(""),[show,setShow]=useState(false),[search,setSearch]=useState("");
 const [form,setForm]=useState({supplier_id:"",product_id:"",supplier_item_code:"",purchase_cost:"0",minimum_order_qty:"1",lead_time_days:"0",is_preferred:false,notes:""});
 const canEdit=["owner","admin","manager","purchase"].includes(currentRole);
 async function load(){
  setLoading(true);setNotice("");
  const [v,s,p]=await Promise.all([
   db.from("vendor_product_catalog").select("id,supplier_id,product_id,supplier_item_code,purchase_cost,minimum_order_qty,lead_time_days,is_preferred,last_cost_date,notes").eq("tenant_id",tenantId).order("updated_at",{ascending:false}).limit(1000),
   db.from("parties").select("id,party_code,name").eq("tenant_id",tenantId).in("party_type",["supplier","both"]).eq("status","active").order("name"),
   db.from("products").select("id,sku,name,cost_price,sale_price").eq("tenant_id",tenantId).eq("is_active",true).order("name")
  ]);
  const err=v.error||s.error||p.error;if(err)setNotice(err.message);else{setRows(v.data??[]);setSuppliers(s.data??[]);setProducts(p.data??[]);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 async function save(e:FormEvent){
  e.preventDefault();if(!canEdit)return;setSaving(true);setNotice("");
  const cost=Number(form.purchase_cost),min=Number(form.minimum_order_qty),lead=Number(form.lead_time_days);
  if(!form.supplier_id||!form.product_id||!Number.isFinite(cost)||cost<0||!Number.isFinite(min)||min<=0||!Number.isInteger(lead)||lead<0){setNotice("Supplier, product, valid purchase cost, MOQ and lead time are required.");setSaving(false);return;}
  const {error}=await db.from("vendor_product_catalog").upsert({tenant_id:tenantId,supplier_id:form.supplier_id,product_id:form.product_id,supplier_item_code:form.supplier_item_code.trim()||null,purchase_cost:cost,minimum_order_qty:min,lead_time_days:lead,is_preferred:form.is_preferred,last_cost_date:new Date().toISOString().slice(0,10),notes:form.notes.trim()||null},{onConflict:"tenant_id,supplier_id,product_id"});
  if(error)setNotice(error.message);else{setNotice("Supplier product cost and feeding details saved.");setForm({supplier_id:"",product_id:"",supplier_item_code:"",purchase_cost:"0",minimum_order_qty:"1",lead_time_days:"0",is_preferred:false,notes:""});setShow(false);await load();}
  setSaving(false);
 }
 async function applyCost(r:Row){
  if(!canEdit)return;const ok=window.confirm("Update this product's master cost price from this supplier's latest purchase cost?");if(!ok)return;
  const {error}=await db.from("products").update({cost_price:r.purchase_cost}).eq("tenant_id",tenantId).eq("id",r.product_id);
  if(error)setNotice(error.message);else{setNotice("Product master cost price updated from vendor cost.");await load();}
 }
 const filtered=rows.filter(r=>{const q=search.toLowerCase();const p=products.find(x=>x.id===r.product_id),s=suppliers.find(x=>x.id===r.supplier_id);return [p?.name,p?.sku,s?.name,s?.party_code,r.supplier_item_code].some(x=>String(x||"").toLowerCase().includes(q));});
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Vendor Feeding & Supplier Product Catalog</h2><p>Supplier-wise SKU mapping, supplier item codes, latest purchase cost, minimum order quantities and lead times.</p></div>{canEdit&&<button className="primary-action" onClick={()=>setShow(!show)}>{show?"Close form":"+ Feed vendor product"}</button>}</div>
  {notice&&<div className="notice">{notice}</div>}
  {show&&<form className="data-form" onSubmit={save}>
   <label>Vendor / Supplier<select required value={form.supplier_id} onChange={e=>setForm({...form,supplier_id:e.target.value})}><option value="">Select supplier</option>{suppliers.map(x=><option key={x.id} value={x.id}>{x.party_code} · {x.name}</option>)}</select></label>
   <label>Product / SKU<select required value={form.product_id} onChange={e=>{const p=products.find(x=>x.id===e.target.value);setForm({...form,product_id:e.target.value,purchase_cost:String(p?.cost_price??0)});}}><option value="">Select product</option>{products.map(x=><option key={x.id} value={x.id}>{x.sku} · {x.name}</option>)}</select></label>
   <label>Vendor item code<input value={form.supplier_item_code} onChange={e=>setForm({...form,supplier_item_code:e.target.value})}/></label>
   <label>Purchase cost (PKR)<input required type="number" min="0" step="0.0001" value={form.purchase_cost} onChange={e=>setForm({...form,purchase_cost:e.target.value})}/></label>
   <label>Minimum order quantity<input required type="number" min="0.0001" step="0.0001" value={form.minimum_order_qty} onChange={e=>setForm({...form,minimum_order_qty:e.target.value})}/></label>
   <label>Lead time (days)<input required type="number" min="0" step="1" value={form.lead_time_days} onChange={e=>setForm({...form,lead_time_days:e.target.value})}/></label>
   <label className="check-label"><input type="checkbox" checked={form.is_preferred} onChange={e=>setForm({...form,is_preferred:e.target.checked})}/> Preferred supplier for this product</label>
   <label>Notes<input value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label>
   <button disabled={saving}>{saving?"Saving…":"Save vendor feeding"}</button>
  </form>}
  <div className="table-tools"><input placeholder="Search supplier, SKU or vendor code…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} vendor product mappings</span><button onClick={()=>void load()}>↻ Refresh</button></div>
  {loading?<div className="table-empty">Loading vendor catalog…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Supplier</th><th>SKU / Product</th><th>Vendor code</th><th>Purchase cost</th><th>MOQ</th><th>Lead days</th><th>Preferred</th><th>Last cost date</th><th>Action</th></tr></thead><tbody>{filtered.map(r=>{const p=products.find(x=>x.id===r.product_id),s=suppliers.find(x=>x.id===r.supplier_id);return <tr key={r.id}><td>{s?.name||"—"}</td><td>{p?.sku} · {p?.name}</td><td>{r.supplier_item_code||"—"}</td><td>PKR {Number(r.purchase_cost).toLocaleString("en-PK",{minimumFractionDigits:2})}</td><td>{r.minimum_order_qty}</td><td>{r.lead_time_days}</td><td>{r.is_preferred?"Yes":"No"}</td><td>{r.last_cost_date||"—"}</td><td>{canEdit?<><button onClick={()=>{setForm({supplier_id:r.supplier_id,product_id:r.product_id,supplier_item_code:r.supplier_item_code||"",purchase_cost:String(r.purchase_cost),minimum_order_qty:String(r.minimum_order_qty),lead_time_days:String(r.lead_time_days),is_preferred:r.is_preferred,notes:r.notes||""});setShow(true);setNotice("");}}>Edit</button> <button onClick={()=>void applyCost(r)}>Apply cost to product</button></>:"—"}</td></tr>})}{!filtered.length&&<tr><td colSpan={9} className="table-empty">No vendor product mappings found. Feed a supplier and product to start.</td></tr>}</tbody></table></div>}
  <p className="module-footnote">Vendor feeding records are company-isolated by Supabase RLS. Supplier costs are separate per supplier; applying cost updates the product master cost without changing historical purchase documents.</p>
 </section>;
}
