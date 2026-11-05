import {useState,type ChangeEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Backup=Record<string,any>;
export default function BackupRestoreModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const allowed=["owner","admin"].includes(currentRole);
 const [backup,setBackup]=useState<Backup|null>(null),[fileName,setFileName]=useState(""),[busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[result,setResult]=useState<Backup|null>(null);
 async function downloadBackup(){
  if(!allowed)return;setBusy(true);setNotice("");setResult(null);
  try{
   const {data,error}=await db.rpc("export_tenant_backup",{p_tenant_id:tenantId});if(error)throw error;
   const blob=new Blob([JSON.stringify(data,null,2)],{type:"application/json;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");
   a.href=url;a.download="EBS-PRO-backup-"+new Date().toISOString().slice(0,10)+".json";a.click();URL.revokeObjectURL(url);
   setNotice("Company backup downloaded. Keep this file in a secure location outside the ERP.");
  }catch(e){setNotice(e instanceof Error?e.message:"Backup export failed.");}
  finally{setBusy(false);}
 }
 async function chooseBackup(e:ChangeEvent<HTMLInputElement>){
  const file=e.target.files?.[0];if(!file)return;setNotice("");setResult(null);
  try{
   const parsed=JSON.parse(await file.text());
   if(parsed?.format!=="EBS-PRO-TENANT-BACKUP-V1"||parsed?.tenant_id!==tenantId||typeof parsed?.tables!=="object")throw new Error("This backup is invalid or belongs to a different company.");
   setBackup(parsed);setFileName(file.name);setNotice("Backup file validated for this company. Restore will only add missing rows; existing records will not be overwritten or deleted.");
  }catch(err){setBackup(null);setFileName("");setNotice(err instanceof Error?err.message:"Backup file could not be read.");}
 }
 async function restoreBackup(){
  if(!allowed||!backup)return;
  if(!window.confirm("Restore this company backup additively? Existing rows will not be overwritten or deleted. Continue?"))return;
  setBusy(true);setNotice("");setResult(null);
  try{
   const {data,error}=await db.rpc("restore_tenant_backup",{p_tenant_id:tenantId,p_backup:backup});if(error)throw error;
   setResult(data);setNotice("Restore finished. "+Number(data?.imported_rows||0)+" missing records were added; "+(data?.skipped_tables?.length||0)+" table(s) need attention.");
  }catch(e){setNotice(e instanceof Error?e.message:"Backup restore failed.");}
  finally{setBusy(false);}
 }
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Backup & Restore</h2><p>Manual company backup and safe additive restore for EBS PRO.</p></div><button onClick={()=>void downloadBackup()} disabled={!allowed||busy}>{busy?"Working…":"Download company backup"}</button></div>
  {notice&&<div className="notice">{notice}</div>}
  <div className="backup-grid">
   <div className="transaction-form"><h3>1. Create a backup</h3><p>Downloads a JSON snapshot of the company’s tenant-scoped business tables. Passwords, API secrets and tenant membership/role assignments are excluded.</p><button className="primary-action" disabled={!allowed||busy} onClick={()=>void downloadBackup()}>Download backup JSON</button></div>
   <div className="transaction-form"><h3>2. Restore a backup</h3><p>Choose a backup exported from this same company. Restore is additive only: it never deletes or overwrites existing records.</p><label>Backup file<input type="file" accept="application/json,.json" onChange={e=>void chooseBackup(e)}/></label>{fileName&&<p><b>Selected:</b> {fileName}</p>}<button className="primary-action" disabled={!allowed||busy||!backup} onClick={()=>void restoreBackup()}>{busy?"Restoring…":"Restore missing records"}</button></div>
  </div>
  {result&&<div className="transaction-form"><h3>Restore report</h3><div className="kpi-grid"><div><b>{Number(result.imported_rows||0).toLocaleString("en-PK")}</b><span>Records added</span></div><div><b>{result.passes||0}</b><span>Dependency passes</span></div><div><b>{result.skipped_tables?.length||0}</b><span>Tables needing attention</span></div></div>{result.skipped_tables?.length>0&&<><h4>Tables not restored</h4><ul>{result.skipped_tables.map((x:string)=><li key={x}><b>{x}</b>: {result.errors?.[x]||"Unresolved dependency or validation issue"}</li>)}</ul></>}</div>}
  <div className="module-footnote"><b>Important:</b> This is a manual JSON backup, not automatic point-in-time recovery. Restore only inserts missing records and may report tables that could not be restored because related records or validation requirements are missing. Keep multiple dated backup copies outside the hosting account.</div>
 </section>;
}
