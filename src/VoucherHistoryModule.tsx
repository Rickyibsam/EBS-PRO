import {useEffect,useMemo,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
const TYPES=[
 {table:"sales_orders",label:"Sales orders",number:"order_number",date:"order_date",notes:"notes",approval:true},
 {table:"purchase_orders",label:"Purchase orders",number:"po_number",date:"order_date",notes:"notes",approval:true},
 {table:"journal_entries",label:"Journal vouchers",number:"journal_number",date:"entry_date",notes:"narration",approval:false},
 {table:"goods_receipts",label:"Goods receipts",number:"grn_number",date:"received_date",notes:"notes",approval:false},
 {table:"purchase_invoices",label:"Purchase invoices",number:"supplier_invoice_no",date:"invoice_date",notes:"notes",approval:false},
 {table:"sales_invoices",label:"Sales invoices",number:"invoice_number",date:"invoice_date",notes:null,approval:false},
 {table:"sales_credit_notes",label:"Sales credit notes",number:"credit_note_number",date:"credit_note_date",notes:"reason",approval:false},
 {table:"purchase_debit_notes",label:"Purchase debit notes",number:"debit_note_number",date:"note_date",notes:"reason",approval:false}
] as const;
export default function VoucherHistoryModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [rows,setRows]=useState<any[]>([]),[loading,setLoading]=useState(true),[notice,setNotice]=useState(""),[filter,setFilter]=useState("all");
 const [table,setTable]=useState<string>("sales_orders"),[drafts,setDrafts]=useState<any[]>([]),[selectedId,setSelectedId]=useState(""),[draftDate,setDraftDate]=useState(""),[draftNotes,setDraftNotes]=useState(""),[saving,setSaving]=useState(false);
 const canEdit=["owner","admin","manager","accounts"].includes(currentRole);
 const config=useMemo(()=>TYPES.find(x=>x.table===table)||TYPES[0],[table]);
 async function load(){setLoading(true);const {data,error}=await db.from("voucher_revisions").select("id,entity_table,entity_id,action,before_data,after_data,changed_by,changed_at").eq("tenant_id",tenantId).order("changed_at",{ascending:false}).limit(1000);if(error)setNotice(error.message);else setRows(data||[]);setLoading(false);}
 async function loadDrafts(nextTable=table){
  setSelectedId("");setDraftDate("");setDraftNotes("");
  const {data,error}=await db.from(nextTable as any).select("*").eq("tenant_id",tenantId).eq("status","draft").order("created_at",{ascending:false}).limit(200);
  if(error){setDrafts([]);setNotice(error.message);return;}
  setDrafts(data||[]);
 }
 useEffect(()=>{void load();void loadDrafts("sales_orders");},[tenantId]);
 useEffect(()=>{void loadDrafts(table);},[table]);
 function chooseDraft(id:string){
  setSelectedId(id);const row=drafts.find(x=>x.id===id);if(!row)return;
  setDraftDate(String(row[config.date]||"").slice(0,10));setDraftNotes(config.notes?String(row[config.notes]||""):"");
 }
 async function saveDraft(){
  if(!canEdit||!selectedId)return;
  setSaving(true);setNotice("");
  try{
   const patch:any={[config.date]:config.date==="order_date"&&table==="sales_orders"?draftDate+"T00:00:00":draftDate};
   if(config.notes)patch[config.notes]=draftNotes.trim()||null;
   if(["sales_orders","purchase_orders"].includes(table))patch.updated_at=new Date().toISOString();
   const {error}=await db.from(table as any).update(patch).eq("tenant_id",tenantId).eq("id",selectedId).eq("status","draft");
   if(error)throw error;
   setNotice("Draft voucher header updated. Revision snapshot saved automatically.");
   await loadDrafts();await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Draft voucher could not be saved.");}
  finally{setSaving(false);}
 }
 async function approveDraft(){
  if(!canEdit||!selectedId||!config.approval)return;
  setSaving(true);setNotice("");
  try{
   const {data:user}=await db.auth.getUser();
   const {error}=await db.from(table as any).update({status:"approved",approved_by:user.user?.id||null,...(["sales_orders","purchase_orders"].includes(table)?{updated_at:new Date().toISOString()}:{})}).eq("tenant_id",tenantId).eq("id",selectedId).eq("status","draft");
   if(error)throw error;
   setNotice("Voucher approved. It is no longer editable as a draft.");
   await loadDrafts();await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Voucher approval failed.");}
  finally{setSaving(false);}
 }
 async function postJournal(){
  if(!selectedId||table!=="journal_entries"||!canEdit)return;
  setSaving(true);setNotice("");
  try{const {error}=await db.rpc("post_journal_entry",{p_journal_entry_id:selectedId});if(error)throw error;setNotice("Journal posted. Posted journal is protected from edits.");await loadDrafts();await load();}
  catch(e){setNotice(e instanceof Error?e.message:"Journal posting failed.");}
  finally{setSaving(false);}
 }
 const shown=rows.filter(x=>filter==="all"||x.entity_table===filter);
 const selected=drafts.find(x=>x.id===selectedId);
 return <section className="module-page">
  <div className="module-toolbar"><div><h2>Universal Voucher Editor & Revision History</h2><p>Controlled draft header editing, approval for sales/purchase orders, journal posting and automatic revision snapshots.</p></div><button onClick={()=>void load()}>↻ Refresh history</button></div>
  {notice&&<div className="notice">{notice}</div>}
  <div className="transaction-form"><h3>Draft voucher editor</h3><div className="form-grid">
   <label>Voucher type<select value={table} onChange={e=>setTable(e.target.value)}>{TYPES.map(x=><option key={x.table} value={x.table}>{x.label}</option>)}</select></label>
   <label>Draft voucher<select value={selectedId} onChange={e=>chooseDraft(e.target.value)}><option value="">Select a draft voucher</option>{drafts.map(x=><option key={x.id} value={x.id}>{x[config.number]||x.id} · {x.status}</option>)}</select></label>
   {selected&&<label>Voucher date<input type="date" value={draftDate} onChange={e=>setDraftDate(e.target.value)}/></label>}
   {selected&&config.notes&&<label>Notes / narration<input value={draftNotes} onChange={e=>setDraftNotes(e.target.value)}/></label>}
  </div>
  {selected&&<div className="table-tools"><span>Only draft vouchers can be edited. Monetary totals and line items remain controlled by their source module.</span><button disabled={!canEdit||saving} onClick={()=>void saveDraft()}>Save draft changes</button>{config.approval&&<button disabled={!canEdit||saving} onClick={()=>void approveDraft()}>Approve & lock draft</button>}{table==="journal_entries"&&<button disabled={!canEdit||saving} onClick={()=>void postJournal()}>Post journal</button>}</div>}
  {!drafts.length&&<p className="module-footnote">No draft vouchers available for this type.</p>}
  </div>
  <div className="table-tools"><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All voucher types</option>{[...new Set(rows.map(x=>x.entity_table))].map(x=><option key={x}>{x}</option>)}</select><span>{shown.length} revisions</span></div>
  {loading?<div className="table-empty">Loading revision history…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Changed at</th><th>Voucher type</th><th>Record ID</th><th>Action</th><th>Before snapshot</th><th>After snapshot</th><th>Changed by</th></tr></thead><tbody>{shown.map(x=><tr key={x.id}><td>{new Date(x.changed_at).toLocaleString("en-PK")}</td><td>{x.entity_table}</td><td><code>{x.entity_id}</code></td><td>{x.action}</td><td><details><summary>View JSON</summary><pre>{JSON.stringify(x.before_data,null,2)}</pre></details></td><td>{x.after_data?<details><summary>View JSON</summary><pre>{JSON.stringify(x.after_data,null,2)}</pre></details>:"—"}</td><td>{x.changed_by||"System"}</td></tr>)}{!shown.length&&<tr><td colSpan={7} className="table-empty">No draft voucher revisions recorded.</td></tr>}</tbody></table></div>}
  <p className="module-footnote">Posted voucher headers and lines are protected at database level. Draft header edits are snapshotted. Approval is enabled here for sales and purchase orders; other documents must use their dedicated receipt, invoice, return or journal posting workflow. Line-item editing is still controlled in the source transaction modules.</p>
 </section>;
}
