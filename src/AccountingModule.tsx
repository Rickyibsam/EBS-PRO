import { FormEvent, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, any>;
type TrialRow = { account_id: string; account_code: string; account_name: string; account_type: string; total_debit: number; total_credit: number; balance: number };

export default function AccountingModule({ db, tenantId }: { db: SupabaseClient; tenantId: string }) {
  const [tab, setTab] = useState("journals");
  const [accounts, setAccounts] = useState<Row[]>([]);
  const [journals, setJournals] = useState<Row[]>([]);
  const [trialRows, setTrialRows] = useState<TrialRow[]>([]);
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
    const [a, j, t] = await Promise.all([
      db.from("chart_of_accounts").select("id,account_code,account_name,account_type,is_active").eq("tenant_id", tenantId).eq("is_active", true).order("account_code"),
      db.from("journal_entries").select("id,journal_number,entry_date,narration,status,created_at").eq("tenant_id", tenantId).order("entry_date", { ascending: false }).limit(300),
      db.rpc("get_trial_balance", { p_tenant_id: tenantId, p_as_of: trialDate })
    ]);
    const err = a.error || j.error || t.error;
    if (err) setNotice(err.message);
    else {
      setAccounts(a.data || []);
      setJournals(j.data || []);
      setTrialRows((t.data || []) as TrialRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId, trialDate]);

  async function postJournal(id: string) {
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
    e.preventDefault(); setSaving(true); setNotice("");
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
    e.preventDefault(); setSaving(true); setNotice("");
    try {
      const value = Number(amount);
      if (!debitAccount || !creditAccount || debitAccount === creditAccount || !Number.isFinite(value) || value <= 0 || !narration.trim()) {
        throw new Error("Choose two different accounts, enter a positive amount and narration.");
      }
      const { data: user } = await db.auth.getUser();
      const number = "EBS-JV-" + Date.now().toString().slice(-9);
      const { data: head, error } = await db.from("journal_entries").insert({
        tenant_id: tenantId, journal_number: number, entry_date: date, source_type: "manual",
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
    </div>

    {tab === "journals" ? <>
      <form className="transaction-form" onSubmit={save}>
        <h3>New balanced journal draft</h3>
        <div className="form-grid">
          <label>Entry date<input type="date" value={date} onChange={e => setDate(e.target.value)} /></label>
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
      <form className="transaction-form" onSubmit={saveAccount}><div className="form-grid">
        <label>Account code<input required value={accountForm.account_code} onChange={e => setAccountForm({ ...accountForm, account_code: e.target.value })} /></label>
        <label>Account name<input required value={accountForm.account_name} onChange={e => setAccountForm({ ...accountForm, account_name: e.target.value })} /></label>
        <label>Account type<select value={accountForm.account_type} onChange={e => setAccountForm({ ...accountForm, account_type: e.target.value })}><option value="asset">Asset</option><option value="liability">Liability</option><option value="equity">Equity</option><option value="income">Income</option><option value="expense">Expense</option></select></label>
      </div><button disabled={saving}>{saving ? "Saving…" : "Add account"}</button></form>
      {loading ? <div className="table-empty">Loading accounts…</div> : <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Account name</th><th>Type</th><th>Status</th></tr></thead><tbody>
        {accounts.map(a => <tr key={a.id}><td>{a.account_code}</td><td>{a.account_name}</td><td>{a.account_type}</td><td>{a.is_active ? "Active" : "Inactive"}</td></tr>)}
        {!accounts.length && <tr><td colSpan={4} className="table-empty">No chart accounts configured.</td></tr>}
      </tbody></table></div>}
    </> : <>
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
    </>}
  </section>;
}
