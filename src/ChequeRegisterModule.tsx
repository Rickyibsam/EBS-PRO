import { FormEvent, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {useModuleAction} from "./lib/modulePermissionContext";

type Cheque = { id:string; party_id:string|null; direction:"received"|"issued"; cheque_number:string; bank_name:string|null; cheque_date:string|null; due_date:string; amount:number; status:string; cleared_date:string|null; notes:string|null; created_at:string };
type Party = { id:string; name:string; party_type:string };
const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
const today=()=>new Date().toISOString().slice(0,10);

export default function ChequeRegisterModule({db,tenantId}:{db:SupabaseClient;tenantId:string}) {
 const [rows,setRows]=useState<Cheque[]>([]),[parties,setParties]=useState<Party[]>([]);
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const [direction,setDirection]=useState<"received"|"issued">("received"),[partyId,setPartyId]=useState("");
 const [chequeNumber,setChequeNumber]=useState(""),[bankName,setBankName]=useState(""),[chequeDate,setChequeDate]=useState(today()),[dueDate,setDueDate]=useState(today()),[amount,setAmount]=useState(""),[notes,setNotes]=useState("");
 const [filter,setFilter]=useState("all"),[search,setSearch]=useState("");
 async function load(){
  setLoading(true);setNotice("");
  const [c,p]=await Promise.all([
   db.from("cheque_register").select("id,party_id,direction,cheque_number,bank_name,cheque_date,due_date,amount,status,cleared_date,notes,created_at").eq("tenant_id",tenantId).order("due_date",{ascending:false}).limit(1000),
   db.from("parties").select("id,name,party_type").eq("tenant_id",tenantId).order("name").limit(1000)
  ]);
  if(c.error||p.error)setNotice(c.error?.message||p.error?.message||"Cheque register could not load.");
  else {setRows((c.data||[]) as Cheque[]);setParties((p.data||[]) as Party[]);}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 const partyName=(id:string|null)=>parties.find(p=>p.id===id)?.name||"—";
 const filtered=useMemo(()=>rows.filter(r=>(filter==="all"||r.status===filter)&&[r.cheque_number,r.bank_name,partyName(r.party_id),r.direction].some(v=>(v||"").toLowerCase().includes(search.toLowerCase()))),[rows,filter,search,parties]);
 async function save(e:FormEvent){
  e.preventDefault();if(!canCreate)return;setSaving(true);setNotice("");
  const value=Number(amount);
  if(!chequeNumber.trim()||!dueDate||!Number.isFinite(value)||value<=0){setNotice("Cheque number, due date aur valid positive amount zaroori hain.");setSaving(false);return;}
  const {data:user}=await db.auth.getUser();
  const {error}=await db.from("cheque_register").insert({tenant_id:tenantId,party_id:partyId||null,direction,cheque_number:chequeNumber.trim(),bank_name:bankName.trim()||null,cheque_date:chequeDate||null,due_date:dueDate,amount:value,status:direction,notes:notes.trim()||null,created_by:user.user?.id||null});
  if(error)setNotice(error.message);else{setNotice("Cheque register entry saved.");setChequeNumber("");setBankName("");setAmount("");setNotes("");await load();}
  setSaving(false);
 }
 async function updateStatus(id:string,status:string){if(!canUpdate)return;
  const patch:Record<string,string|null>={status,cleared_date:status==="cleared"?today():null};
  const {error}=await db.from("cheque_register").update(patch).eq("tenant_id",tenantId).eq("id",id);
  if(error)setNotice(error.message);else{setNotice("Cheque status updated.");await load();}
 }
 function exportCsv(){
  const data=filtered.map(r=>({direction:r.direction,cheque_number:r.cheque_number,party:partyName(r.party_id),bank:r.bank_name||"",cheque_date:r.cheque_date||"",due_date:r.due_date,amount:r.amount,status:r.status,cleared_date:r.cleared_date||"",notes:r.notes||""}));
  const keys=Object.keys(data[0]||{direction:"",cheque_number:"",party:"",bank:"",cheque_date:"",due_date:"",amount:"",status:"",cleared_date:"",notes:""});
  const csv=[keys.join(","),...data.map(row=>keys.map(k=>'"'+String(row[k as keyof typeof row]??"").replace(/"/g,'""')+'"').join(","))].join("\r\n");
  const blob=new Blob(["\uFEFF"+csv],{type:"text/csv;charset=utf-8"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download="ebs-pro-cheque-register.csv";a.click();URL.revokeObjectURL(url);
 }
 const outstanding=rows.filter(r=>!["cleared","bounced","cancelled"].includes(r.status)).reduce((s,r)=>s+Number(r.amount),0);
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Cheque Register</h2><p>Received and issued cheques, deposits, clearances, bounced instruments and due-date tracking.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  {canCreate&&<form className="transaction-form" onSubmit={save}><h3>Register a cheque</h3><div className="form-grid">
   <label>Direction<select value={direction} onChange={e=>setDirection(e.target.value as "received"|"issued")}><option value="received">Received from customer / other party</option><option value="issued">Issued to vendor / other party</option></select></label>
   <label>Party<select value={partyId} onChange={e=>setPartyId(e.target.value)}><option value="">Select party (optional)</option>{parties.filter(p=>direction==="received"?["customer","both"].includes(p.party_type):["supplier","both"].includes(p.party_type)).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
   <label>Cheque number<input required value={chequeNumber} onChange={e=>setChequeNumber(e.target.value)} /></label>
   <label>Bank name<input value={bankName} onChange={e=>setBankName(e.target.value)} /></label>
   <label>Cheque date<input type="date" value={chequeDate} onChange={e=>setChequeDate(e.target.value)} /></label>
   <label>Deposit / due date<input required type="date" value={dueDate} onChange={e=>setDueDate(e.target.value)} /></label>
   <label>Amount (PKR)<input required type="number" min="0.01" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)} /></label>
   <label>Notes<input value={notes} onChange={e=>setNotes(e.target.value)} /></label>
  </div><button disabled={saving}>{saving?"Saving…":"Save cheque record"}</button></form>
  <div className="stats report-stats"><article><small>Total cheques</small><strong>{rows.length}</strong></article><article><small>Received</small><strong>{money(rows.filter(r=>r.direction==="received"&&!["cleared","bounced","cancelled"].includes(r.status)).reduce((s,r)=>s+Number(r.amount),0))}</strong></article><article><small>Issued</small><strong>{money(rows.filter(r=>r.direction==="issued"&&!["cleared","bounced","cancelled"].includes(r.status)).reduce((s,r)=>s+Number(r.amount),0))}</strong></article><article><small>Open cheque value</small><strong>{money(outstanding)}</strong></article></div>
  <div className="table-tools"><input aria-label="Search cheques" placeholder="Search cheque, bank or party…" value={search} onChange={e=>setSearch(e.target.value)}/><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All statuses</option>{["received","issued","deposited","cleared","bounced","cancelled"].map(s=><option key={s} value={s}>{s}</option>)}</select><button onClick={exportCsv}>Export Excel (CSV)</button><button onClick={()=>window.print()}>Print / PDF</button><span>{filtered.length} records</span></div>
  {loading?<div className="table-empty">Loading cheque register…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Direction</th><th>Cheque #</th><th>Party</th><th>Bank</th><th>Cheque date</th><th>Due date</th><th>Amount</th><th>Status</th><th>Cleared</th><th>Update status</th></tr></thead><tbody>
   {filtered.map(r=><tr key={r.id}><td>{r.direction}</td><td>{r.cheque_number}</td><td>{partyName(r.party_id)}</td><td>{r.bank_name||"—"}</td><td>{r.cheque_date||"—"}</td><td>{r.due_date}</td><td>{money(r.amount)}</td><td>{r.status}</td><td>{r.cleared_date||"—"}</td><td>{!["cleared","bounced","cancelled"].includes(r.status)?<select aria-label={"Update "+r.cheque_number} value={r.status} onChange={e=>void updateStatus(r.id,e.target.value)}>{["received","issued","deposited","cleared","bounced","cancelled"].map(s=><option key={s} value={s}>{s}</option>)}</select>:"Final"}</td></tr>)}
   {!filtered.length&&<tr><td colSpan={10} className="table-empty">No cheque records found.</td></tr>}
  </tbody></table></div>}
  <p className="module-footnote">This register tracks cheque lifecycle and status only. It does not itself post or reverse accounting entries; settlement must be recorded through the payment / journal workflow to avoid duplicate ledger postings.</p>
 </section>;
}
