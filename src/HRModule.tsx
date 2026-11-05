import {useEffect,useMemo,useState,type FormEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Row=Record<string,any>;
const localDate=()=>{const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,"0"),String(d.getDate()).padStart(2,"0")].join("-");};
const money=(n:number)=>"PKR "+Number(n||0).toLocaleString("en-PK",{maximumFractionDigits:2});
export default function HRModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const canManage=["owner","admin","manager"].includes(currentRole);
 const [employees,setEmployees]=useState<Row[]>([]),[attendance,setAttendance]=useState<Row[]>([]),[leaves,setLeaves]=useState<Row[]>([]),[advances,setAdvances]=useState<Row[]>([]),[repaymentHistory,setRepaymentHistory]=useState<Row[]>([]),[departments,setDepartments]=useState<Row[]>([]),[designations,setDesignations]=useState<Row[]>([]),[accounts,setAccounts]=useState<Row[]>([]),[cashAccounts,setCashAccounts]=useState<string[]>([]);
 const [employeeId,setEmployeeId]=useState(""),[attendanceDate,setAttendanceDate]=useState(localDate()),[attendanceStatus,setAttendanceStatus]=useState("present"),[checkIn,setCheckIn]=useState(""),[checkOut,setCheckOut]=useState(""),[attendanceNotes,setAttendanceNotes]=useState("");
 const [leaveType,setLeaveType]=useState("Annual"),[leaveStart,setLeaveStart]=useState(localDate()),[leaveEnd,setLeaveEnd]=useState(localDate()),[leaveReason,setLeaveReason]=useState("");
 const [departmentCode,setDepartmentCode]=useState(""),[departmentName,setDepartmentName]=useState(""),[designationCode,setDesignationCode]=useState(""),[designationName,setDesignationName]=useState(""),[designationDepartment,setDesignationDepartment]=useState("");
 const [advanceAmount,setAdvanceAmount]=useState(""),[advanceDate,setAdvanceDate]=useState(localDate()),[advanceNotes,setAdvanceNotes]=useState(""),[repayments,setRepayments]=useState<Record<string,string>>({}),[repaymentMethods,setRepaymentMethods]=useState<Record<string,string>>({});
 const [advanceMapping,setAdvanceMapping]=useState({receivable_account_id:"",cash_account_id:"",bank_account_id:""});
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[notice,setNotice]=useState(""),[tab,setTab]=useState("attendance");
 const [currentUserId,setCurrentUserId]=useState("");
 const ownEmployee=employees.find(x=>x.user_id===currentUserId);
 const activeEmployeeId=canManage?employeeId:(ownEmployee?.id||"");
 const dayCount=useMemo(()=>{if(!leaveStart||!leaveEnd||leaveEnd<leaveStart)return 0;return Math.round((new Date(leaveEnd+"T00:00:00").getTime()-new Date(leaveStart+"T00:00:00").getTime())/86400000)+1;},[leaveStart,leaveEnd]);
 async function load(){
  setLoading(true);setNotice("");
  const {data:{session}}=await db.auth.getSession();setCurrentUserId(session?.user.id||"");
  const [e,a,l,v,d,g,rp,ac,cm]=await Promise.all([
   db.from("employees").select("id,user_id,employee_code,full_name,job_title,department_id,designation_id,employment_status").eq("tenant_id",tenantId).eq("employment_status","active").order("full_name"),
   db.from("employee_attendance").select("*").eq("tenant_id",tenantId).order("attendance_date",{ascending:false}).limit(200),
   db.from("employee_leaves").select("*").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(100),
   db.from("employee_advances").select("*").eq("tenant_id",tenantId).order("issue_date",{ascending:false}).limit(100),
   db.from("departments").select("*").eq("tenant_id",tenantId).order("name"),
   db.from("designations").select("*").eq("tenant_id",tenantId).order("name"),
   db.from("employee_advance_repayments").select("*").eq("tenant_id",tenantId).order("repayment_date",{ascending:false}).limit(200),
   db.from("chart_of_accounts").select("id,account_code,account_name,account_type").eq("tenant_id",tenantId).eq("is_active",true).order("account_code"),
   db.from("cash_flow_account_mappings").select("account_id").eq("tenant_id",tenantId).eq("classification","cash_bank")
  ]);
  const err=[e,a,l,v,d,g,rp,ac,cm].find(x=>x.error);if(err)setNotice(err.error?.message||"HR records could not be loaded.");else{setEmployees(e.data||[]);setAttendance(a.data||[]);setLeaves(l.data||[]);setAdvances(v.data||[]);setDepartments(d.data||[]);setDesignations(g.data||[]);setRepaymentHistory(rp.data||[]);setAccounts(ac.data||[]);setCashAccounts((cm.data||[]).map(x=>x.account_id));if(!employeeId&&e.data?.length)setEmployeeId(e.data[0].id);const m=await db.from("employee_advance_account_mappings").select("*").eq("tenant_id",tenantId).maybeSingle();if(!m.error&&m.data)setAdvanceMapping({receivable_account_id:m.data.receivable_account_id,cash_account_id:m.data.cash_account_id,bank_account_id:m.data.bank_account_id});}
  setLoading(false);
 }
 useEffect(()=>{void load();},[tenantId]);
 async function saveAttendance(e:FormEvent){
  e.preventDefault();if(!activeEmployeeId)return;setSaving(true);setNotice("");
  try{
   const checkin=checkIn?new Date(attendanceDate+"T"+checkIn+":00+05:00").toISOString():null,checkout=checkOut?new Date(attendanceDate+"T"+checkOut+":00+05:00").toISOString():null;
   const {error}=await db.rpc("record_employee_attendance",{p_tenant_id:tenantId,p_employee_id:activeEmployeeId,p_attendance_date:attendanceDate,p_status:attendanceStatus,p_check_in:checkin,p_check_out:checkout,p_notes:attendanceNotes.trim()||null});
   if(error)throw error;setNotice("Attendance saved.");setAttendanceNotes("");await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Attendance could not be saved.");}finally{setSaving(false);}
 }
 async function requestLeave(e:React.FormEvent){
  e.preventDefault();if(!activeEmployeeId||dayCount<=0)return;setSaving(true);setNotice("");
  try{
   const {data:{session}}=await db.auth.getSession();
   const {error}=await db.from("employee_leaves").insert({tenant_id:tenantId,employee_id:activeEmployeeId,leave_type:leaveType,start_date:leaveStart,end_date:leaveEnd,total_days:dayCount,status:"pending",reason:leaveReason.trim()||null,created_by:session?.user.id||null});
   if(error)throw error;setNotice("Leave request submitted for approval.");setLeaveReason("");await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Leave request could not be submitted.");}finally{setSaving(false);}
 }
 async function decideLeave(id:string,decision:"approved"|"rejected"){
  setSaving(true);const {error}=await db.rpc("decide_employee_leave",{p_leave_id:id,p_decision:decision});if(error)setNotice(error.message);else{setNotice("Leave request "+decision+".");await load();}setSaving(false);
 }
 async function addDepartment(e:React.FormEvent){
  e.preventDefault();setSaving(true);const {error}=await db.from("departments").insert({tenant_id:tenantId,code:departmentCode.trim(),name:departmentName.trim()});if(error)setNotice(error.message);else{setDepartmentCode("");setDepartmentName("");setNotice("Department added.");await load();}setSaving(false);
 }
 async function addDesignation(e:React.FormEvent){
  e.preventDefault();setSaving(true);const {error}=await db.from("designations").insert({tenant_id:tenantId,department_id:designationDepartment||null,code:designationCode.trim(),name:designationName.trim()});if(error)setNotice(error.message);else{setDesignationCode("");setDesignationName("");setNotice("Designation added.");await load();}setSaving(false);
 }
 async function updateEmployee(id:string,patch:Row){
  setSaving(true);const {error}=await db.from("employees").update(patch).eq("tenant_id",tenantId).eq("id",id);if(error)setNotice(error.message);else{setNotice("Employee profile updated.");await load();}setSaving(false);
 }
 async function issueAdvance(e:React.FormEvent){
  e.preventDefault();if(!employeeId)return;setSaving(true);const {data,error}=await db.rpc("create_employee_advance",{p_tenant_id:tenantId,p_employee_id:employeeId,p_amount:Number(advanceAmount),p_issue_date:advanceDate,p_notes:advanceNotes.trim()||null});if(error)setNotice(error.message);else{setAdvanceAmount("");setAdvanceNotes("");setNotice("Employee advance created: "+data);await load();}setSaving(false);
 }
 async function repayAdvance(id:string){
  const amount=Number(repayments[id]||0);if(!amount)return;setSaving(true);const {error}=await db.rpc("record_employee_advance_repayment",{p_advance_id:id,p_amount:amount,p_repayment_date:localDate(),p_payment_method:"cash",p_reference:null,p_notes:null});if(error)setNotice(error.message);else{setRepayments(x=>({...x,[id]:""}));setNotice("Advance repayment recorded and outstanding balance updated.");await load();}setSaving(false);
 }
 const employeeName=(id:string)=>employees.find(x=>x.id===id)?.full_name||id;
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>HR & Workforce</h2><p>Employee attendance, leave approvals, department structure, advances and repayment tracking.</p></div><button onClick={()=>void load()}>↻ Refresh</button></div>
  {notice&&<div className="notice">{notice}</div>}
  <div className="module-tabs">{["attendance","leave","advances",...(canManage?["organization"] : [])].map(x=><button className={tab===x?"active":""} onClick={()=>setTab(x)} key={x}>{x==="organization"?"Departments & Designations":x==="attendance"?"Attendance":x==="leave"?"Leave": "Employee Advances"}</button>)}</div>
  {loading?<div className="table-empty">Loading HR records…</div>:tab==="attendance"?<>
   <form className="transaction-form" onSubmit={saveAttendance}><h3>Record daily attendance</h3><div className="form-grid">{canManage&&<label>Employee<select required value={employeeId} onChange={e=>setEmployeeId(e.target.value)}>{employees.map(x=><option key={x.id} value={x.id}>{x.employee_code} · {x.full_name}</option>)}</select></label>}<label>Date<input type="date" required value={attendanceDate} onChange={e=>setAttendanceDate(e.target.value)}/></label><label>Status<select value={attendanceStatus} onChange={e=>setAttendanceStatus(e.target.value)}><option value="present">Present</option><option value="late">Late</option><option value="half_day">Half day</option><option value="absent">Absent</option><option value="leave">Leave</option><option value="holiday">Holiday</option></select></label><label>Check in<input type="time" value={checkIn} onChange={e=>setCheckIn(e.target.value)}/></label><label>Check out<input type="time" value={checkOut} onChange={e=>setCheckOut(e.target.value)}/></label><label>Notes<input value={attendanceNotes} onChange={e=>setAttendanceNotes(e.target.value)}/></label></div><button className="primary-action" disabled={saving||!activeEmployeeId}>{saving?"Saving…":"Save attendance"}</button></form>
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Employee</th><th>Status</th><th>Check in</th><th>Check out</th><th>Notes</th></tr></thead><tbody>{attendance.filter(x=>canManage||x.employee_id===ownEmployee?.id).map(x=><tr key={x.id}><td>{x.attendance_date}</td><td>{employeeName(x.employee_id)}</td><td>{x.status}</td><td>{x.check_in?new Date(x.check_in).toLocaleTimeString("en-PK",{hour:"2-digit",minute:"2-digit"}):"—"}</td><td>{x.check_out?new Date(x.check_out).toLocaleTimeString("en-PK",{hour:"2-digit",minute:"2-digit"}):"—"}</td><td>{x.notes||"—"}</td></tr>)}{!attendance.length&&<tr><td colSpan={6} className="table-empty">No attendance records found.</td></tr>}</tbody></table></div>
  </>:tab==="leave"?<>
   <form className="transaction-form" onSubmit={requestLeave}><h3>Submit leave request</h3><div className="form-grid">{canManage&&<label>Employee<select required value={employeeId} onChange={e=>setEmployeeId(e.target.value)}>{employees.map(x=><option key={x.id} value={x.id}>{x.employee_code} · {x.full_name}</option>)}</select></label>}<label>Leave type<select value={leaveType} onChange={e=>setLeaveType(e.target.value)}><option>Annual</option><option>Sick</option><option>Casual</option><option>Unpaid</option><option>Other</option></select></label><label>Start date<input type="date" value={leaveStart} onChange={e=>setLeaveStart(e.target.value)}/></label><label>End date<input type="date" value={leaveEnd} onChange={e=>setLeaveEnd(e.target.value)}/></label><label>Days<input readOnly value={dayCount}/></label><label>Reason<input value={leaveReason} onChange={e=>setLeaveReason(e.target.value)} placeholder="Reason for leave"/></label></div><button className="primary-action" disabled={saving||!activeEmployeeId||dayCount<=0}>Submit leave request</button></form>
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Employee</th><th>Type</th><th>Period</th><th>Days</th><th>Status</th><th>Reason</th>{canManage&&<th>Decision</th>}</tr></thead><tbody>{leaves.filter(x=>canManage||x.employee_id===ownEmployee?.id).map(x=><tr key={x.id}><td>{employeeName(x.employee_id)}</td><td>{x.leave_type}</td><td>{x.start_date} → {x.end_date}</td><td>{x.total_days}</td><td>{x.status}</td><td>{x.reason||"—"}</td>{canManage&&<td>{x.status==="pending"?<><button disabled={saving} onClick={()=>void decideLeave(x.id,"approved")}>Approve</button> <button disabled={saving} onClick={()=>void decideLeave(x.id,"rejected")}>Reject</button></>:"—"}</td>}</tr>)}{!leaves.length&&<tr><td colSpan={canManage?7:6} className="table-empty">No leave requests found.</td></tr>}</tbody></table></div>
  </>:tab==="advances"?<>
   {canManage&&<form className="transaction-form" onSubmit={issueAdvance}><h3>Issue employee advance</h3><div className="form-grid"><label>Employee<select required value={employeeId} onChange={e=>setEmployeeId(e.target.value)}>{employees.map(x=><option key={x.id} value={x.id}>{x.employee_code} · {x.full_name}</option>)}</select></label><label>Amount (PKR)<input type="number" min="0.01" step="0.01" required value={advanceAmount} onChange={e=>setAdvanceAmount(e.target.value)}/></label><label>Issue date<input type="date" value={advanceDate} onChange={e=>setAdvanceDate(e.target.value)}/></label><label>Notes<input value={advanceNotes} onChange={e=>setAdvanceNotes(e.target.value)}/></label></div><button className="primary-action" disabled={saving}>Create advance</button></form>}
   <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Advance no.</th><th>Employee</th><th>Issue date</th><th>Amount</th><th>Balance</th><th>Status</th>{canManage&&<th>Repayment</th>}</tr></thead><tbody>{advances.filter(x=>canManage||x.employee_id===ownEmployee?.id).map(x=><tr key={x.id}><td>{x.advance_number}</td><td>{employeeName(x.employee_id)}</td><td>{x.issue_date}</td><td>{money(x.amount)}</td><td>{money(x.balance)}</td><td>{x.status}</td>{canManage&&<td>{Number(x.balance)>0?<div className="inline-form"><input type="number" min="0.01" max={x.balance} step="0.01" placeholder="Amount" value={repayments[x.id]||""} onChange={e=>setRepayments(v=>({...v,[x.id]:e.target.value}))}/><button disabled={saving} onClick={()=>void repayAdvance(x.id)}>Record</button></div>:"—"}</td>}</tr>)}{!advances.length&&<tr><td colSpan={canManage?7:6} className="table-empty">No employee advances found.</td></tr>}</tbody></table></div>
  </>:<div className="hr-organization">
   <div className="transaction-form"><h3>Departments</h3><form className="form-grid" onSubmit={addDepartment}><label>Code<input required value={departmentCode} onChange={e=>setDepartmentCode(e.target.value)}/></label><label>Department name<input required value={departmentName} onChange={e=>setDepartmentName(e.target.value)}/></label><button disabled={saving}>Add department</button></form><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Status</th></tr></thead><tbody>{departments.map(x=><tr key={x.id}><td>{x.code}</td><td>{x.name}</td><td>{x.is_active?"Active":"Inactive"}</td></tr>)}</tbody></table></div></div>
   <div className="transaction-form"><h3>Designations</h3><form className="form-grid" onSubmit={addDesignation}><label>Code<input required value={designationCode} onChange={e=>setDesignationCode(e.target.value)}/></label><label>Designation<input required value={designationName} onChange={e=>setDesignationName(e.target.value)}/></label><label>Department<select value={designationDepartment} onChange={e=>setDesignationDepartment(e.target.value)}><option value="">No department</option>{departments.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select></label><button disabled={saving}>Add designation</button></form><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Department</th></tr></thead><tbody>{designations.map(x=><tr key={x.id}><td>{x.code}</td><td>{x.name}</td><td>{departments.find(d=>d.id===x.department_id)?.name||"—"}</td></tr>)}</tbody></table></div></div>
   <div className="transaction-form"><h3>Employee organization</h3><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Employee</th><th>Department</th><th>Designation</th></tr></thead><tbody>{employees.map(x=><tr key={x.id}><td>{x.employee_code} · {x.full_name}</td><td><select value={x.department_id||""} onChange={e=>void updateEmployee(x.id,{department_id:e.target.value||null})}><option value="">Unassigned</option>{departments.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></td><td><select value={x.designation_id||""} onChange={e=>void updateEmployee(x.id,{designation_id:e.target.value||null})}><option value="">Unassigned</option>{designations.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></td></tr>)}</tbody></table></div></div>
  </div>}
  <p className="module-footnote">Advance repayments are tracked against outstanding balances. They are not automatically deducted from payroll; payroll deductions remain subject to the payroll approval workflow.</p>
 </section>;
}
