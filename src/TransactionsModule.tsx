import { useEffect, useMemo, useState, FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Product={id:string;name:string;sku:string;is_active:boolean;cost_price:number;sale_price:number};
type Party={id:string;name:string;party_code:string};
type Unit={id:string;name:string;symbol:string};
type ProductUnit={id:string;product_id:string;unit_id:string;conversion_to_base:number;is_purchase_unit:boolean;is_sales_unit:boolean};
type Line={product_id:string;unit_id:string;quantity:string;rate:string;tax_rate:string;discount:string};
type Header={id:string;order_number:string;order_date:string;status:string;grand_total:number};
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
 useEffect(()=>{void loadAll();},[tenantId,module]);
 async function loadAll(){
  setLoading(true);setNotice("");
  const [p,pa,u,pu,vc,w,h]=await Promise.all([
   db.from("products").select("id,name,sku,is_active,cost_price,sale_price").eq("tenant_id",tenantId).eq("is_active",true).order("name").limit(1000),
   db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",purchase?["supplier","both"]:["customer","both"]).eq("status","active").order("name").limit(1000),
   db.from("units_of_measure").select("id,name,symbol").eq("tenant_id",tenantId).order("name"),
   db.from("product_units").select("id,product_id,unit_id,conversion_to_base,is_purchase_unit,is_sales_unit").eq("tenant_id",tenantId),
    db.from("vendor_product_catalog").select("supplier_id,product_id,purchase_cost,is_preferred").eq("tenant_id",tenantId),
   db.from("warehouses").select("id,name").eq("tenant_id",tenantId).eq("is_active",true).order("name"),
   db.from(table).select("id,"+(purchase?"po_number":"order_number")+",order_date,status,grand_total").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(200)
  ]);
  const errors=[p.error,pa.error,u.error,pu.error,vc.error,w.error,h.error].filter(Boolean);
  if(errors.length)setNotice(errors.map(e=>e!.message).join(" · "));
  setProducts((p.data??[]) as Product[]);setParties((pa.data??[]) as Party[]);setUnits((u.data??[]) as Unit[]);setProductUnits((pu.data??[]) as ProductUnit[]);setVendorCosts(vc.data??[]);setWarehouses((w.data??[]) as {id:string;name:string}[]);
  setRows((h.data??[]).map((r:any)=>({id:r.id,order_number:purchase?r.po_number:r.order_number,order_date:r.order_date,status:r.status,grand_total:Number(r.grand_total)})));
  setLoading(false);
 }
 async function selectParty(id:string){
  setPartyId(id);
  if(purchase){setLines(old=>old.map(line=>{const v=vendorCosts.find(x=>x.supplier_id===id&&x.product_id===line.product_id);const preferred=vendorCosts.find(x=>x.product_id===line.product_id&&x.is_preferred);const p=products.find(x=>x.id===line.product_id);return line.product_id?{...line,rate:String(v?.purchase_cost??preferred?.purchase_cost??p?.cost_price??0)}:line;}));return;}
  setCustomerPrices([]);
  if(!id)return;
  const {data:assignments,error}=await db.from("customer_price_lists").select("price_list_id").eq("tenant_id",tenantId).eq("customer_id",id);
  if(error){setNotice("Customer pricing could not be loaded: "+error.message);return;}
  const ids=(assignments??[]).map(x=>x.price_list_id);
  if(!ids.length)return;
  const {data,error:priceError}=await db.from("product_prices").select("product_id,unit_id,price,min_quantity").eq("tenant_id",tenantId).in("price_list_id",ids);
  if(priceError){setNotice("Customer product prices could not be loaded: "+priceError.message);return;}
  setCustomerPrices(price??[]);
 }
 function allowedUnits(productId:string){return productUnits.filter(x=>x.product_id===productId&&(purchase?x.is_purchase_unit:x.is_sales_unit));}
 function changeLine(i:number,key:keyof Line,value:string){setLines(old=>old.map((r,n)=>{if(n!==i)return r;if(key==="product_id"){const p=products.find(x=>x.id===value);const supplierCost=vendorCosts.find(x=>x.supplier_id===partyId&&x.product_id===value);const preferredCost=vendorCosts.find(x=>x.product_id===value&&x.is_preferred);const listPrice=customerPrices.filter(x=>x.product_id===value&&x.unit_id===(allowedUnits(value)[0]?.unit_id??"")).sort((a,b)=>Number(b.min_quantity)-Number(a.min_quantity))[0];const rate=purchase?(supplierCost?.purchase_cost??preferredCost?.purchase_cost??p?.cost_price??0):(listPrice?.price??p?.sale_price??0);return {...r,product_id:value,unit_id:allowedUnits(value)[0]?.unit_id??"",rate:String(rate)};}return {...r,[key]:value};}));}
 const total=useMemo(()=>lines.reduce((s,l)=>{const base=(Number(l.quantity)||0)*(Number(l.rate)||0);return s+base+base*(Number(l.tax_rate)||0)/100-(Number(l.discount)||0);},0),[lines]);
 const filtered=rows.filter(r=>r.order_number.toLowerCase().includes(search.toLowerCase())||r.status.toLowerCase().includes(search.toLowerCase()));
 async function preparePrint(row:Header){setNotice("");try{const [lineResult,headResult]=await Promise.all([db.from("sales_order_lines").select("product_id,unit_id,quantity,unit_price,tax_rate,discount_amount,line_total").eq("tenant_id",tenantId).eq("sales_order_id",row.id),db.from("sales_orders").select("customer_id").eq("tenant_id",tenantId).eq("id",row.id).single()]);if(lineResult.error)throw lineResult.error;if(headResult.error)throw headResult.error;const {data:party,error}=await db.from("parties").select("name,phone,address").eq("tenant_id",tenantId).eq("id",headResult.data.customer_id).single();if(error)throw error;setPrintDoc(row);setPrintLines(lineResult.data??[]);setPrintParty(party);}catch(e){setNotice(e instanceof Error?e.message:"Sales order print preview could not be prepared.");}}
 async function approve(id:string){setNotice("");try{const {data:user}=await db.auth.getUser();const {error}=await db.from(table).update({status:"approved",approved_by:user.user?.id??null}).eq("id",id).eq("tenant_id",tenantId).in("status",["draft","submitted"]);if(error)throw error;setNotice("Document approved.");await loadAll();}catch(e){setNotice(e instanceof Error?e.message:"Approval failed. Check your database permissions.");}}
 async function save(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try{
   if(!partyId)throw new Error(purchase?"Please select a supplier.":"Please select a customer.");
   const clean=lines.filter(l=>l.product_id&&l.unit_id&&Number(l.quantity)>0);
   if(!clean.length)throw new Error("Add at least one product with a valid quantity.");
   for(const l of clean){const pu=allowedUnits(l.product_id).find(x=>x.unit_id===l.unit_id);if(!pu)throw new Error("No valid unit was found for the selected product.");const q=Number(l.quantity),rate=Number(l.rate),taxRate=Number(l.tax_rate),discountValue=Number(l.discount);if(![q,rate,taxRate,discountValue].every(Number.isFinite)||q<=0||rate<0||taxRate<0||discountValue<0)throw new Error("Quantity, rate, tax and discount must be valid non-negative values.");if(rate>0&&discountValue>=q*rate)throw new Error("A line discount must be lower than the pre-tax gross amount.");}
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
   if(lineError){const cleanup=await db.from(table).delete().eq("id",created.id).eq("tenant_id",tenantId).eq("status","draft");setNotice("Order lines could not be saved: "+lineError.message+(cleanup.error?" The empty draft could not be removed; please review document "+doc+".":" The empty draft was rolled back."));await loadAll();return;}
   setNotice("Draft "+doc+" saved successfully.");
   setLines([{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}]);setPartyId("");setWarehouseId("");setNotes("");setShowForm(false);await loadAll();
  }catch(err){setNotice(err instanceof Error?err.message:"The transaction could not be saved.");}
  finally{setSaving(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>{purchase?"Purchase Orders":"Sales Orders"}</h2><p>{purchase?"Supplier purchase orders and item-wise cost tracking.":"Customer sales orders with item pricing, tax and discount."}</p></div><button className="primary-action" onClick={()=>{setShowForm(!showForm);setNotice("");}}>{showForm?"Close form":purchase?"+ New purchase":"+ New sales order"}</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {showForm&&<form className="transaction-form" onSubmit={save}>
   <div className="form-grid"><label>{purchase?"Supplier":"Customer"}<select required value={partyId} onChange={e=>void selectParty(e.target.value)}><option value="">Select {purchase?"supplier":"customer"}</option>{parties.map(p=><option key={p.id} value={p.id}>{p.party_code} · {p.name}</option>)}</select></label><label>Warehouse (optional)<select value={warehouseId} onChange={e=>setWarehouseId(e.target.value)}><option value="">Default / not selected</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Reference / remarks"/></label></div>
   <div className="line-heading"><b>Order items</b><button type="button" onClick={()=>setLines(x=>[...x,{product_id:"",unit_id:"",quantity:"1",rate:"0",tax_rate:"0",discount:"0"}])}>+ Add line</button></div>
   {lines.map((l,i)=><div className="order-line" key={i}><label>Product<select required value={l.product_id} onChange={e=>changeLine(i,"product_id",e.target.value)}><option value="">Select product</option>{products.map(p=><option key={p.id} value={p.id}>{p.sku} · {p.name}</option>)}</select></label><label>Unit<select required value={l.unit_id} onChange={e=>changeLine(i,"unit_id",e.target.value)}><option value="">Select unit</option>{allowedUnits(l.product_id).map(pu=><option key={pu.id} value={pu.unit_id}>{units.find(u=>u.id===pu.unit_id)?.symbol||units.find(u=>u.id===pu.unit_id)?.name||"Unit"} (×{pu.conversion_to_base})</option>)}</select></label><label>Qty<input required type="number" min="0.001" step="0.001" value={l.quantity} onChange={e=>changeLine(i,"quantity",e.target.value)}/></label><label>{purchase?"Unit cost":"Unit price"}<input required type="number" min="0" step="0.01" value={l.rate} onChange={e=>changeLine(i,"rate",e.target.value)}/></label><label>Tax %<input type="number" min="0" step="0.01" value={l.tax_rate} onChange={e=>changeLine(i,"tax_rate",e.target.value)}/></label><label>Discount PKR<input type="number" min="0" step="0.01" value={l.discount} onChange={e=>changeLine(i,"discount",e.target.value)}/></label><button type="button" className="remove-line" onClick={()=>setLines(x=>x.length>1?x.filter((_,n)=>n!==i):x)}>×</button></div>)}
   <div className="transaction-total"><span>Estimated total</span><b>{money(total)}</b></div><button disabled={saving||!products.length||!parties.length}>{saving?"Saving draft…":"Save as draft"}</button>
   {!products.length&&<small>Add products and their purchase/sales units in Product Master first.</small>}
  </form>}
  <div className="table-tools"><input placeholder="Search document number or status…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} records</span><button onClick={()=>void loadAll()}>↻ Refresh</button></div>
  {loading?<div className="table-empty">Loading transactions…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Document</th><th>Date</th><th>Status</th><th>Total</th><th>Workflow</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{r.order_number}</td><td>{new Date(r.order_date).toLocaleDateString("en-PK")}</td><td><span className="status-active">{r.status}</span></td><td>{money(r.grand_total)}</td><td>{!purchase&&<button onClick={()=>void preparePrint(r)}>Print copy</button>} {["owner","admin","manager"].includes(currentRole)&&["draft","submitted"].includes(r.status)?<button onClick={()=>void approve(r.id)}>Approve</button>:""}</td></tr>)}{!filtered.length&&<tr><td colSpan={5} className="table-empty">No records found.</td></tr>}</tbody></table></div>}
  {printDoc&&printParty&&<section className="print-document"><div className="print-top"><h2>EBS PRO V.01</h2><strong>SALES ORDER</strong><p>Wholesale & Distribution</p></div><div className="print-meta"><div><b>Customer</b><br/>{printParty.name}<br/>{printParty.phone||""}<br/>{printParty.address||""}</div><div><b>Document</b><br/>{printDoc.order_number}<br/>{new Date(printDoc.order_date).toLocaleDateString("en-PK")}<br/>Status: {printDoc.status}</div></div><table className="print-table"><thead><tr><th>Item</th><th>Qty</th><th>Rate</th><th>Tax</th><th>Discount</th><th>Total</th></tr></thead><tbody>{printLines.map((l,i)=><tr key={i}><td>{products.find(p=>p.id===l.product_id)?.name||l.product_id}</td><td>{l.quantity} {units.find(u=>u.id===l.unit_id)?.symbol||""}</td><td>{money(l.unit_price)}</td><td>{l.tax_rate}%</td><td>{money(l.discount_amount)}</td><td>{money(l.line_total)}</td></tr>)}</tbody></table><div className="print-total">Grand total: {money(printDoc.grand_total)}</div><p className="print-note">This is a sales order copy, not a tax invoice or proof of payment.</p><div className="print-actions"><button onClick={()=>window.print()}>Print</button><button onClick={()=>setPrintDoc(null)}>Close</button></div></section>}\n  <p className="module-footnote">Orders are saved as drafts and require approval. Approved orders can be allocated to delivery; dispatch deducts stock through the controlled database workflow. Printed copies are sales order copies, not tax invoices.</p>
 </section>;
}
