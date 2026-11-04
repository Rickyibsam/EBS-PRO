import { FormEvent,useEffect,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
type Row=Record<string,any>;
export default function OperationsModule({db,tenantId,module}:{db:SupabaseClient;tenantId:string;module:string}){
 const [rows,setRows]=useState<Row[]>([]),[loading,setLoading]=useState(true),[notice,setNotice]=useState(""),[counts,setCounts]=useState<Record<string,number>>({});
 const [products,setProducts]=useState<Row[]>([]),[warehouses,setWarehouses]=useState<Row[]>([]);
 const [showForm,setShowForm]=useState(false),[saving,setSaving]=useState(false),[search,setSearch]=useState("");
 const [form,setForm]=useState<Record<string,string>>({});
 const inventory=module==="Inventory",distribution=module==="Distribution",recovery=module==="Recovery",accounts=module==="Accounts",reports=module==="Reports";
 const title=inventory?"Stock Movement Ledger":distribution?"Delivery Management":recovery?"Customer & Supplier Payments":accounts?"Expense Register":"Business Reports";
 useEffect(()=>{void load();},[tenantId,module]);
 async function load(){
  setLoading(true);setNotice("");setRows([]);
  try{
   if(inventory){
    const [m,p,w]=await Promise.all([db.from("stock_movements").select("id,product_id,warehouse_id,movement_type,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,notes").eq("tenant_id",tenantId).order("movement_at",{ascending:false}).limit(300),db.from("products").select("id,sku,name").eq("tenant_id",tenantId).eq("is_active",true).order("name"),db.from("warehouses").select("id,name,code").eq("tenant_id",tenantId).eq("is_active",true).order("name")]);
    const err=[m.error,p.error,w.error].find(Boolean);if(err)throw err;setRows(m.data??[]);setProducts(p.data??[]);setWarehouses(w.data??[]);
   }else if(distribution){
    const {data,error}=await db.from("deliveries").select("id,delivery_number,delivery_date,driver_name,vehicle_number,status,delivered_at,notes").eq("tenant_id",tenantId).order("delivery_date",{ascending:false}).limit(300);if(error)throw error;setRows(data??[]);
   }else if(recovery){
    const {data,error}=await db.from("payments").select("id,payment_number,payment_type,payment_date,method,amount,reference_no,notes").eq("tenant_id",tenantId).order("payment_date",{ascending:false}).limit(300);if(error)throw error;setRows(data??[]);
   }else if(accounts){
    const {data,error}=await db.from("expenses").select("id,expense_number,expense_date,description,amount,payment_method").eq("tenant_id",tenantId).order("expense_date",{ascending:false}).limit(300);if(error)throw error;setRows(data??[]);
   }else if(reports){
    const tables=["sales_orders","purchase_orders","products","parties","payments","stock_movements","deliveries","expenses"];const results=await Promise.all(tables.map(t=>db.from(t).select("id",{count:"exact",head:true}).eq("tenant_id",tenantId)));const err=results.find(x=>x.error);if(err)throw err;setCounts(Object.fromEntries(tables.map((t,i)=>[t,results[i].count??0])));
   }
  }catch(err){setNotice(err instanceof Error?err.message:"Unable to load this module.");}
  setLoading(false);
 }
 async function save(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try{
   const {data:user}=await db.auth.getUser();
   if(inventory){
    const qty=Number(form.quantity),cost=Number(form.unit_cost||0);if(!form.product_id||!form.warehouse_id||!Number.isFinite(qty)||qty<=0)throw new Error("Select a product, warehouse and a quantity greater than zero.");
    const inward=form.direction==="in";
    const {error}=await db.from("stock_movements").insert({tenant_id:tenantId,product_id:form.product_id,warehouse_id:form.warehouse_id,movement_type:"adjustment",quantity_in:inward?qty:0,quantity_out:inward?0:qty,unit_cost:cost,batch_number:form.batch_number||null,expiry_date:form.expiry_date||null,notes:form.notes||"Manual stock adjustment",created_by:user.user?.id??null});
    if(error)throw error;
   }else if(accounts){
    const amount=Number(form.amount);if(!form.description?.trim()||!Number.isFinite(amount)||amount<=0)throw new Error("Enter a description and an amount greater than zero.");
    const number="EBS-EXP-"+Date.now().toString().slice(-9);
    const {error}=await db.from("expenses").insert({tenant_id:tenantId,expense_number:number,expense_date:form.expense_date||new Date().toISOString().slice(0,10),description:form.description.trim(),amount,payment_method:form.payment_method||"cash"});
    if(error)throw error;
   }
   setForm({});setShowForm(false);setNotice(inventory?"Stock adjustment recorded.": "Expense voucher recorded.");await load();
  }catch(err){setNotice(err instanceof Error?err.message:"The record could not be saved.");}
  setSaving(false);
 }
 const columns=inventory?[["movement_at","Date"],["movement_type","Movement"],["product_id","Product ID"],["warehouse_id","Warehouse ID"],["quantity_in","Qty In"],["quantity_out","Qty Out"],["unit_cost","Unit Cost"],["batch_number","Batch"],["expiry_date","Expiry"]]:distribution?[["delivery_number","Delivery"],["delivery_date","Date"],["driver_name","Driver"],["vehicle_number","Vehicle"],["status","Status"],["delivered_at","Delivered"]]:recovery?[["payment_number","Receipt"],["payment_type","Type"],["payment_date","Date"],["method","Method"],["amount","Amount PKR"],["reference_no","Reference"]]:[["expense_number","Voucher"],["expense_date","Date"],["description","Description"],["payment_method","Method"],["amount","Amount PKR"]];
 const filtered=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(search.toLowerCase()));
 return <section className="module-page"><div className="module-toolbar"><div><h2>{title}</h2><p>{reports?"Live record counts from your company's database.":"Live operational records. Stock adjustments and expense vouchers are recorded against this company."}</p></div>{(inventory||accounts)&&<button className="primary-action" onClick={()=>{setShowForm(!showForm);setNotice("");}}>{showForm?"Close form":inventory?"+ Stock adjustment":"+ Add expense"}</button>}</div>{notice&&<div className="notice">{notice}</div>}
 {showForm&&<form className="transaction-form" onSubmit={save}>{inventory?<div className="form-grid"><label>Product<select required value={form.product_id??""} onChange={e=>setForm({...form,product_id:e.target.value})}><option value="">Select product</option>{products.map(p=><option key={p.id} value={p.id}>{p.sku} · {p.name}</option>)}</select></label><label>Warehouse<select required value={form.warehouse_id??""} onChange={e=>setForm({...form,warehouse_id:e.target.value})}><option value="">Select warehouse</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.code} · {w.name}</option>)}</select></label><label>Adjustment direction<select value={form.direction??"in"} onChange={e=>setForm({...form,direction:e.target.value})}><option value="in">Stock increase</option><option value="out">Stock decrease</option></select></label><label>Quantity<input required type="number" min="0.001" step="0.001" value={form.quantity??""} onChange={e=>setForm({...form,quantity:e.target.value})}/></label><label>Unit cost (PKR)<input type="number" min="0" step="0.01" value={form.unit_cost??"0"} onChange={e=>setForm({...form,unit_cost:e.target.value})}/></label><label>Batch number<input value={form.batch_number??""} onChange={e=>setForm({...form,batch_number:e.target.value})}/></label><label>Expiry date<input type="date" value={form.expiry_date??""} onChange={e=>setForm({...form,expiry_date:e.target.value})}/></label><label>Reason / notes<input required value={form.notes??""} onChange={e=>setForm({...form,notes:e.target.value})}/></label></div>:<div className="form-grid"><label>Expense date<input type="date" value={form.expense_date??new Date().toISOString().slice(0,10)} onChange={e=>setForm({...form,expense_date:e.target.value})}/></label><label>Description<input required value={form.description??""} onChange={e=>setForm({...form,description:e.target.value})}/></label><label>Amount (PKR)<input required type="number" min="0.01" step="0.01" value={form.amount??""} onChange={e=>setForm({...form,amount:e.target.value})}/></label><label>Payment method<select value={form.payment_method??"cash"} onChange={e=>setForm({...form,payment_method:e.target.value})}><option value="cash">Cash</option><option value="bank">Bank</option><option value="cheque">Cheque</option><option value="online">Online</option></select></label></div>}<button disabled={saving}>{saving?"Saving…":"Save record"}</button></form>}
 {loading?<div className="table-empty">Loading live data…</div>:reports?<div className="stats report-stats">{Object.entries(counts).map(([k,v])=><article key={k}><small>{k.replaceAll("_"," ")}</small><strong>{v.toLocaleString("en-PK")}</strong><span>Live database records</span></article>)}</div>:<><div className="table-tools"><input placeholder="Search records…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} records</span><button onClick={()=>void load()}>↻ Refresh</button></div><div className="data-table-wrap"><table className="data-table"><thead><tr>{columns.map(([k,l])=><th key={k}>{l}</th>)}</tr></thead><tbody>{filtered.map((r,i)=><tr key={String(r.id??i)}>{columns.map(([k])=><td key={k}>{r[k]===null||r[k]===undefined?"—":k.includes("amount")||k==="unit_cost"?Number(r[k]).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2}):k.includes("date")||k==="movement_at"||k==="delivered_at"?new Date(String(r[k])).toLocaleString("en-PK"):String(r[k])}</td>)}</tr>)}{!filtered.length&&<tr><td className="table-empty" colSpan={columns.length}>No records yet.</td></tr>}</tbody></table></div></>}
 <p className="module-footnote">Stock adjustment entries are recorded in the movement ledger; this does not post purchase or sales documents or calculate the full inventory valuation. Payment receipts and delivery posting still need full workflows.</p></section>;
}
