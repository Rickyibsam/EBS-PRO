import {fetchAllRowsResult} from "./lib/fetchAllRows";
import {FormEvent,useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {useModuleAction} from "./lib/modulePermissionContext";
type Row=Record<string,any>;
export default function PayrollModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [employees,setEmployees]=useState<Row[]>([]),[runs,setRuns]=useState<Row[]>([]),[lines,setLines]=useState<Row[]>([]);
 const [selected,setSelected]=useState(""),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState("");
 const [periodStart,setPeriodStart]=useState(new Date(new Date().getFullYear(),new Date().getMonth(),1).toISOString().slice(0,10));
 const [periodEnd,setPeriodEnd]=useState(new Date(new Date().getFullYear(),new Date().getMonth()+1,0).toISOString().slice(0,10));
 const [payDate,setPayDate]=useState(new Date().toISOString().slice(0,10));
 const roleCanManage=["owner","admin","manager","accounts"].includes(currentRole);
 const canCreate=useModuleAction("hr_payroll","create",roleCanManage);
 const canUpdate=useModuleAction("hr_payroll","update",roleCanManage);
 const canManage=canCreate||canUpdate;
 const canEditSalary=useModuleAction("hr_payroll","update",["owner","admin","manager"].includes(currentRole));
 const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{minimumFractionDigits:2,maximumFractionDigits:2});
 async function load(){
  setLoading(true);setNotice("");
  const [e,r]=await Promise.all([
   db.from("employees").select("id,employee_code,full_name,job_title,employment_status,basic_salary,joining_date,bank_name,bank_account_no").eq("tenant_id",tenantId).order("full_name"),
   fetchAllRowsResult<any>((from,to)=>db.from("payroll_runs").select("id,run_number,period_start,period_end,pay_date,status,gross_total,deductions_total,net_total,created_at").eq("tenant_id",tenantId).order("period_start",{ascending:false}).order("id",{ascending:true}).range(from,to))]);
  if(e.error||r.error)setNotice(e.error?.message||r.error?.message||"Payroll records could not be loaded.");
  else{setEmployees(e.data??[]);setRuns(r.data??[]);if(!selected&&r.data?.[0])setSelected(r.data[0].id);}
  setLoading(false);
 }
 async function loadLines(id:string){
  if(!id){setLines([]);return;}
  const {data,error}=await db.from("payroll_lines").select("id,employee_id,basic_salary,allowances,overtime,sales_incentive,deductions,net_salary,payment_status,payment_method,payment_reference,paid_at").eq("tenant_id",tenantId).eq("payroll_run_id",id).order("created_at");
  if(error){setNotice(error.message);return;}
  setLines((data??[]).map(x=>({...x,employee:employees.find(e=>e.id===x.employee_id)?.full_name||x.employee_id})));
 }
 useEffect(()=>{void load();},[tenantId]);
 useEffect(()=>{void loadLines(selected);},[selected,employees.length]);
 async function updateSalary(id:string,value:string){
  const amount=Number(value);if(!canEditSalary){setNotice("Only an owner, admin or manager can change employee salary master.");return;}if(!Number.isFinite(amount)||amount<0){setNotice("Salary must be a valid non-negative amount.");return;}
  const {error}=await db.from("employees").update({basic_salary:amount}).eq("tenant_id",tenantId).eq("id",id);
  if(error)setNotice(error.message);else{setEmployees(old=>old.map(x=>x.id===id?{...x,basic_salary:amount}:x));setNotice("Employee salary master updated.");}
 }
 async function createRun(e:FormEvent){
  e.preventDefault();if(!canCreate)return;setSaving(true);setNotice("");
  try{
   if(!periodStart||!periodEnd||periodEnd<periodStart)throw new Error("Enter a valid payroll period.");
   const staff=employees.filter(x=>x.employment_status==="active"&&Number(x.basic_salary)>0);
   if(!staff.length)throw new Error("Set basic salary for at least one active employee before generating payroll.");
   const {data:runNo,error:numberError}=await db.rpc("next_document_number",{p_tenant_id:tenantId,p_document_type:"payroll_run"});
   if(numberError)throw numberError;
   if(typeof runNo!=="string"||!runNo)throw new Error("Payroll run number could not be generated.");
   const {data:auth}=await db.auth.getUser();
   const {data:head,error}=await db.from("payroll_runs").insert({tenant_id:tenantId,run_number:runNo,period_start:periodStart,period_end:periodEnd,pay_date:payDate,status:"draft",created_by:auth.user?.id??null}).select("id").single();
   if(error)throw error;
   const payload=staff.map(x=>({tenant_id:tenantId,payroll_run_id:head.id,employee_id:x.id,basic_salary:Number(x.basic_salary),allowances:0,overtime:0,sales_incentive:0,deductions:0,net_salary:Number(x.basic_salary)}));
   const {error:lineError}=await db.from("payroll_lines").insert(payload);
   if(lineError){await db.from("payroll_runs").delete().eq("id",head.id).eq("tenant_id",tenantId).eq("status","draft");throw new Error("Payroll lines could not be generated: "+lineError.message);}
   setSelected(head.id);setNotice("Draft payroll generated for "+staff.length+" active employees.");await load();
  }catch(err){setNotice(err instanceof Error?err.message:"Payroll run could not be created.");}
  finally{setSaving(false);}
 }
 async function updateLine(line:Row,field:"allowances"|"overtime"|"sales_incentive"|"deductions",value:string){
  if(!canUpdate||activeRun?.status!=="draft")return;
  const amount=Number(value);if(!Number.isFinite(amount)||amount<0){setNotice("Payroll adjustment must be non-negative.");return;}
  const patch={ [field]:amount, net_salary:Number(line.basic_salary)+(field==="allowances"?amount:Number(line.allowances))+(field==="overtime"?amount:Number(line.overtime))+(field==="sales_incentive"?amount:Number(line.sales_incentive||0))-(field==="deductions"?amount:Number(line.deductions))};
  if(patch.net_salary<0){setNotice("Deductions cannot exceed gross salary.");return;}
  const {error}=await db.from("payroll_lines").update(patch).eq("tenant_id",tenantId).eq("id",line.id);
  if(error)setNotice(error.message);else{setLines(old=>old.map(x=>x.id===line.id?{...x,...patch}:x));setNotice("Payroll line updated.");}
 }
 async function postRun(){
  if(!canUpdate||!selected)return;setSaving(true);setNotice("");
  try{
   // Apply eligible customer-return commission clawbacks before the payroll journal is posted.
   // The database function is idempotent per target/payroll run and locks the draft run.
   const {data:adjustment,error:adjustmentError}=await db.rpc("apply_commission_return_adjustments",{p_payroll_run_id:selected});
   if(adjustmentError)throw adjustmentError;
   if(adjustment?.success!==true)throw new Error("Commission return adjustments were not confirmed.");
   const {data,error}=await db.rpc("post_payroll_run",{p_payroll_run_id:selected});
   if(error)throw error;
   if(data?.success!==true)throw new Error("Payroll posting was not confirmed.");
   setNotice("Payroll posted to the general ledger. Commission return deductions applied: "+money(Number(adjustment.applied_amount||0))+".");
   await load();await loadLines(selected);
  }catch(err){setNotice(err instanceof Error?err.message:"Payroll posting failed. Draft payroll remains available for review.");}
  finally{setSaving(false);}
 }
 async function payLine(line:Row){
  if(!canUpdate||activeRun?.status!=="posted"||line.payment_status!=="unpaid")return;
  const method=window.prompt("Payment method: cash, bank, cheque or online","bank");if(!method)return;
  const reference=window.prompt("Payment reference (optional)","")||null;setSaving(true);setNotice("");
  try{const {data,error}=await db.rpc("pay_payroll_line",{p_payroll_line_id:line.id,p_method:method.trim().toLowerCase(),p_reference:reference});if(error)throw error;if(data?.success!==true)throw new Error("Salary payment was not confirmed.");setNotice("Salary payment posted to cash/bank and payroll payable.");await loadLines(selected);}
  catch(err){setNotice(err instanceof Error?err.message:"Salary payment failed.");}finally{setSaving(false);}
 }
 function exportPayroll(){const data=lines.map(x=>({employee:x.employee,basic:x.basic_salary,allowances:x.allowances,overtime:x.overtime,incentive:x.sales_incentive||0,deductions:x.deductions,net:x.net_salary,payment:x.payment_status}));const keys=Object.keys(data[0]||{employee:"",basic:"",allowances:"",overtime:"",incentive:"",deductions:"",net:"",payment:""});const csv=[keys.join(","),...data.map(x=>keys.map(k=>'"'+String(x[k as keyof typeof x]??"").replace(/"/g,'""')+'"').join(","))].join("\\r\\n");const url=URL.createObjectURL(new Blob(["\\uFEFF"+csv],{type:"text/csv;charset=utf-8"}));const a=document.createElement("a");a.href=url;a.download="payroll-"+(runs.find(r=>r.id===selected)?.run_number||"register")+".csv";a.click();URL.revokeObjectURL(url);}
 const activeRun=runs.find(x=>x.id===selected);
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>HR & Payroll</h2><p>Employee salary master, monthly payroll drafts, ledger posting and salary disbursement.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  <h3>Employee salary master</h3>
  <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Employee</th><th>Code</th><th>Designation</th><th>Employment</th><th>Basic salary (PKR / month)</th><th>Joining date</th></tr></thead><tbody>{employees.map(x=><tr key={x.id}><td>{x.full_name}</td><td>{x.employee_code}</td><td>{x.job_title||"—"}</td><td>{x.employment_status}</td><td><input type="number" min="0" step="0.01" disabled={!canEditSalary} value={x.basic_salary??0} onChange={e=>setEmployees(old=>old.map(y=>y.id===x.id?{...y,basic_salary:e.target.value}:y))} onBlur={e=>void updateSalary(x.id,e.target.value)}/></td><td>{x.joining_date||"—"}</td></tr>)}{!employees.length&&<tr><td colSpan={6} className="table-empty">No employee records found.</td></tr>}</tbody></table></div>
  {canCreate&&<form className="transaction-form" onSubmit={createRun}><h3>Generate monthly payroll draft</h3><div className="form-grid"><label>Period start<input type="date" required value={periodStart} onChange={e=>setPeriodStart(e.target.value)}/></label><label>Period end<input type="date" required value={periodEnd} onChange={e=>setPeriodEnd(e.target.value)}/></label><label>Pay date<input type="date" required value={payDate} onChange={e=>setPayDate(e.target.value)}/></label></div><button disabled={saving}>{saving?"Generating…":"Generate draft payroll"}</button></form>}
  <h3>Payroll runs</h3>
  <div className="table-tools"><select value={selected} onChange={e=>setSelected(e.target.value)}><option value="">Select payroll run</option>{runs.map(x=><option key={x.id} value={x.id}>{x.run_number} · {x.period_start} to {x.period_end} · {x.status}</option>)}</select><span>{runs.length} runs</span><button onClick={exportPayroll}>Export Excel (CSV)</button><button onClick={()=>window.print()}>Print / PDF</button></div>
  {activeRun&&<><div className="stats report-stats"><article><small>Gross salary</small><strong>{money(activeRun.gross_total)}</strong></article><article><small>Deductions</small><strong>{money(activeRun.deductions_total)}</strong></article><article><small>Net payroll</small><strong>{money(activeRun.net_total)}</strong></article><article><small>Status</small><strong>{activeRun.status}</strong></article></div>
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Employee</th><th>Basic</th><th>Allowances</th><th>Overtime</th><th>Sales / Delivery Incentive</th><th>Deductions</th><th>Net</th><th>Payment</th><th>Action</th></tr></thead><tbody>{lines.map(x=><tr key={x.id}><td>{x.employee}</td><td>{money(x.basic_salary)}</td><td><input type="number" min="0" step="0.01" disabled={!canUpdate||activeRun.status!=="draft"} value={x.allowances} onBlur={e=>void updateLine(x,"allowances",e.target.value)}/></td><td><input type="number" min="0" step="0.01" disabled={!canUpdate||activeRun.status!=="draft"} value={x.overtime} onBlur={e=>void updateLine(x,"overtime",e.target.value)}/></td><td><input type="number" min="0" step="0.01" disabled={!canUpdate||activeRun.status!=="draft"} value={x.sales_incentive??0} onBlur={e=>void updateLine(x,"sales_incentive",e.target.value)}/></td><td><input type="number" min="0" step="0.01" disabled={!canUpdate||activeRun.status!=="draft"} value={x.deductions} onBlur={e=>void updateLine(x,"deductions",e.target.value)}/></td><td>{money(x.net_salary)}</td><td>{x.payment_status}</td><td>{activeRun.status==="posted"&&x.payment_status==="unpaid"&&canUpdate?<button disabled={saving} onClick={()=>void payLine(x)}>Pay salary</button>:x.payment_status==="paid"?"Paid":"—"}</td></tr>)}{!lines.length&&<tr><td colSpan={9} className="table-empty">No payroll lines found.</td></tr>}</tbody></table></div>
   {activeRun.status==="draft"&&canUpdate&&<button disabled={saving||!lines.length} onClick={()=>void postRun()}>Post payroll to accounts</button>}
  </>}
 </section>;
}
