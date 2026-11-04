import { FormEvent, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, any>;
const roles = ["owner","admin","manager","accounts","purchase","sales","order_booker","warehouse","cashier","viewer"];

export default function AdminModule({db,tenantId,module,currentRole}:{db:SupabaseClient;tenantId:string;module:string;currentRole:string}) {
 const [rows,setRows]=useState<Row[]>([]);
 const [lookups,setLookups]=useState<{customers:Row[];employees:Row[];routes:Row[]}>({customers:[],employees:[],routes:[]});
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const [showForm,setShowForm]=useState(false),[search,setSearch]=useState("");
 const [form,setForm]=useState<Record<string,string>>({});
 const [settings,setSettings]=useState("{}");
 const team=module==="Team & Employees", routes=module==="Routes", booker=module==="Booker App", config=module==="Settings";
 const title=team?"Team & Employee Directory":routes?"Sales Route Management":booker?"Booker Visit Register":"Company Settings";
 const roleLabel=(r:string)=>r.replaceAll("_"," ").replace(/\b\w/g,x=>x.toUpperCase());
 async function load(){
  setLoading(true);setNotice("");
  try {
   if(team){
    const [e,m]=await Promise.all([db.from("employees").select("id,employee_code,full_name,phone,job_title,employment_status,branch_id,user_id").eq("tenant_id",tenantId).order("full_name"),db.from("tenant_memberships").select("id,user_id,role,is_active,created_at").eq("tenant_id",tenantId).order("created_at")]);
    if(e.error)throw e.error;if(m.error)throw m.error;setRows([...(e.data??[]).map(x=>({...x,_kind:"Employee"})),...(m.data??[]).map(x=>({...x,_kind:"Login account"}))]);
   } else if(routes){
    const {data,error}=await db.from("sales_routes").select("id,route_code,name,area_description,is_active,branch_id").eq("tenant_id",tenantId).order("name");if(error)throw error;setRows(data??[]);
   } else if(booker){
    const [v,c,e,r]=await Promise.all([db.from("booker_visits").select("id,visit_at,visit_status,customer_id,booker_employee_id,route_id,notes").eq("tenant_id",tenantId).order("visit_at",{ascending:false}).limit(300),db.from("parties").select("id,name,party_code").eq("tenant_id",tenantId).in("party_type",["customer","both"]).eq("status","active").order("name"),db.from("employees").select("id,full_name,employee_code").eq("tenant_id",tenantId).eq("employment_status","active").order("full_name"),db.from("sales_routes").select("id,name,route_code").eq("tenant_id",tenantId).eq("is_active",true).order("name")]);
    const err=[v.error,c.error,e.error,r.error].find(Boolean);if(err)throw err;setRows(v.data??[]);setLookups({customers:c.data??[],employees:e.data??[],routes:r.data??[]});
   } else if(config){
    const {data,error}=await db.from("app_settings").select("settings").eq("tenant_id",tenantId).maybeSingle();if(error)throw error;const val=data?.settings??{};setSettings(JSON.stringify(val,null,2));setRows([{settings:val}]);
   }
  } catch(err){setNotice(err instanceof Error?err.message:"Unable to load this module.");}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId,module]);
 async function save(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try {
   if(team){
    const {error}=await db.from("employees").insert({tenant_id:tenantId,employee_code:form.employee_code.trim(),full_name:form.full_name.trim(),phone:form.phone.trim()||null,job_title:form.job_title.trim()||null,employment_status:"active",branch_id:form.branch_id||null});
    if(error)throw error;setNotice("Employee record created. Login access must be invited separately by an administrator.");
   } else if(routes){
    const {error}=await db.from("sales_routes").insert({tenant_id:tenantId,route_code:form.route_code.trim(),name:form.name.trim(),area_description:form.area_description.trim()||null,is_active:true});
    if(error)throw error;setNotice("Sales route created successfully.");
   } else if(booker){
    const {data:user}=await db.auth.getUser();
    const {error}=await db.from("booker_visits").insert({tenant_id:tenantId,customer_id:form.customer_id,booker_employee_id:form.booker_employee_id||null,route_id:form.route_id||null,visit_status:form.visit_status||"visited",notes:form.notes.trim()||null,created_by:user.user?.id??null});
    if(error)throw error;setNotice("Booker visit saved successfully.");
   }
   setForm({});setShowForm(false);await load();
  } catch(err){setNotice(err instanceof Error?err.message:"The record could not be saved.");}
  setSaving(false);
 }
 async function updateMember(id:string,patch:Row){
  setNotice("");const {error}=await db.from("tenant_memberships").update(patch).eq("id",id).eq("tenant_id",tenantId);
  if(error)setNotice(error.message);else {setNotice("Team access updated.");await load();}
 }
 async function saveSettings(e:FormEvent){
  e.preventDefault();setSaving(true);setNotice("");
  try{const parsed=JSON.parse(settings);const {error}=await db.from("app_settings").upsert({tenant_id:tenantId,settings:parsed,updated_at:new Date().toISOString()},{onConflict:"tenant_id"});if(error)throw error;setNotice("Company settings saved.");await load();}
  catch(err){setNotice(err instanceof Error?err.message:"Settings must contain valid JSON.");}
  setSaving(false);
 }
 const filtered=rows.filter(r=>JSON.stringify(r).toLowerCase().includes(search.toLowerCase()));
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>{title}</h2><p>{team?"Employee records and existing company login roles.":routes?"Create and maintain customer visit routes.":booker?"Record field visits for customer order-booking operations.":"Manage company-level configuration stored in the database."}</p></div>{!config&&<button className="primary-action" onClick={()=>{setShowForm(!showForm);setNotice("");}}>{showForm?"Close form":team?"+ Add employee":routes?"+ Add route":"+ Record visit"}</button>}</div>
  {notice&&<div className="notice">{notice}</div>}
  {showForm&&<form className="data-form" onSubmit={save}>
   {team&&<><label>Employee code<input required value={form.employee_code??""} onChange={e=>setForm({...form,employee_code:e.target.value})}/></label><label>Full name<input required value={form.full_name??""} onChange={e=>setForm({...form,full_name:e.target.value})}/></label><label>Phone<input value={form.phone??""} onChange={e=>setForm({...form,phone:e.target.value})}/></label><label>Job title<input value={form.job_title??""} onChange={e=>setForm({...form,job_title:e.target.value})}/></label></>}
   {routes&&<><label>Route code<input required value={form.route_code??""} onChange={e=>setForm({...form,route_code:e.target.value})}/></label><label>Route name<input required value={form.name??""} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Area description<input value={form.area_description??""} onChange={e=>setForm({...form,area_description:e.target.value})}/></label></>}
   {booker&&<><label>Customer<select required value={form.customer_id??""} onChange={e=>setForm({...form,customer_id:e.target.value})}><option value="">Select customer</option>{lookups.customers.map(x=><option key={x.id} value={x.id}>{x.party_code} · {x.name}</option>)}</select></label><label>Booker / employee<select value={form.booker_employee_id??""} onChange={e=>setForm({...form,booker_employee_id:e.target.value})}><option value="">Not assigned</option>{lookups.employees.map(x=><option key={x.id} value={x.id}>{x.employee_code} · {x.full_name}</option>)}</select></label><label>Route<select value={form.route_id??""} onChange={e=>setForm({...form,route_id:e.target.value})}><option value="">No route</option>{lookups.routes.map(x=><option key={x.id} value={x.id}>{x.route_code} · {x.name}</option>)}</select></label><label>Visit status<select value={form.visit_status??"visited"} onChange={e=>setForm({...form,visit_status:e.target.value})}><option value="visited">Visited</option><option value="order_taken">Order taken</option><option value="no_order">No order</option><option value="closed">Closed</option></select></label><label>Notes<input value={form.notes??""} onChange={e=>setForm({...form,notes:e.target.value})}/></label></>}
   <button disabled={saving}>{saving?"Saving…":"Save record"}</button>
  </form>}
  {config?<form className="data-form" onSubmit={saveSettings}><label>Company settings (JSON)<textarea rows={14} value={settings} onChange={e=>setSettings(e.target.value)}/></label><button disabled={saving}>{saving?"Saving…":"Save settings"}</button><p className="module-footnote">Settings are stored per company. Keep secrets and API keys out of this field.</p></form>:<><div className="table-tools"><input placeholder="Search records…" value={search} onChange={e=>setSearch(e.target.value)}/><span>{filtered.length} records</span><button onClick={()=>void load()}>↻ Refresh</button></div>
  {loading?<div className="table-empty">Loading records…</div>:team?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Type</th><th>Code / User ID</th><th>Name / Role</th><th>Contact / Status</th><th>Access control</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{r._kind}</td><td>{r.employee_code||r.user_id}</td><td>{r.full_name||(r.role==="owner"&&currentRole!=="owner"?<strong>Owner</strong>:<select value={r.role} onChange={e=>updateMember(r.id,{role:e.target.value})}>{roles.filter(x=>currentRole==="owner"||x!=="owner").map(x=><option key={x} value={x}>{roleLabel(x)}</option>)}</select>)}</td><td>{r.phone|| (r.is_active===undefined?r.employment_status:(r.is_active?"Active":"Disabled"))}</td><td>{r._kind==="Login account"&&(currentRole==="owner"||currentRole==="admin")?<button disabled={r.role==="owner"&&currentRole!=="owner"} onClick={()=>updateMember(r.id,{is_active:!r.is_active})}>{r.is_active?"Disable access":"Enable access"}</button>:r._kind==="Login account"?"View only":"Employee profile"}</td></tr>)}{!filtered.length&&<tr><td colSpan={5} className="table-empty">No records found.</td></tr>}</tbody></table></div>:routes?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Route code</th><th>Route name</th><th>Area</th><th>Status</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{r.route_code}</td><td>{r.name}</td><td>{r.area_description||"—"}</td><td>{r.is_active?"Active":"Inactive"}</td></tr>)}{!filtered.length&&<tr><td colSpan={4} className="table-empty">No routes found.</td></tr>}</tbody></table></div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Visit date</th><th>Customer ID</th><th>Booker ID</th><th>Route ID</th><th>Status</th><th>Notes</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{new Date(r.visit_at).toLocaleString("en-PK")}</td><td>{r.customer_id}</td><td>{r.booker_employee_id||"—"}</td><td>{r.route_id||"—"}</td><td>{r.visit_status}</td><td>{r.notes||"—"}</td></tr>)}{!filtered.length&&<tr><td colSpan={6} className="table-empty">No visits found.</td></tr>}</tbody></table></div>}
  </>}
 </section>;
}
