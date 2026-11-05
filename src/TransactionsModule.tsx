import { useEffect, useMemo, useState, FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Product={id:string;name:string;sku:string;barcode:string|null;is_active:boolean;cost_price:number;sale_price:number;purchase_tax_rate:number;sales_tax_rate:number};
type Party={id:string;name:string;party_code:string};
type Unit={id:string;name:string;symbol:string};
type ProductUnit={id:string;product_id:string;unit_id:string;conversion_to_base:number;is_purchase_unit:boolean;is_sales_unit:boolean};
type Line={product_id:string;unit_id:string;quantity:string;rate:string;tax_rate:string;discount:string};
type Header={id:string;order_number:string;po_number?:string;supplier_id?:string;customer_id?:string;order_date:string;status:string;grand_total:number;booker_employee_id?:string|null;route_id?:string|null;delivery_man_employee_id?:string|null};
type PrintLine={product_id:string;unit_id:string;quantity:number;unit_price:number;tax_rate:number;discount_amount:number;line_total:number};

export default function TransactionsModule({db,tenantId,module,currentRole}:{db:SupabaseClient;tenantId:string;module:string;currentRole:string}){
 const purchase=module==="Purchases";
 const table=purchase?"purchase_orders":"sales_orders";
 const [products,setProducts]=useState<Product[]>([]);
 const [parties,setParties]=useState<Party[]>([]);
 const [units,setUnits]=useState<Unit[]>([]);
 const [productUnits,setProductUnits]=useState<ProductUnit[]>([]);
 const [vendorCosts,setVendorCosts]=useState<Array<{supplier_id:string;product_id:string;purchase_cost:number;is_preferred:boolean}>>([]);
 const [customerPrices,setCustomerPrices]=useState<Array<{product_id:string;unit_id:string;price:number;min_quantity:number}>>([]);
 const [warehouses,setWarehouses]=useState<{id:string;name:string}[]>([]);
 const [employees,setEmployees]=useState<Array<{id:string;full_name:string;job_title:string|null}>>([]);
 const [routes,setRoutes]=useState<Array<{id:string;name:string;route_code:string}>>([]);
 const [bookerId,setBookerId]=useState("");const [routeId,setRouteId]=useState("");const [deliveryManId,setDeliveryManId]=useState("");
 const [rows,setRows]=useState<Header[]>([]);
 const [partyId,setPartyId]=useState("");
 const [warehouseId,setWarehouseId]=useState("");
 const [notes,setNotes]=useState("");
 const [lines,setLines]=useState<Line[]>([{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}]);
 const [loading,setLoading]=useState(true);
 const [saving,setSaving]=useState(false);
 const [notice,setNotice]=useState("");
 const [showForm,setShowForm]=useState(false);
 const [search,setSearch]=useState("");const [printDoc,setPrintDoc]=useState<Header|null>(null),[printLines,setPrintLines]=useState<PrintLine[]>([]),[printParty,setPrintParty]=useState<{name:string;phone:string|null;address:string|null}|null>(null);
 const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
 function exportOrders(){const data=filtered.map(r=>({document:purchase?r.po_number:r.order_number,date:r.order_date,party:parties.find(p=>p.id===(purchase?r.supplier_id:r.customer_id))?.name||"",status:r.status,total:r.grand_total,booker:employees.find(e=>e.id===r.booker_employee_id)?.full_name||"",route:routes.find(x=>x.id===r.route_id)?.name||"",delivery_man:employees.find(e=>e.id===r.delivery_man_employee_id)?.full_name||""}));const keys=Object.keys(data[0]||{document:"",date:"",party:"",status:"",total:""});const csv=[keys.join(","),...data.map(x=>keys.map(k=>'"'+String(x[k as keyof typeof x]??"").replace(/"/g,'""')+'"').join(","))].join("\\r\\n");const blob=new Blob(["\\uFEFF"+csv],{type:"text/csv;charset=utf-8"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=(purchase?"purchase-orders":"sales-orders")+".csv";a.click();URL.revokeObjectURL(url);}
 useEffect(()=>{void loadAll();},[tenantId,module]);
 async function loadAll(){
  setLoading(true);setNotice("");
  const [p,pa,u,pu,vc,w,h,emp,rt]=await Promise.all([
   db.from("products").select("id,name,sku,barcode,is_active,cost_price,sale_price,purchase_tax_rate,sales_tax_rate").eq("tenant_id",tenantId).eq("is_active",true).order("name").limit(1000),
   db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",purchase?["supplier","both"]:["customer","both"]).eq("status","active").order("name").limit(1000),
   db.from("units_of_measure").select("id,name,symbol").eq("tenant_id",tenantId).order("name"),
   db.from("product_units").select("id,product_id,unit_id,conversion_to_base,is_purchase_unit,is_sales_unit").eq("tenant_id",tenantId),
    db.from("vendor_product_catalog").select("supplier_id,product_id,purchase_cost,is_preferred").eq("tenant_id",tenantId),
   db.from("warehouses").select("id,name").eq("tenant_id",tenantId).eq("is_active",true).order("name"),
   db.from(table).select("id,"+(purchase?"po_number":"order_number")+",order_date,status,grand_total"+(purchase?"":",booker_employee_id,route_id,delivery_man_employee_id")).eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(200),
   db.from("employees").select("id,full_name,job_title").eq("tenant_id",tenantId).eq("employment_status","active").order("full_name"),
   db.from("sales_routes").select("id,name,route_code").eq("tenant_id",tenantId).eq("is_active",true).order("name")
  ]);
  const errors=[p.error,pa.error,u.error,pu.error,vc.error,w.error,h.error,emp.error,rt.error].filter(Boolean);
  if(errors.length)setNotice(errors.map(e=>e!.message).join(" · "));
  setProducts((p.data??[]) as Product[]);setParties((pa.data??[]) as Party[]);setUnits((u.data??[]) as Unit[]);setProductUnits((pu.data??[]) as ProductUnit[]);setVendorCosts(vc.data??[]);setWarehouses((w.data??[]) as {id:string;name:string}[]);
  setEmployees(emp.data??[]);setRoutes(rt.data??[]);setRows((h.data??[]).map((r:any)=>({id:r.id,order_number:purchase?r.po_number:r.order_number,order_date:r.order_date,status:r.status,grand_total:Number(r.grand_total),booker_employee_id:r.booker_employee_id,route_id:r.route_id,delivery_man_employee_id:r.delivery_man_employee_id})));
  setLoading(false);
 }
 async function selectParty(id:string){
  setPartyId(id);
  if(purchase){setLines(old=>old.map(line=>{const v=vendorCosts.find(x=>x.supplier_id===id&&x.product_id===line.product_id);const p=products.find(x=>x.id===line.product_id);return line.product_id?{...line,rate:String(v?.purchase_cost??p?.cost_price??0)}:line;}));return;}
  setCustomerPrices([]);
  if(!id)return;
  const {data:assignments,error}=await db.from("customer_price_lists").select("price_list_id").eq("tenant_id",tenantId).eq("customer_id",id);
  if(error){setNotice("Customer pricing could not be loaded: "+error.message);return;}
  const ids=(assignments??[]).map(x=>x.price_list_id);
  if(!ids.length)return;
  const {data,error:priceError}=await db.from("product_prices").select("product_id,unit_id,price,min_quantity").eq("tenant_id",tenantId).in("price_list_id",ids);
  if(priceError){setNotice("Customer product prices could not be loaded: "+priceError.message);return;}
  setCustomerPrices(data??[]);setLines(old=>old.map(line=>{const p=products.find(x=>x.id===line.product_id);const match=(data??[]).filter(x=>x.product_id===line.product_id&&x.unit_id===line.unit_id&&Number(x.min_quantity)<=Number(line.quantity)).sort((a,b)=>Number(b.min_quantity)-Number(a.min_quantity))[0];return line.product_id?{...line,rate:String(match?.price??p?.sale_price??0)}:line;}));
 }
 function allowedUnits(productId:string){return productUnits.filter(x=>x.product_id===productId&&(purchase?x.is_purchase_unit:x.is_sales_unit));}
 function changeLine(i:number,key:keyof Line,value:string){setLines(old=>old.map((r,n)=>{if(n!==i)return r;const next={...r,[key]:value};if(key==="product_id"){next.unit_id=allowedUnits(value)[0]?.unit_id??"";const p=products.find(x=>x.id===value);next.tax_rate=String(p?(purchase?p.purchase_tax_rate:p.sales_tax_rate):0);}if(key==="product_id"||key==="unit_id"||key==="quantity"){const productId=key==="product_id"?value:r.product_id;const unitId=key==="unit_id"?value:next.unit_id;const qty=Number(key==="quantity"?value:r.quantity)||1;const p=products.find(x=>x.id===productId);const supplierCost=vendorCosts.find(x=>x.supplier_id===partyId&&x.product_id===productId);const preferredCost=vendorCosts.find(x=>x.product_id===productId&&x.is_preferred);const listPrice=customerPrices.filter(x=>x.product_id===productId&&x.unit_id===unitId&&Number(x.min_quantity)<=qty).sort((a,b)=>Number(b.min_quantity)-Number(a.min_quantity))[0];next.rate=String(purchase?(supplierCost?.purchase_cost??p?.cost_price??0):(listPrice?.price??p?.sale_price??0));}return next;}));}
 const total=useMemo(()=>lines.reduce((s,l)=>{const base=(Number(l.quantity)||0)*(Number(l.rate)||0);return s+base+base*(Number(l.tax_rate)||0)/100-(Number(l.discount)||0);},0),[lines]);
 const filtered=rows.filter(r=>r.order_number.toLowerCase().includes(search.toLowerCase())||r.status.toLowerCase().includes(search.toLowerCase()));
 async function preparePrint(row:Header){setNotice("");try{const [lineResult,headResult]=await Promise.all([db.from("sales_order_lines").select("product_id,unit_id,quantity,unit_price,tax_rate,discount_amount,line_total").eq("tenant_id",tenantId).eq("sales_order_id",row.id),db.from("sales_orders").select("customer_id").eq("tenant_id",tenantId).eq("id",row.id).single()]);if(lineResult.error)throw lineResult.error;if(headResult.error)throw headResult.error;const {data:party,error}=await db.from("parties").select("name,phone,address").eq("tenant_id",tenantId).eq("id",headResult.data.customer_id).single();if(error)throw error;setPrintDoc(row);setPrintLines(lineResult.data??[]);setPrintParty(party);}catch(e){setNotice(e instanceof Error?e.message:"Sales order print preview could not be prepared.");}}
 async function approve(id:string){setNotice("");try{const {data:user}=await db.auth.getUser();const {error}=await db.from(table).update({status:"approved",approved_by:user.user?.id??null}).eq("id",id).eq("tenant_id",tenantId).in("status",["draft","submitted"]);if(error)throw error;if(!purchase){const {data,error:deliveryError}=await db.rpc("create_delivery_for_approved_order",{p_sales_order_id:id,p_delivery_man_employee_id:null});if(deliveryError)throw deliveryError;if(data?.success!==true)throw new Error("Delivery allocation was not confirmed.");setNotice("Sales order approved and delivery "+data.delivery_number+" created. Invoice will be generated automatically after dispatch and delivery confirmation.");}else setNotice("Purchase order approved.");await loadAll();}catch(e){setNotice(e instanceof Error?e.message:"Approval failed. Check your database permissions.");}}
 async function save(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try{
   if(!partyId)throw new Error(purchase?"Please select a supplier.":"Please select a customer.");
   const clean=lines.filter(l=>l.product_id&&l.unit_id&&Number(l.quantity)>0);
   if(!clean.length)throw new Error("Add at least one product with a valid quantity.");
   for(const l of clean){const pu=allowedUnits(l.product_id).find(x=>x.unit_id===l.unit_id);if(!pu)throw new Error("No valid unit was found for the selected product.");const q=Number(l.quantity),rate=Number(l.rate),taxRate=Number(l.tax_rate),discountValue=Number(l.discount);if(![q,rate,taxRate,discountValue].every(Number.isFinite)||q<=0||rate<0||taxRate<0||discountValue<0)throw new Error("Quantity, rate, tax and discount must be valid non-negative values.");if(discountValue>q*rate+0.000001)throw new Error("A line discount cannot exceed the pre-tax gross amount.");}
   const subtotal=clean.reduce((s,l)=>s+Number(l.quantity)*Number(l.rate),0);
   const tax=clean.reduce((s,l)=>s+Math.max(0,Number(l.quantity)*Number(l.rate)-Number(l.discount))*Number(l.tax_rate)/100,0);
   const discount=clean.reduce((s,l)=>s+Number(l.discount),0);
   const {data:doc,error:docError}=await db.rpc("next_document_number",{p_tenant_id:tenantId,p_document_type:purchase?"purchase_order":"sales_order"});if(docError)throw docError;if(typeof doc!=="string"||!doc)throw new Error("Document number could not be generated.");
   const {data:userData}=await db.auth.getUser();
   const header:any={tenant_id:tenantId,order_date:new Date().toISOString(),status:"draft",subtotal,tax_total:tax,discount_total:discount,grand_total:subtotal+tax-discount,notes:notes.trim()||null,created_by:userData.user?.id??null};
   if(purchase){header.po_number=doc;header.supplier_id=partyId;if(warehouseId)header.warehouse_id=warehouseId;}
   else {header.order_number=doc;header.customer_id=partyId;header.order_source="backoffice";header.booker_employee_id=bookerId||null;header.route_id=routeId||null;header.delivery_man_employee_id=deliveryManId||null;if(warehouseId)header.warehouse_id=warehouseId;}
   const {data:created,error}=await db.from(table).insert(header).select("id").single();
   if(error)throw error;
   const detail=clean.map(l=>{const pu=allowedUnits(l.product_id).find(x=>x.unit_id===l.unit_id)!;const amount=Number(l.quantity)*Number(l.rate);const taxAmount=Math.max(0,amount-Number(l.discount))*Number(l.tax_rate)/100;return {tenant_id:tenantId,[purchase?"purchase_order_id":"sales_order_id"]:created.id,product_id:l.product_id,unit_id:l.unit_id,quantity:Number(l.quantity),conversion_to_base:Number(pu.conversion_to_base),[purchase?"unit_cost":"unit_price"]:Number(l.rate),tax_rate:Number(l.tax_rate)||0,discount_amount:Number(l.discount)||0,line_total:amount+taxAmount-(Number(l.discount)||0)};});
   const lineTable=purchase?"purchase_order_lines":"sales_order_lines";
   const {error:lineError}=await db.from(lineTable).insert(detail);
   if(lineError){const cleanup=await db.from(table).delete().eq("id",created.id).eq("tenant_id",tenantId).eq("status","draft");setNotice("Order lines could not be saved: "+lineError.message+(cleanup.error?" The empty draft could not be removed; please review document "+doc+".":" The empty draft was rolled back."));await loadAll();return;}
   setNotice("Draft "+doc+" saved successfully.");
   setLines([{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}]);setPartyId("");setWarehouseId("");setNotes("");setBookerId("");setRouteId("");setDeliveryManId("");setShowForm(false);await loadAll();
  }catch(err){setNotice(err instanceof Error?err.message:"The transaction could not be saved.");}
  finally{setSaving(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>{purchase?"Purchase Orders":"Sales Orders"}</h2><p>{purchase?"Vendor purchase orders and item-wise cost tracking.":"Customer sales orders with item pricing, tax and discount."}</p></div><button className="primary-action" onClick={()=>{setShowForm(!showForm);setNotice("");}}>{showForm?"Close form":purchase?"+ New purchase":"+ New sales order"}</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {showForm&&<form className="transaction-form" onSubmit={save}>
   <div className="form-grid"><label>{purchase?"Vendor":"Customer"}<select required value={partyId} onChange={e=>void selectParty(e.target.value)}><option value="">Select {purchase?"supplier":"customer"}</option>{parties.map(p=><option key={p.id} value={p.id}>{p.party_code} · {p.name}</option>)}</select></label><label>{purchase?"Warehouse (optional)":"Warehouse (required)"}<select required={!purchase} value={warehouseId} onChange={e=>setWarehouseId(e.target.value)}><option value="">Default / not selected</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Reference / remarks"/></label>{!purchase&&<><label>Booker<select value={bookerId} onChange={e=>setBookerId(e.target.value)}><option value="">Select Booker / employee</option>{employees.filter(x=>(x.job_title||"").toLowerCase().includes("book")||true).map(x=><option key={x.id} value={x.id}>{x.full_name} · {x.job_title||"Employee"}</option>)}</select></label><label>Sales route / area<select value={routeId} onChange={e=>setRouteId(e.target.value)}><option value="">Select route</option>{routes.map(x=><option key={x.id} value={x.id}>{x.route_code} · {x.name}</option>)}</select></label><label>Delivery man<select value={deliveryManId} onChange={e=>setDeliveryManId(e.target.value)}><option value="">Assign later</option>{employees.filter(x=>(x.job_title||"").toLowerCase().includes("delivery")||(x.job_title||"").toLowerCase().includes("driver")).map(x=><option key={x.id} value={x.id}>{x.full_name}</option>)}</select></label></>}</div>
   <div className="line-heading"><b>Order items</b><button type="button" onClick={()=>setLines(x=>[...x,{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}])}>+ Add line</button></div>
   {lines.map((l,i)=><div className="order-line" key={i}><label>Product<select required value={l.product_id} onChange={e=>changeLine(i,"product_id",e.target.value)}><option value="">Select product</option>{products.map(p=><option key={p.id} value={p.id}>{p.sku} · {p.name}{p.barcode?` · ${p.barcode}`:""}</option>)}</select></label><label>Unit<select required value={l.unit_id} onChange={e=>changeLine(i,"unit_id",e.target.value)}><option value="">Select unit</option>{allowedUnits(l.product_id).map(pu=><option key={pu.id} value={pu.unit_id}>{units.find(u=>u.id===pu.unit_id)?.symbol||units.find(u=>u.id===pu.unit_id)?.name||"Unit"} (×{pu.conversion_to_base})</option>)}</select></label><label>Qty<input required type="number" min="0.001" step="0.001" value={l.quantity} onChange={e=>changeLine(i,"quantity",e.target.value)}/></label><label>{purchase?"Unit cost":"Unit price"}<input required type="number" min="0" step="0.01" value={l.rate} onChange={e=>changeLine(i,"rate",e.target.value)}/></label><label>Tax %<input type="number" min="0" step="0.01" value={l.tax_rate} onChange={e=>changeLine(i,"tax_rate",e.target.value)}/></label><label>Discount PKR<input type="number" min="0" step="0.01" value={l.discount} onChange={e=>changeLine(i,"discount",e.target.value)}/></label><button type="button" className="remove-line" onClick={()=>setLines(x=>x.length>1?x.filter((_,n)=>n!==i):x)}>×</button></div>)}
   <div className="transaction-total"><span>Estimated total</span><b>{money(total)}</b></div><button disabled={saving||!products.length||!parties.length}>{saving?"Saving draft…":"Save as draft"}</button>
   {!products.length&&<small>Add products and their purchase/sales units in Product Master first.</small>}
  </form>}
  <div className="table-tools"><input placeholder="Search document number or status…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} records</span><button onClick={()=>void loadAll()}>↻ Refresh</button><button onClick={exportOrders}>Export Excel (CSV)</button><button onClick={()=>window.print()}>Print / PDF</button></div>
  {loading?<div className="table-empty">Loading transactions…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Document</th><th>Date</th>{!purchase&&<><th>Booker</th><th>Route / Area</th><th>Delivery man</th></>}<th>Status</th><th>Total</th><th>Workflow</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{purchase?r.po_number:r.order_number}</td><td>{new Date(r.order_date).toLocaleDateString("en-PK")}</td>{!purchase&&<><td>{employees.find(x=>x.id===r.booker_employee_id)?.full_name||"—"}</td><td>{routes.find(x=>x.id===r.route_id)?.name||"—"}</td><td>{employees.find(x=>x.id===r.delivery_man_employee_id)?.full_name||"Not assigned"}</td></>}<td><span className="status-active">{r.status}</span></td><td>{money(r.grand_total)}</td><td>{!purchase&&<button onClick={()=>void preparePrint(r)}>Print copy</button>} {["owner","admin","manager"].includes(currentRole)&&["draft","submitted"].includes(r.status)?<button onClick={()=>void approve(r.id)}>Approve</button>:""}</td></tr>)}{!filtered.length&&<tr><td colSpan={purchase?5:8} className="table-empty">No records found.</td></tr>}</tbody></table></div>}
  {printDoc&&printParty&&<section className="print-document"><div className="print-top"><h2>EBS PRO V.01</h2><strong>SALES ORDER</strong><p>Wholesale & Distribution</p></div><div className="print-meta"><div><b>Customer</b><br/>{printParty.name}<br/>{printParty.phone||""}<br/>{printParty.address||""}</div><div><b>Document</b><br/>{printDoc.order_number}<br/>{new Date(printDoc.order_date).toLocaleDateString("en-PK")}<br/>Status: {printDoc.status}</div></div><table className="print-table"><thead><tr><th>Item</th><th>Qty</th><th>Rate</th><th>Tax</th><th>Discount</th><th>Total</th></tr></thead><tbody>{printLines.map((l,i)=><tr key={i}><td>{products.find(p=>p.id===l.product_id)?.name||l.product_id}{products.find(p=>p.id===l.product_id)?.barcode?<small>Barcode: {products.find(p=>p.id===l.product_id)?.barcode}</small>:null}</td><td>{l.quantity} {units.find(u=>u.id===l.unit_id)?.symbol||""}</td><td>{money(l.unit_price)}</td><td>{l.tax_rate}%</td><td>{money(l.discount_amount)}</td><td>{money(l.line_total)}</td></tr>)}</tbody></table><div className="print-total">Grand total: {money(printDoc.grand_total)}</div><p className="print-note">This is a sales order copy, not a tax invoice or proof of payment.</p><div className="print-actions"><button onClick={()=>window.print()}>Print</button><button onClick={()=>setPrintDoc(null)}>Close</button></div></section>}
  <p className="module-footnote">Orders are saved as drafts and require approval. Approved orders can be allocated to delivery; dispatch deducts stock through the controlled database workflow. Printed copies are sales order copies, not tax invoices.</p>
 </section>;
}
