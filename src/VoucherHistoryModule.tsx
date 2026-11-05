import {useEffect,useMemo,useState} from "react";
type Row=Record<string,any>;
import type {SupabaseClient} from "@supabase/supabase-js";
const TYPES=[
 {table:"sales_orders",label:"Sales orders",number:"order_number",date:"order_date",notes:"notes",approval:true,lines:"sales_order_lines",parentKey:"sales_order_id",lineKind:"taxedSales"},
 {table:"purchase_orders",label:"Purchase orders",number:"po_number",date:"order_date",notes:"notes",approval:true,lines:"purchase_order_lines",parentKey:"purchase_order_id",lineKind:"taxedPurchase"},
 {table:"journal_entries",label:"Journal vouchers",number:"journal_number",date:"entry_date",notes:"narration",approval:false,lines:"journal_lines",parentKey:"journal_entry_id",lineKind:"journal"},
 {table:"goods_receipts",label:"Goods receipts",number:"grn_number",date:"received_date",notes:"notes",approval:false,lines:"goods_receipt_lines",parentKey:"goods_receipt_id",lineKind:"grn"},
 {table:"purchase_invoices",label:"Purchase invoices",number:"supplier_invoice_no",date:"invoice_date",notes:"notes",approval:false,lines:"purchase_invoice_lines",parentKey:"purchase_invoice_id",lineKind:"simplePurchase"},
 {table:"sales_invoices",label:"Sales invoices",number:"invoice_number",date:"invoice_date",notes:null,approval:false,lines:"sales_invoice_lines",parentKey:"sales_invoice_id",lineKind:"taxedSales"},
 {table:"sales_credit_notes",label:"Sales credit notes",number:"credit_note_number",date:"credit_note_date",notes:"reason",approval:false,lines:"sales_credit_note_lines",parentKey:"credit_note_id",lineKind:"taxedSales"},
 {table:"purchase_debit_notes",label:"Purchase debit notes",number:"debit_note_number",date:"note_date",notes:"reason",approval:false,lines:"purchase_debit_note_lines",parentKey:"debit_note_id",lineKind:"simpleDebit"}
] as const;
const LINE_FIELDS:any={
 taxedSales:[["quantity","Quantity","number"],["unit_price","Unit price","number"],["tax_rate","Tax %","number"],["discount_amount","Discount","number"]],
 taxedPurchase:[["quantity","Quantity","number"],["unit_cost","Unit cost","number"],["tax_rate","Tax %","number"],["discount_amount","Discount","number"]],
 simplePurchase:[["quantity","Quantity","number"],["unit_cost","Unit cost","number"]],
 simpleDebit:[["quantity","Quantity","number"],["unit_cost","Unit cost","number"]],
 journal:[["debit","Debit","number"],["credit","Credit","number"],["memo","Line memo","text"]],
 grn:[["quantity","Received quantity","number"],["accepted_quantity","Accepted quantity","number"],["rejected_quantity","Rejected quantity","number"],["unit_cost","Unit cost","number"],["batch_number","Batch number","text"],["expiry_date","Expiry date","date"]]
};
export default function VoucherHistoryModule({db,tenantId,currentRole}:{db:SupabaseClient;tenantId:string;currentRole:string}){
 const [rows,setRows]=useState<any[]>([]),[loading,setLoading]=useState(true),[notice,setNotice]=useState(""),[filter,setFilter]=useState("all");
 const [table,setTable]=useState<string>("sales_orders"),[drafts,setDrafts]=useState<any[]>([]),[selectedId,setSelectedId]=useState(""),[draftDate,setDraftDate]=useState(""),[draftNotes,setDraftNotes]=useState(""),[lineRows,setLineRows]=useState<any[]>([]),[saving,setSaving]=useState(false);
 const canEdit=["owner","admin","manager","accounts"].includes(currentRole);
 const canApprove=["owner","admin","manager"].includes(currentRole);
 const config=useMemo(()=>TYPES.find(x=>x.table===table)||TYPES[0],[table]);
 async function load(){setLoading(true);const {data,error}=await db.from("voucher_revisions").select("id,entity_table,entity_id,action,before_data,after_data,changed_by,changed_at").eq("tenant_id",tenantId).order("changed_at",{ascending:false}).limit(1000);if(error)setNotice(error.message);else setRows(data||[]);setLoading(false);}
 async function loadDrafts(nextTable=table){
  setSelectedId("");setDraftDate("");setDraftNotes("");setLineRows([]);
  const {data,error}=await db.from(nextTable as any).select("*").eq("tenant_id",tenantId).eq("status","draft").order("created_at",{ascending:false}).limit(200);
  if(error){setDrafts([]);setNotice(error.message);return;}
  setDrafts(data||[]);
 }
 async function loadDraftLines(id:string,nextTable=table){
  const cfg=TYPES.find(x=>x.table===nextTable);
  if(!cfg?.lines){setLineRows([]);return;}
  const {data,error}=await db.from(cfg.lines as any).select("*").eq("tenant_id",tenantId).eq(cfg.parentKey as string,id);
  if(error){setNotice(error.message);setLineRows([]);return;}
  setLineRows(data||[]);
 }
 function changeLine(id:string,key:string,value:any){setLineRows(rows=>rows.map(row=>row.id===id?{...row,[key]:value}:row));}
 async function saveLines(){
  if(!canEdit||!selectedId||!config.lines)return;
  setSaving(true);setNotice("");
  try{
   const fields=(LINE_FIELDS as any)[config.lineKind] as Array<[string,string,string]>;
   const payload=lineRows.map(row=>Object.fromEntries([["id",row.id],...fields.map(([key])=>[key,row[key]===""?null:(row[key]??null)])]));
   const {data,error}=await db.rpc("update_draft_voucher_lines",{p_tenant_id:tenantId,p_voucher_table:table,p_voucher_id:selectedId,p_lines:payload});
   if(error)throw error;
   setNotice("All draft line items saved. Line totals and voucher totals were recalculated atomically.");
   await loadDraftLines(selectedId,table);await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Draft line items could not be saved.");}
  finally{setSaving(false);}
 }
 useEffect(()=>{void load();void loadDrafts("sales_orders");},[tenantId]);
 useEffect(()=>{void loadDrafts(table);},[table]);
 function chooseDraft(id:string){
  setSelectedId(id);const row=drafts.find(x=>x.id===id);if(!row)return;
  setDraftDate(String(row[config.date]||"").slice(0,10));setDraftNotes(config.notes?String(row[config.notes]||""):"");void loadDraftLines(id,table);
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
  if(!canApprove||!selectedId||!config.approval)return;
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
 async function restoreRevision(revision:Row){
  if(!canEdit||revision.action!=="updated"||String(revision.entity_table).endsWith("_lines"))return;
  if(!window.confirm("Restore this earlier header snapshot? The current draft values will be saved as a new revision."))return;
  setSaving(true);setNotice("");
  try{
   const {data,error}=await db.rpc("restore_draft_voucher_revision",{p_revision_id:revision.id});
   if(error)throw error;
   setNotice("Draft voucher header restored from revision history. The previous current state was preserved as a new revision.");
   await load();
  }catch(e){setNotice(e instanceof Error?e.message:"Revision restore failed.");}
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
  {selected&&<div className="table-tools"><span>Only draft vouchers can be edited. Line totals and header totals are recalculated in one database transaction.</span><button disabled={!canEdit||saving} onClick={()=>void saveDraft()}>Save draft header</button>{config.approval&&canApprove&&<button disabled={saving} onClick={()=>void approveDraft()}>Approve & lock draft</button>}{table==="journal_entries"&&<button disabled={!canEdit||saving} onClick={()=>void postJournal()}>Post journal</button>}</div>}
  {selected&&config.lines&&<div className="transaction-form"><h3>Draft line item editor</h3>{lineRows.map(row=><div className="form-grid" key={row.id}><strong>{row.product_id||row.account_id||row.id}</strong>{(LINE_FIELDS as any)[config.lineKind].map(([key,label,type]:[string,string,string])=><label key={key}>{label}<input type={type} step={type==="number"?"0.001":undefined} value={row[key]??""} onChange={e=>changeLine(row.id,key,type==="number"?(e.target.value===""?"":Number(e.target.value)):e.target.value)}/></label>)}</div>)}{!lineRows.length&&<p>No line items found for this draft.</p>}<button disabled={!canEdit||saving||!lineRows.length} onClick={()=>void saveLines()}>Save all line items</button></div>}
  {!drafts.length&&<p className="module-footnote">No draft vouchers available for this type.</p>}
  </div>
  <div className="table-tools"><select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All voucher types</option>{[...new Set(rows.map(x=>x.entity_table))].map(x=><option key={x}>{x}</option>)}</select><span>{shown.length} revisions</span></div>
  {loading?<div className="table-empty">Loading revision history…</div>:<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Changed at</th><th>Voucher type</th><th>Record ID</th><th>Action</th><th>Before snapshot</th><th>After snapshot</th><th>Changed by</th><th>Restore</th></tr></thead><tbody>{shown.map(x=><tr key={x.id}><td>{new Date(x.changed_at).toLocaleString("en-PK")}</td><td>{x.entity_table}</td><td><code>{x.entity_id}</code></td><td>{x.action}</td><td><details><summary>View JSON</summary><pre>{JSON.stringify(x.before_data,null,2)}</pre></details></td><td>{x.after_data?<details><summary>View JSON</summary><pre>{JSON.stringify(x.after_data,null,2)}</pre></details>:"—"}</td><td>{x.changed_by||"System"}</td><td>{canEdit&&x.action==="updated"&&!String(x.entity_table).endsWith("_lines")?<button disabled={saving} onClick={()=>void restoreRevision(x)}>Restore before</button>:"—"}</td></tr>)}{!shown.length&&<tr><td colSpan={8} className="table-empty">No draft voucher revisions recorded.</td></tr>}</tbody></table></div>}
  <p className="module-footnote">Posted voucher headers and lines are protected at database level. Draft headers and supported line items can be edited here with atomic total recalculation and automatic revision snapshots. Earlier header snapshots can be restored while the voucher remains draft; line snapshots remain available for review. Approval is enabled for sales and purchase orders; other documents use their dedicated posting workflows.</p>
 </section>;
}
