import { FormEvent, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {useModuleAction} from "./lib/modulePermissionContext";

type Row = Record<string, any>;
type TrialRow = { account_id: string; account_code: string; account_name: string; account_type: string; total_debit: number; total_credit: number; balance: number };

export default function AccountingModule({ db, tenantId,currentRole }: { db: SupabaseClient; tenantId: string;currentRole:string }) {
  const roleCanManage=["owner","admin","manager","accounts"].includes(currentRole);
  const canCreate=useModuleAction("accounts_finance","create",roleCanManage);
  const canUpdate=useModuleAction("accounts_finance","update",roleCanManage);
  const [tab, setTab] = useState("journals");
  const [accounts, setAccounts] = useState<Row[]>([]);
  const [branches,setBranches]=useState<Row[]>([]);
  const [branchId,setBranchId]=useState("");
  const [journals, setJournals] = useState<Row[]>([]);
  const [trialRows, setTrialRows] = useState<TrialRow[]>([]);
  const [ledgerParties,setLedgerParties]=useState<Row[]>([]);
  const [ledgerRows,setLedgerRows]=useState<Row[]>([]);
  const [ledgerType,setLedgerType]=useState("customer");
  const [selectedParty,setSelectedParty]=useState("");
  const [cashAccounts,setCashAccounts]=useState<Row[]>([]);
  const [cashRows,setCashRows]=useState<Row[]>([]);
  const [cashAccountId,setCashAccountId]=useState("");
  const [cashRecons,setCashRecons]=useState<Row[]>([]);
  const [statementDate,setStatementDate]=useState(new Date().toISOString().slice(0,10));
  const [statementBalance,setStatementBalance]=useState("0");
  const [reconNotes,setReconNotes]=useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [trialDate, setTrialDate] = useState(new Date().toISOString().slice(0, 10));
  const [narration, setNarration] = useState("");
  const [debitAccount, setDebitAccount] = useState("");
  const [creditAccount, setCreditAccount] = useState("");
  const [amount, setAmount] = useState("");
  const [accountForm, setAccountForm] = useState({ account_code: "", account_name: "", account_type: "asset" });

  const money = (value: number) => "PKR " + Number(value || 0).toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const sumType = (type: string) => trialRows.filter(x => x.account_type === type).reduce((sum, x) => sum + Number(x.balance || 0), 0);
  const debitTotal = trialRows.reduce((sum, x) => sum + Number(x.total_debit || 0), 0);
  const creditTotal = trialRows.reduce((sum, x) => sum + Number(x.total_credit || 0), 0);
  const netProfit = sumType("income") - sumType("expense");

  async function load() {
    setLoading(true);
    setNotice("");
    const [a, j, t, br] = await Promise.all([
      db.from("chart_of_accounts").select("id,account_code,account_name,account_type,is_active").eq("tenant_id", tenantId).eq("is_active", true).order("account_code"),
      db.from("journal_entries").select("id,journal_number,entry_date,narration,status,created_at,branch_id").eq("tenant_id", tenantId).order("entry_date", { ascending: false }).limit(300),
      db.rpc("get_trial_balance", { p_tenant_id: tenantId, p_as_of: trialDate }),
      db.from("branches").select("id,name,branch_code").eq("tenant_id",tenantId).order("name")
    ]);
    const err = a.error || j.error || t.error || br.error;
    if (err) setNotice(err.message);
    else {
      setAccounts(a.data || []);
      setBranches(br.data||[]);
      setJournals(j.data || []);
      setTrialRows((t.data || []) as TrialRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId, trialDate]);
  useEffect(()=>{if(tab==="ledger")void loadLedger();if(tab==="cash")void loadCashBook();},[tab,tenantId,ledgerType]);

  async function loadLedger(){
    setNotice("");
    const [coa,party,journal]=await Promise.all([
      db.from("chart_of_accounts").select("id,account_code").eq("tenant_id",tenantId).in("account_code",["1100","2000"]),
      db.from("parties").select("id,party_code,name,party_type,opening_balance").eq("tenant_id",tenantId).order("name"),
      db.from("journal_entries").select("id,journal_number,entry_date,narration,status").eq("tenant_id",tenantId).eq("status","posted").order("entry_date",{ascending:false}).limit(5000)
    ]);
    if(coa.error||party.error||journal.error){setNotice(coa.error?.message||party.error?.message||journal.error?.message||"Party ledger could not be loaded.");return;}
    const ids=(coa.data||[]).map(x=>x.id);if(!ids.length){setNotice("Accounts receivable and payable control accounts are missing.");return;}
    const {data:lines,error}=await db.from("journal_lines").select("journal_entry_id,party_id,account_id,debit,credit,memo").eq("tenant_id",tenantId).in("account_id",ids).not("party_id","is",null).limit(20000);
    if(error){setNotice(error.message);return;}
    const journalMap=new Map((journal.data||[]).map(x=>[x.id,x]));
    const codeMap=new Map((coa.data||[]).map(x=>[x.id,x.account_code]));
    setLedgerParties((party.data||[]).filter(x=>ledgerType==="customer"?["customer","both"].includes(x.party_type):["supplier","both"].includes(x.party_type)));
    setLedgerRows((lines||[]).filter(x=>journalMap.has(x.journal_entry_id)).map(x=>({...x,...journalMap.get(x.journal_entry_id),account_code:codeMap.get(x.account_id)})));
  }

  async function loadCashBook(){
    setNotice("");
    const {data:accountsData,error:accountError}=await db.from("chart_of_accounts").select("id,account_code,account_name").eq("tenant_id",tenantId).in("account_code",["1000","1010"]).eq("is_active",true);
    if(accountError){setNotice(accountError.message);return;}
    setCashAccounts(accountsData||[]);
    if(!accountsData?.length){setNotice("Cash and bank control accounts are not configured.");return;}
    const ids=accountsData.map(x=>x.id);
    const [j,l,r]=await Promise.all([
      db.from("journal_entries").select("id,journal_number,entry_date,narration").eq("tenant_id",tenantId).eq("status","posted").order("entry_date",{ascending:true}).limit(5000),
      db.from("journal_lines").select("journal_entry_id,account_id,debit,credit,memo").eq("tenant_id",tenantId).in("account_id",ids).limit(20000),
      db.from("bank_reconciliations").select("id,account_id,statement_date,statement_balance,book_balance,difference,notes,created_at").eq("tenant_id",tenantId).order("statement_date",{ascending:false}).limit(100)
    ]);
    if(j.error||l.error||r.error){setNotice(j.error?.message||l.error?.message||r.error?.message||"Cashbook could not be loaded.");return;}
    const jm=new Map((j.data||[]).map(x=>[x.id,x])),am=new Map(accountsData.map(x=>[x.id,x]));
    setCashRows((l.data||[]).filter(x=>jm.has(x.journal_entry_id)).map(x=>({...x,...jm.get(x.journal_entry_id),...(am.get(x.account_id)||{})})).sort((a,b)=>String(a.entry_date).localeCompare(String(b.entry_date))||String(a.journal_number).localeCompare(String(b.journal_number))));setCashRecons(r.data||[]);
    if(!cashAccountId)setCashAccountId(ids[0]);
  }

  async function saveReconciliation(){
    if(!canCreate)return;
    const amount=Number(statementBalance);if(!cashAccountId||!statementDate||!Number.isFinite(amount)){setNotice("Select an account and enter a valid statement balance.");return;}
    const book=cashRows.filter(x=>x.account_id===cashAccountId).reduce((n,x)=>n+Number(x.debit||0)-Number(x.credit||0),0);
    const {error}=await db.from("bank_reconciliations").insert({tenant_id:tenantId,account_id:cashAccountId,statement_date:statementDate,statement_balance:amount,book_balance:book,difference:amount-book,notes:reconNotes.trim()||null});
    if(error)setNotice(error.message);else{setNotice("Bank/cash reconciliation snapshot saved.");setReconNotes("");await loadCashBook();}
  }

  async function postJournal(id: string) {
    if(!canUpdate)return;
    setSaving(true); setNotice("");
    try {
      const { error } = await db.rpc("post_journal_entry", { p_journal_entry_id: id });
      if (error) throw error;
      setNotice("Journal posted successfully. Posted entries are final.");
      await load();
    } catch (e) { setNotice(e instanceof Error ? e.message : "Journal posting failed."); }
    finally { setSaving(false); }
  }

  async function saveAccount(e: FormEvent) {
    e.preventDefault(); if(!canCreate)return; setSaving(true); setNotice("");
    try {
      if (!accountForm.account_code.trim() || !accountForm.account_name.trim()) throw new Error("Enter account code and account name.");
      const { error } = await db.from("chart_of_accounts").insert({
        tenant_id: tenantId, account_code: accountForm.account_code.trim(),
        account_name: accountForm.account_name.trim(), account_type: accountForm.account_type,
        is_control_account: false, is_active: true
      });
      if (error) throw error;
      setAccountForm({ account_code: "", account_name: "", account_type: "asset" });
      setNotice("Chart account created.");
      await load();
    } catch (e) { setNotice(e instanceof Error ? e.message : "Account could not be saved."); }
    finally { setSaving(false); }
  }

  async function save(e: FormEvent) {
    e.preventDefault(); if(!canCreate)return; setSaving(true); setNotice("");
    try {
      const value = Number(amount);
      if (!debitAccount || !creditAccount || debitAccount === creditAccount || !Number.isFinite(value) || value <= 0 || !narration.trim()) {
        throw new Error("Choose two different accounts, enter a positive amount and narration.");
      }
      const { data: user } = await db.auth.getUser();
      const number = "EBS-JV-" + Date.now().toString().slice(-9);
      const { data: head, error } = await db.from("journal_entries").insert({
        tenant_id: tenantId, journal_number: number, entry_date: date, source_type: "manual", branch_id: branchId||null,
        narration: narration.trim(), status: "draft", created_by: user.user?.id ?? null
      }).select("id").single();
      if (error) throw error;
      const { error: lineError } = await db.from("journal_lines").insert([
        { tenant_id: tenantId, journal_entry_id: head.id, account_id: debitAccount, debit: value, credit: 0, memo: narration.trim() },
        { tenant_id: tenantId, journal_entry_id: head.id, account_id: creditAccount, debit: 0, credit: value, memo: narration.trim() }
      ]);
      if (lineError) {
        const rollback = await db.from("journal_entries").delete().eq("id", head.id).eq("tenant_id", tenantId);
        throw new Error("Journal lines failed: " + lineError.message + (rollback.error ? " Draft header could not be removed." : " Draft header rolled back."));
      }
      setNotice("Balanced journal draft saved. It has not been posted.");
      setNarration(""); setAmount("");
      await load();
    } catch (e) { setNotice(e instanceof Error ? e.message : "Journal could not be saved."); }
    finally { setSaving(false); }
  }

  return <section className="module-page">
    <div className="module-toolbar"><div><h2>Financial Accounting</h2><p>Double-entry journals, chart of accounts and live trial balance.</p></div><button onClick={() => void load()}>↻ Refresh</button></div>
    {notice && <div className="notice">{notice}</div>}
    <div className="table-tools">
      <button onClick={() => setTab("journals")}>Journal entries</button>
      <button onClick={() => setTab("accounts")}>Chart of accounts</button>
      <button onClick={() => setTab("trial")}>Trial balance & statements</button>
      <button onClick={() => setTab("ledger")}>Customer / Vendor ledgers</button>
      <button onClick={() => setTab("cash")}>Cash & Bank book</button>
    </div>

    {tab === "journals" ? <>
      {canCreate&&<form className="transaction-form" onSubmit={save}>
        <h3>New balanced journal draft</h3>
        <div className="form-grid">
          <label>Entry date<input type="date" value={date} onChange={e => setDate(e.target.value)} /></label>
          <label>Branch<select value={branchId} onChange={e=>setBranchId(e.target.value)}><option value="">Company-wide / unassigned</option>{branches.map(b=><option key={b.id} value={b.id}>{b.branch_code} · {b.name}</option>)}</select></label>
          <label>Debit account<select required value={debitAccount} onChange={e => setDebitAccount(e.target.value)}><option value="">Select account</option>{accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} · {a.account_name}</option>)}</select></label>
          <label>Credit account<select required value={creditAccount} onChange={e => setCreditAccount(e.target.value)}><option value="">Select account</option>{accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} · {a.account_name}</option>)}</select></label>
          <label>Amount (PKR)<input required type="number" min="0.01" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} /></label>
          <label>Narration<input required value={narration} onChange={e => setNarration(e.target.value)} /></label>
        </div>
        <p className="module-footnote">One debit and one equal credit are generated automatically. Drafts do not affect posted balances until authorized posting.</p>
        <button disabled={saving || !accounts.length}>{saving ? "Saving…" : "Save journal draft"}</button>
      </form>
      <h3>Journal register</h3>
      {loading ? <div className="table-empty">Loading journals…</div> : <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Journal</th><th>Date</th><th>Narration</th><th>Status</th><th>Action</th></tr></thead><tbody>
        {journals.map(j => <tr key={j.id}><td>{j.journal_number}</td><td>{j.entry_date}</td><td>{j.narration}</td><td>{j.status}</td><td>{j.status === "draft" ? <button disabled={saving} onClick={() => void postJournal(j.id)}>Post journal</button> : "Posted"}</td></tr>)}
        {!journals.length && <tr><td colSpan={5} className="table-empty">No journal entries yet.</td></tr>}
      </tbody></table></div>}
    </> : tab === "accounts" ? <>
      <h3>Chart of accounts</h3>
      {canCreate&&<form className="transaction-form" onSubmit={saveAccount}><div className="form-grid">
        <label>Account code<input required value={accountForm.account_code} onChange={e => setAccountForm({ ...accountForm, account_code: e.target.value })} /></label>
        <label>Account name<input required value={accountForm.account_name} onChange={e => setAccountForm({ ...accountForm, account_name: e.target.value })} /></label>
        <label>Account type<select value={accountForm.account_type} onChange={e => setAccountForm({ ...accountForm, account_type: e.target.value })}><option value="asset">Asset</option><option value="liability">Liability</option><option value="equity">Equity</option><option value="income">Income</option><option value="expense">Expense</option></select></label>
      </div><button disabled={saving}>{saving ? "Saving…" : "Add account"}</button></form>
      {loading ? <div className="table-empty">Loading accounts…</div> : <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Account name</th><th>Type</th><th>Status</th></tr></thead><tbody>
        {accounts.map(a => <tr key={a.id}><td>{a.account_code}</td><td>{a.account_name}</td><td>{a.account_type}</td><td>{a.is_active ? "Active" : "Inactive"}</td></tr>)}
        {!accounts.length && <tr><td colSpan={4} className="table-empty">No chart accounts configured.</td></tr>}
      </tbody></table></div>}
    </> : tab === "trial" ? <>
      <div className="module-toolbar"><div><h3>Trial balance & financial position</h3><p>Posted journal entries only; draft journals are excluded.</p></div><label>As of date<input type="date" value={trialDate} onChange={e => setTrialDate(e.target.value)} /></label></div>
      {loading ? <div className="table-empty">Calculating posted account balances…</div> : <>
        <div className="stats report-stats">
          <article><small>Total debits</small><strong>{money(debitTotal)}</strong><span>Posted journal lines</span></article>
          <article><small>Total credits</small><strong>{money(creditTotal)}</strong><span>Posted journal lines</span></article>
          <article><small>Assets</small><strong>{money(sumType("asset"))}</strong><span>Debit balance</span></article>
          <article><small>Liabilities</small><strong>{money(sumType("liability"))}</strong><span>Credit balance</span></article>
          <article><small>Equity</small><strong>{money(sumType("equity"))}</strong><span>Credit balance</span></article>
          <article><small>Net profit / loss</small><strong>{money(netProfit)}</strong><span>Income less expenses</span></article>
        </div>
        <div className="table-tools"><strong>Trial balance</strong><span>Difference: {money(debitTotal - creditTotal)}</span></div>
        <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Account</th><th>Type</th><th>Debits</th><th>Credits</th><th>Balance</th></tr></thead><tbody>
          {trialRows.map(r => <tr key={r.account_id}><td>{r.account_code}</td><td>{r.account_name}</td><td>{r.account_type}</td><td>{money(r.total_debit)}</td><td>{money(r.total_credit)}</td><td>{money(r.balance)}</td></tr>)}
          {!trialRows.length && <tr><td colSpan={6} className="table-empty">No active accounts or posted journal balances.</td></tr>}
          <tr><th colSpan={3}>Totals</th><th>{money(debitTotal)}</th><th>{money(creditTotal)}</th><th>{money(debitTotal-creditTotal)}</th></tr>
        </tbody></table></div>
        <h3>Profit & loss summary</h3>
        <div className="table-tools"><span>Income: {money(sumType("income"))}</span><span>Expenses: {money(sumType("expense"))}</span><strong>Net profit / loss: {money(netProfit)}</strong></div>
        <h3>Balance sheet summary</h3>
        <div className="table-tools"><span>Assets: {money(sumType("asset"))}</span><span>Liabilities: {money(sumType("liability"))}</span><span>Equity: {money(sumType("equity"))}</span><strong>Liabilities + equity + current profit: {money(sumType("liability")+sumType("equity")+netProfit)}</strong></div>
      </>}
    </> : tab === "ledger" ? <>
      <div className="module-toolbar"><div><h3>Customer & Vendor Control Ledgers</h3><p>Posted receivables and payables, linked to individual customer and supplier accounts.</p></div><select value={ledgerType} onChange={e=>{setLedgerType(e.target.value);setSelectedParty("");}}><option value="customer">Customer ledger (AR)</option><option value="supplier">Vendor ledger (AP)</option></select></div>
      <div className="form-grid"><label>Select party<select value={selectedParty} onChange={e=>setSelectedParty(e.target.value)}><option value="">All parties</option>{ledgerParties.map(p=><option key={p.id} value={p.id}>{p.party_code} · {p.name}</option>)}</select></label></div>
      {(()=>{const code=ledgerType==="customer"?"1100":"2000";const items=ledgerRows.filter(x=>x.account_code===code&&(!selectedParty||x.party_id===selectedParty)).slice().sort((a,b)=>String(a.entry_date).localeCompare(String(b.entry_date))||String(a.journal_number).localeCompare(String(b.journal_number)));const debit=items.reduce((n,x)=>n+Number(x.debit||0),0),credit=items.reduce((n,x)=>n+Number(x.credit||0),0),balance=ledgerType==="customer"?debit-credit:credit-debit;return <><div className="stats report-stats"><article><small>Total debits</small><strong>{money(debit)}</strong></article><article><small>Total credits</small><strong>{money(credit)}</strong></article><article><small>{ledgerType==="customer"?"Receivable":"Payable"} balance</small><strong>{money(balance)}</strong></article></div><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Party</th><th>Journal</th><th>Description</th><th>Debit</th><th>Credit</th><th>Running balance</th></tr></thead><tbody>{items.map((x,i)=>{const p=ledgerParties.find(y=>y.id===x.party_id);const prior=items.slice(0,i+1).reduce((n,y)=>n+(ledgerType==="customer"?Number(y.debit)-Number(y.credit):Number(y.credit)-Number(y.debit)),0);return <tr key={x.journal_entry_id+":"+i}><td>{x.entry_date}</td><td>{p?.name||x.party_id}</td><td>{x.journal_number}</td><td>{x.narration||x.memo||"—"}</td><td>{money(x.debit)}</td><td>{money(x.credit)}</td><td>{money(prior)}</td></tr>;})}{!items.length&&<tr><td colSpan={7} className="table-empty">No posted ledger transactions for this party type.</td></tr>}</tbody></table></div></>;})()}
    </> : tab === "cash" ? <>
      <div className="module-toolbar"><div><h3>Cash & Bank Book</h3><p>Posted cash and bank journal movements with running balances.</p></div><select value={cashAccountId} onChange={e=>setCashAccountId(e.target.value)}>{cashAccounts.map(a=><option key={a.id} value={a.id}>{a.account_code} · {a.account_name}</option>)}</select><button onClick={()=>void loadCashBook()}>↻ Refresh</button></div>
      <form className="transaction-form" onSubmit={e=>{e.preventDefault();void saveReconciliation();}}><h4>Statement / physical cash reconciliation</h4><div className="form-grid"><label>Statement date<input type="date" required value={statementDate} onChange={e=>setStatementDate(e.target.value)}/></label><label>Statement or counted balance (PKR)<input type="number" step="0.01" required value={statementBalance} onChange={e=>setStatementBalance(e.target.value)}/></label><label>Notes<input value={reconNotes} onChange={e=>setReconNotes(e.target.value)}/></label></div><button type="submit">Save reconciliation snapshot</button></form>
      <h4>Reconciliation history</h4><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Account</th><th>Statement</th><th>Book</th><th>Difference</th><th>Notes</th></tr></thead><tbody>{cashRecons.filter(x=>x.account_id===cashAccountId).map(x=><tr key={x.id}><td>{x.statement_date}</td><td>{cashAccounts.find(a=>a.id===x.account_id)?.account_name}</td><td>{money(x.statement_balance)}</td><td>{money(x.book_balance)}</td><td>{money(x.difference)}</td><td>{x.notes||"—"}</td></tr>)}{!cashRecons.some(x=>x.account_id===cashAccountId)&&<tr><td colSpan={6} className="table-empty">No reconciliation snapshots yet.</td></tr>}</tbody></table></div>
      {(()=>{const items=cashRows.filter(x=>x.account_id===cashAccountId);let balance=0;const ledger:Row[]=items.map(x=>{balance+=Number(x.debit||0)-Number(x.credit||0);return {...x,running:balance};});return <><div className="stats report-stats"><article><small>Book balance</small><strong>{money(balance)}</strong></article><article><small>Money in</small><strong>{money(items.reduce((n,x)=>n+Number(x.debit||0),0))}</strong></article><article><small>Money out</small><strong>{money(items.reduce((n,x)=>n+Number(x.credit||0),0))}</strong></article></div><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Date</th><th>Journal</th><th>Description</th><th>In</th><th>Out</th><th>Running balance</th></tr></thead><tbody>{ledger.slice().reverse().map(x=><tr key={x.journal_entry_id}><td>{x.entry_date}</td><td>{x.journal_number}</td><td>{x.narration||x.memo||"—"}</td><td>{money(x.debit)}</td><td>{money(x.credit)}</td><td>{money(x.running)}</td></tr>)}{!ledger.length&&<tr><td colSpan={6} className="table-empty">No posted cash or bank movements.</td></tr>}</tbody></table></div></>;})()}
    </> : <>
    </>
}
  </section>;
}
