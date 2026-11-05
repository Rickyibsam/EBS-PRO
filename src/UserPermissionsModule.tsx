import {useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Member={id:string;user_id:string;role:string;is_active:boolean;full_name?:string;employee_code?:string;email?:string};
type Permission={can_view:boolean;can_create:boolean;can_update:boolean;can_delete:boolean};
type PermissionRow=Permission&{id:string;tenant_id:string;user_id:string;module_key:string};
const modules=[
 {key:"dashboard_management",label:"Dashboard & Management"},
 {key:"sales_customer",label:"Sales & Customer Management"},
 {key:"order_booking",label:"Order Booking App"},
 {key:"inventory",label:"Inventory & Warehouse"},
 {key:"purchase_supplier",label:"Purchase & Supplier Management"},
 {key:"accounts_finance",label:"Accounts & Finance"},
 {key:"distribution_delivery",label:"Distribution & Delivery"},
 {key:"hr_payroll",label:"HR & Payroll"},
 {key:"reports_analytics",label:"Reports & Analytics"},
 {key:"administration_security",label:"Administration & Security"}
];
const empty:Permission={can_view:false,can_create:false,can_update:false,can_delete:false};
const keyOf=(userId:string,moduleKey:string)=>userId+":"+moduleKey;
export default function UserPermissionsModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [members,setMembers]=useState<Member[]>([]);
 const [overrides,setOverrides]=useState<Record<string,Permission>>({});
 const [enabled,setEnabled]=useState<Record<string,boolean>>({});
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(""),[notice,setNotice]=useState("");
 async function load(){
  setLoading(true);setNotice("");
  try{
   const [m,e,p]=await Promise.all([
    db.from("tenant_memberships").select("id,user_id,role,is_active").eq("tenant_id",tenantId).order("created_at"),
    db.from("employees").select("user_id,full_name,employee_code").eq("tenant_id",tenantId),
    db.from("tenant_user_module_permissions").select("id,user_id,module_key,can_view,can_create,can_update,can_delete").eq("tenant_id",tenantId)
   ]);
   const err=m.error||e.error||p.error;if(err)throw err;
   const employees=e.data||[];
   setMembers((m.data||[]).map(x=>({...x,...(employees.find(y=>y.user_id===x.user_id)||{})})));
   const nextEnabled:Record<string,boolean>={},nextOverrides:Record<string,Permission>={};
   (p.data||[]).forEach((x:PermissionRow)=>{const k=keyOf(x.user_id,x.module_key);nextEnabled[k]=true;nextOverrides[k]={can_view:x.can_view,can_create:x.can_create,can_update:x.can_update,can_delete:x.can_delete};});
   setEnabled(nextEnabled);setOverrides(nextOverrides);
  }catch(err){setNotice(err instanceof Error?err.message:"Unable to load user permissions.");}
  finally{setLoading(false);}
 }
 useEffect(()=>{void load();},[tenantId]);
 function toggle(userId:string,moduleKey:string,field:keyof Permission,value:boolean){
  const k=keyOf(userId,moduleKey);
  setEnabled(v=>({...v,[k]:true}));
  setOverrides(v=>{const current=v[k]||{...empty};const next={...current,[field]:value};if(field==="can_view"&&!value){next.can_create=false;next.can_update=false;next.can_delete=false;}return {...v,[k]:next};});
 }
 async function saveMember(member:Member){
  if(!["owner"].includes(currentRole))return;
  setSaving(member.user_id);setNotice("");
  try{
   const changes=modules.map(async mod=>{
    const k=keyOf(member.user_id,mod.key);
    if(!enabled[k]){
     const {error}=await db.from("tenant_user_module_permissions").delete().eq("tenant_id",tenantId).eq("user_id",member.user_id).eq("module_key",mod.key);
     if(error)throw error;return;
    }
    const permission=overrides[k]||empty;
    const {error}=await db.from("tenant_user_module_permissions").upsert({
     tenant_id:tenantId,user_id:member.user_id,module_key:mod.key,...permission,updated_by:(await db.auth.getUser()).data.user?.id
    },{onConflict:"tenant_id,user_id,module_key"});
    if(error)throw error;
   });
   await Promise.all(changes);setNotice("Permissions saved for "+(member.full_name||member.email||member.user_id.slice(0,8))+".");
   await load();
  }catch(err){setNotice(err instanceof Error?err.message:"Unable to save permissions.");}
  finally{setSaving("");}
 }
 if(currentRole!=="owner")return <section className="module-page"><h2>Owner access required</h2><p>Only the company owner can configure individual user permissions.</p></section>;
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Individual User Permissions</h2><p>Override a staff member’s role defaults module by module. When an override is disabled, the original role permissions remain in effect. Explicit overrides are also enforced by database row-level security.</p></div><button className="primary-action" onClick={()=>void load()} disabled={loading}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {loading?<div className="table-empty">Loading company members and permission rules…</div>:members.length===0?<div className="table-empty">No staff accounts found.</div>:members.map(member=>{
   const locked=["owner","admin"].includes(member.role);
   return <article className="permission-member" key={member.user_id}>
    <div className="permission-member-head"><div><strong>{member.full_name||member.email||"Staff account"}</strong><span>{member.employee_code?member.employee_code+" · ":""}{member.role.replaceAll("_"," ")} · {member.is_active?"Active":"Inactive"}</span></div>{locked&&<span className="permission-lock">Role-managed access</span>}</div>
    {locked?<p className="module-footnote">Owner and administrator access follows the protected role baseline and cannot be restricted here.</p>:<div className="permission-grid">
     {modules.map(mod=>{const k=keyOf(member.user_id,mod.key),on=!!enabled[k],value=overrides[k]||empty;return <div className="permission-row" key={mod.key}>
      <div className="permission-module"><label><input type="checkbox" checked={on} onChange={e=>setEnabled(v=>({...v,[k]:e.target.checked}))}/><b>{mod.label}</b></label><small>{on?"Custom override enabled":"Using role defaults"}</small></div>
      <div className="permission-actions">{(["can_view","can_create","can_update","can_delete"] as const).map((field,i)=><label key={field} className={!on?"muted":""}><input type="checkbox" disabled={!on||(i>0&&!value.can_view)} checked={on&&value[field]} onChange={e=>toggle(member.user_id,mod.key,field,e.target.checked)}/>{["View","Create","Update","Delete"][i]}</label>)}</div>
     </div>})}
    </div>}
    {!locked&&<div className="permission-save"><button className="primary-action" disabled={saving===member.user_id} onClick={()=>void saveMember(member)}>{saving===member.user_id?"Saving…":"Save "+(member.full_name||"user")+" permissions"}</button></div>}
   </article>;
  })}
  <p className="module-footnote">Security note: custom overrides apply to tenant-scoped business tables. Owner and administrator accounts retain full access. A user must have View enabled before Create, Update or Delete can be used.</p>
 </section>;
}
