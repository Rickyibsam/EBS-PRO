import { useEffect, useMemo, useState, FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Product={id:string;name:string;sku:string;is_active:boolean};
type Party={id:string;name:string;party_code:string};
type Unit={id:string;name:string;symbol:string};
type ProductUnit={id:string;product_id:string;unit_id:string;conversion_to_base:number;is_purchase_unit:boolean;is_sales_unit:boolean};
type Line={product_id:string;unit_id:string;quantity:string;rate:string;tax_rate:string;discount:string};
type Header={id:string;order_number:string;order_date:string;status:string;grand_total:number};

export default function TransactionsModule({db,tenantId,module}:{db:SupabaseClient;tenantId:string;module:string}){
 const purchase=module==="Purchases";
 const table=purchase?"purchase_orders":"sales_orders";
 const [products,setProducts]=useState<Product[]>([]);
 const [parties,setParties]=useState<Party[]>([]);
 const [units,setUnits]=useState<Unit[]>([]);
 const [productUnits,setProductUnits]=useState<ProductUnit[]>([]);
 const [warehouses,setWarehouses]=useState<{id:string;name:string}[]>([]);
 const [rows,setRows]=useState<Header[]>([]);
 const [partyId,setPartyId]=useState("");
 const [warehouseId,setWarehouseId]=useState("");
 const [notes,setNotes]=useState("");
 const [lines,setLines]=useState<Line[]>([{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}]);
 const [loading,setLoading]=useState(true);
 const [saving,setSaving]=useState(false);
 const [notice,setNotice]=useState("");
 const [showForm,setShowForm]=useState(false);
 const [search,setSearch]=useState("");
 const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
 useEffect(()=>{void loadAll();},[tenantId,module]);
 async function loadAll(){
  setLoading(true);setNotice("");
  const [p,pa,u,pu,w,h]=await Promise.all([
   db.from("products").select("id,name,sku,is_active").eq("tenant_id",tenantId).eq("is_active",true).order("name").limit(1000),
   db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",purchase?["supplier","both"]:["customer","both"]).eq("status","active").order("name").limit(1000),
   db.from("units_of_measure").select("id,name,symbol").eq("tenant_id",tenantId).order("name"),
   db.from("product_units").select("id,product_id,unit_id,conversion_to_base,is_purchase_unit,is_sales_unit").eq("tenant_id",tenantId),
   db.from("warehouses").select("id,name").eq("tenant_id",tenantId).eq("is_active",true).order("name"),
   db.from(table).select("id,"+(purchase?"po_number":"order_number")+",order_date,status,grand_total").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(200)
  ]);
  const errors=[p.error,pa.error,u.error,pu.error,w.error,h.error].filter(Boolean);
  if(errors.length)setNotice(errors.map(e=>e!.message).join(" · "));
  setProducts((p.data??[]) as Product[]);setParties((pa.data??[]) as Party[]);setUnits((u.data??[]) as Unit[]);setProductUnits((pu.data??[]) as ProductUnit[]);setWarehouses((w.data??[]) as {id:string;name:string}[]);
  setRows((h.data??[]).map((r:any)=>({id:r.id,order_number:purchase?r.po_number:r.order_number,order_date:r.order_date,status:r.status,grand_total:Number(r.grand_total)})));
  setLoading(false);
 }
 function allowedUnits(productId:string){return productUnits.filter(x=>x.product_id===productId&&(purchase?x.is_purchase_unit:x.is_sales_unit));}
 function changeLine(i:number,key:keyof Line,value:string){setLines(old=>old.map((r,n)=>n===i?{...r,[key]:value,...(key==="product_id"?{unit_id:allowedUnits(value)[0]?.unit_id??""}:{})}:r));}
 const total=useMemo(()=>lines.reduce((s,l)=>{const base=(Number(l.quantity)||0)*(Number(l.rate)||0);return s+base+base*(Number(l.tax_rate)||0)/100-(Number(l.discount)||0);},0),[lines]);
 const filtered=rows.filter(r=>r.order_number.toLowerCase().includes(search.toLowerCase())||r.status.toLowerCase().includes(search.toLowerCase()));
 async function save(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try{
   if(!partyId)throw new Error(purchase?"Supplier select karein.":"Customer select karein.");
   const clean=lines.filter(l=>l.product_id&&l.unit_id&&Number(l.quantity)>0);
   if(!clean.length)throw new Error("Kam az kam aik product aur valid quantity enter karein.");
   for(const l of clean){const pu=allowedUnits(l.product_id).find(x=>x.unit_id===l.unit_id);if(!pu)throw new Error("Selected product ka valid unit nahi mila.");}
   const subtotal=clean.reduce((s,l)=>s+Number(l.quantity)*Number(l.rate),0);
   const tax=clean.reduce((s,l)=>s+Number(l.quantity)*Number(l.rate)*Number(l.tax_rate)/100,0);
   const discount=clean.reduce((s,l)=>s+Number(l.discount),0);
   const doc=(purchase?"EBS-PO-":"EBS-SO-")+Date.now().toString().slice(-10);
   const {data:userData}=await db.auth.getUser();
   const header:any={tenant_id:tenantId,order_date:new Date().toISOString(),status:"draft",subtotal,tax_total:tax,discount_total:discount,grand_total:subtotal+tax-discount,notes:notes.trim()||null,created_by:userData.user?.id??null};
   if(purchase){header.po_number=doc;header.supplier_id=partyId;if(warehouseId)header.warehouse_id=warehouseId;}
   else {header.order_number=doc;header.customer_id=partyId;header.order_source="backoffice";if(warehouseId)header.warehouse_id=warehouseId;}
   const {data:created,error}=await db.from(table).insert(header).select("id").single();
   if(error)throw error;
   const detail=clean.map(l=>{const pu=allowedUnits(l.product_id).find(x=>x.unit_id===l.unit_id)!;const amount=Number(l.quantity)*Number(l.rate);const taxAmount=amount*Number(l.tax_rate)/100;return {tenant_id:tenantId,[purchase?"purchase_order_id":"sales_order_id"]:created.id,product_id:l.product_id,unit_id:l.unit_id,quantity:Number(l.quantity),conversion_to_base:Number(pu.conversion_to_base),[purchase?"unit_cost":"unit_price"]:Number(l.rate),tax_rate:Number(l.tax_rate)||0,discount_amount:Number(l.discount)||0,line_total:amount+taxAmount-(Number(l.discount)||0)};});
   const lineTable=purchase?"purchase_order_lines":"sales_order_lines";
   const {error:lineError}=await db.from(lineTable).insert(detail);
   if(lineError){setNotice("Header draft save ho gaya ("+doc+"), lekin line items save nahi hue: "+lineError.message+" — draft ko verify karein.");await loadAll();return;}
   setNotice("Draft "+doc+" successfully save ho gaya.");
   setLines([{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}]);setPartyId("");setWarehouseId("");setNotes("");setShowForm(false);await loadAll();
  }catch(err){setNotice(err instanceof Error?err.message:"Transaction save nahi ho saki.");}
  finally{setSaving(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>{purchase?"Purchase Orders":"Sales Orders"}</h2><p>{purchase?"Supplier purchase orders and item-wise cost tracking.":"Customer sales orders with item pricing, tax and discount."}</p></div><button className="primary-action" onClick={()=>{setShowForm(!showForm);setNotice("");}}>{showForm?"Close form":purchase?"+ New purchase":"+ New sales order"}</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {showForm&&<form className="transaction-form" onSubmit={save}>
   <div className="form-grid"><label>{purchase?"Supplier":"Customer"}<select required value={partyId} onChange={e=>setPartyId(e.target.value)}><option value="">Select {purchase?"supplier":"customer"}</option>{parties.map(p=><option key={p.id} value={p.id}>{p.party_code} · {p.name}</option>)}</select></label><label>Warehouse (optional)<select value={warehouseId} onChange={e=>setWarehouseId(e.target.value)}><option value="">Default / not selected</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Reference / remarks"/></label></div>
   <div className="line-heading"><b>Order items</b><button type="button" onClick={()=>setLines(x=>[...x,{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}])}>+ Add line</button></div>
   {lines.map((l,i)=><div className="order-line" key={i}><label>Product<select required value={l.product_id} onChange={e=>changeLine(i,"product_id",e.target.value)}><option value="">Select product</option>{products.map(p=><option key={p.id} value={p.id}>{p.sku} · {p.name}</option>)}</select></label><label>Unit<select required value={l.unit_id} onChange={e=>changeLine(i,"unit_id",e.target.value)}><option value="">Select unit</option>{allowedUnits(l.product_id).map(pu=><option key={pu.id} value={pu.unit_id}>{units.find(u=>u.id===pu.unit_id)?.symbol||units.find(u=>u.id===pu.unit_id)?.name||"Unit"} (×{pu.conversion_to_base})</option>)}</select></label><label>Qty<input required type="number" min="0.001" step="0.001" value={l.quantity} onChange={e=>changeLine(i,"quantity",e.target.value)}/></label><label>{purchase?"Unit cost":"Unit price"}<input required type="number" min="0" step="0.01" value={l.rate} onChange={e=>changeLine(i,"rate",e.target.value)}/></label><label>Tax %<input type="number" min="0" step="0.01" value={l.tax_rate} onChange={e=>changeLine(i,"tax_rate",e.target.value)}/></label><label>Discount PKR<input type="number" min="0" step="0.01" value={l.discount} onChange={e=>changeLine(i,"discount",e.target.value)}/></label><button type="button" className="remove-line" onClick={()=>setLines(x=>x.length>1?x.filter((_,n)=>n!==i):x)}>×</button></div>)}
   <div className="transaction-total"><span>Estimated total</span><b>{money(total)}</b></div><button disabled={saving||!products.length||!parties.length}>{saving?"Saving draft…":"Save as draft"}</button>
   {!products.length&&<small>Product Master mein pehle products aur unke purchase/sales units add karein.</small>}
  </form>}
  <div className="table-tools"><input placeholder="Search document number or status…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} records</span><button onClick={()=>void loadAll()}>↻ Refresh</button></div>
  {loading?<div className="table-empty">Loading transactions…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Document</th><th>Date</th><th>Status</th><th>Total</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{r.order_number}</td><td>{new Date(r.order_date).toLocaleDateString("en-PK")}</td><td><span className="status-active">{r.status}</span></td><td>{money(r.grand_total)}</td></tr>)}{!filtered.length&&<tr><td colSpan={4} className="table-empty">No records found.</td></tr>}</tbody></table></div>}
  <p className="module-footnote">Orders are saved as drafts. Stock is not changed until a verified receiving/dispatch posting workflow is implemented.</p>
 </section>;
}
