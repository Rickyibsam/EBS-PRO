import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {useModuleAction} from "./lib/modulePermissionContext";
type Party={id:string;party_code:string;name:string;phone:string|null;credit_limit:number;opening_balance:number;payment_terms_days:number};
type Invoice={id:string;customer_id:string;invoice_number:string;invoice_date:string;due_date:string|null;grand_total:number};
type Balance={customer:Party;current:number;d1_30:number;d31_60:number;d61_90:number;over90:number;opening:number;total:number};
const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
const today=new Date();const day=(s:string)=>Math.floor((today.getTime()-new Date(s+"T00:00:00").getTime())/86400000);
export default function CustomerCreditControlModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [parties,setParties]=useState<Party[]>([]),[invoices,setInvoices]=useState<Invoice[]>([]),[payments,setPayments]=useState<Array<{sales_invoice_id:string;amount:number;payment_type:string}>>([]),[credits,setCredits]=useState<Array<{sales_invoice_id:string;grand_total:number}>>([]);
 const [loading,setLoading]=useState(true),[notice,setNotice]=useState(""),[search,setSearch]=useState(""),[filter,setFilter]=useState("all"),[savingId,setSavingId]=useState(""),[limits,setLimits]=useState<Record<string,string>>({});
 async function load(){
  setLoading(true);setNotice("");
  const [p,i,pa,c]=await Promise.all([
   db.from("parties").select("id,party_code,name,phone,credit_limit,opening_balance,payment_terms_days").eq("tenant_id",tenantId).in("party_type",["customer","both"]).order("name").limit(5000),
   db.from("sales_invoices").select("id,customer_id,invoice_number,invoice_date,due_date,grand_total").eq("tenant_id",tenantId).eq("status","posted").order("invoice_date",{ascending:false}).limit(10000),
   db.from("payments").select("sales_invoice_id,amount,payment_type").eq("tenant_id",tenantId).not("sales_invoice_id","is",null),
   db.from("sales_credit_notes").select("sales_invoice_id,grand_total").eq("tenant_id",tenantId).eq("status","posted")
  ]);
  const err=p.error||i.error||pa.error||c.error;
  if(err)setNotice(err.message);else{setParties((p.data||[]) as Party[]);setInvoices((i.data||[]) as Invoice[]);setPayments((pa.data||[]) as typeof payments);setCredits((c.data||[]) as typeof credits);setLimits(Object.fromEntries((p.data||[]).map(x=>[x.id,String(x.credit_limit||0)])));}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 const balances=useMemo<Balance[]>(()=>{
  const paid:Record<string,number>={},credited:Record<string,number>={};
  payments.filter(x=>x.payment_type==="receipt").forEach(x=>{paid[x.sales_invoice_id]=(paid[x.sales_invoice_id]||0)+Number(x.amount||0);});
  credits.forEach(x=>{credited[x.sales_invoice_id]=(credited[x.sales_invoice_id]||0)+Number(x.grand_total||0);});
  return parties.map(customer=>{
   const b={current:0,d1_30:0,d31_60:0,d61_90:0,over90:0};
   invoices.filter(x=>x.customer_id===customer.id).forEach(inv=>{
    const outstanding=Math.max(0,Number(inv.grand_total||0)-(paid[inv.id]||0)-(credited[inv.id]||0));
    const age=day(inv.due_date||inv.invoice_date);
    if(age<=0)b.current+=outstanding;else if(age<=30)b.d1_30+=outstanding;else if(age<=60)b.d31_60+=outstanding;else if(age<=90)b.d61_90+=outstanding;else b.over90+=outstanding;
   });
   const opening=Number(customer.opening_balance||0);const total=opening+b.current+b.d1_30+b.d31_60+b.d61_90+b.over90;
   return {customer,...b,opening,total};
  });
 },[parties,invoices,payments,credits]);
 const filtered=balances.filter(x=>(filter==="all"||(filter==="overlimit"&&x.customer.credit_limit>0&&x.total>x.customer.credit_limit)||(filter==="overdue"&&x.d1_30+x.d31_60+x.d61_90+x.over90>0))&&[x.customer.name,x.customer.party_code,x.customer.phone||""].some(v=>v.toLowerCase().includes(search.toLowerCase())));
 const totalExposure=balances.reduce((s,x)=>s+x.total,0),overdue=balances.reduce((s,x)=>s+x.d1_30+x.d31_60+x.d61_90+x.over90,0),overLimit=balances.filter(x=>x.customer.credit_limit>0&&x.total>x.customer.credit_limit).length;
 async function saveLimit(p:Party){
  if(!canEdit)return;
  const value=Number(limits[p.id]);if(!Number.isFinite(value)||value<0){setNotice("Credit limit must be a valid non-negative amount.");return;}
  setSavingId(p.id);setNotice("");const {error}=await db.from("parties").update({credit_limit:value}).eq("tenant_id",tenantId).eq("id",p.id);
  if(error)setNotice(error.message);else{setNotice("Credit limit updated for "+p.name+".");await load();}setSavingId("");
 }
 function exportCsv(){const rows=filtered.map(x=>({customer:x.customer.name,code:x.customer.party_code,credit_limit:x.customer.credit_limit,opening_balance:x.opening,current:x.current,days_1_30:x.d1_30,days_31_60:x.d31_60,days_61_90:x.d61_90,over_90:x.over90,total_outstanding:x.total,available_credit:x.customer.credit_limit>0?x.customer.credit_limit-x.total:""}));const keys=Object.keys(rows[0]||{customer:"",code:"",credit_limit:"",opening_balance:"",current:"",days_1_30:"",days_31_60:"",days_61_90:"",over_90:"",total_outstanding:"",available_credit:""});const csv=[keys.join(","),...rows.map(r=>keys.map(k=>'"'+String(r[k as keyof typeof r]??"").replace(/"/g,'""')+'"').join(","))].join("\r\n");const blob=new Blob(["\uFEFF"+csv],{type:"text/csv;charset=utf-8"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download="ebs-pro-customer-credit-ageing.csv";a.click();URL.revokeObjectURL(url);}
 const canEdit=useModuleAction("sales_customer","update",["owner","admin","manager","accounts","sales"].includes(currentRole));
 return <section className="module-page"><div className="module-toolbar"><div><h2>Customer Credit Control</h2><p>Credit limits, invoice outstanding, overdue ageing and customer exposure. Posted invoices, receipts and posted credit notes only.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
 {notice&&<div className="notice">{notice}</div>}
 <div className="stats report-stats"><article><small>Total receivables</small><strong>{money(totalExposure)}</strong></article><article><small>Overdue receivables</small><strong>{money(overdue)}</strong></article><article><small>Customers over limit</small><strong>{overLimit}</strong></article><article><small>Customer accounts</small><strong>{parties.length}</strong></article></div>
 <div className="table-tools"><input placeholder="Search customer, code or phone…" value={search} onChange={e=>setSearch(e.target.value)}/><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All customers</option><option value="overdue">Overdue only</option><option value="overlimit">Over credit limit</option></select><button onClick={exportCsv}>Export Excel (CSV)</button><button onClick={()=>window.print()}>Print / PDF</button></div>
 {loading?<div className="table-empty">Calculating customer balances and ageing…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Customer</th><th>Credit limit</th><th>Opening</th><th>Not due</th><th>1–30 days</th><th>31–60 days</th><th>61–90 days</th><th>90+ days</th><th>Total due</th><th>Available / Excess</th>{canEdit&&<th>Save limit</th>}</tr></thead><tbody>
 {filtered.map(x=>{const excess=x.customer.credit_limit>0&&x.total>x.customer.credit_limit;return <tr key={x.customer.id}><td>{x.customer.name}<small>{x.customer.party_code} · {x.customer.phone||""}</small></td><td>{canEdit?<input aria-label={"Credit limit "+x.customer.name} type="number" min="0" step="0.01" value={limits[x.customer.id]??"0"} onChange={e=>setLimits(v=>({...v,[x.customer.id]:e.target.value}))}/>:money(x.customer.credit_limit)}</td><td>{money(x.opening)}</td><td>{money(x.current)}</td><td>{money(x.d1_30)}</td><td>{money(x.d31_60)}</td><td>{money(x.d61_90)}</td><td>{money(x.over90)}</td><td><strong>{money(x.total)}</strong></td><td>{x.customer.credit_limit>0?(excess?"Excess "+money(x.total-x.customer.credit_limit):money(x.customer.credit_limit-x.total)):"No limit set"}</td>{canEdit&&<td><button disabled={savingId===x.customer.id} onClick={()=>void saveLimit(x.customer)}>{savingId===x.customer.id?"Saving…":"Save"}</button></td>}</tr>;})}
 {!filtered.length&&<tr><td colSpan={canEdit?11:10} className="table-empty">No matching customer balances.</td></tr>}
 </tbody></table></div>}
 <p className="module-footnote">Ageing uses invoice due date; if no due date exists, invoice date is used. Opening balances are shown separately and included in total exposure, but cannot be age-bucketed without an opening-balance date. A zero credit limit means no limit configured. This screen reports exposure; it does not automatically block order approval.</p>
 </section>;
}
