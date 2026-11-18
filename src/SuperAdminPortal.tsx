import { FormEvent, useEffect, useMemo, useState } from "react";
import { createClient, Session } from "@supabase/supabase-js";
import "./super-admin.css";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
const db = supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null;
const PUBLIC_APP_URL = "https://ebs-pro.onrender.com";

type PlatformAdmin = { user_id: string; role: "super_admin" | "support_admin" };
type Company = {
  id: string; name: string; city: string | null; contact_email: string | null; contact_phone: string | null; organization_status: string;
  created_at: string; member_count: number; branch_count: number; open_ticket_count: number;
};
type Ticket = {
  id: string; tenant_id: string; subject: string; category: string; priority: string;
  status: string; description: string; resolution: string | null; assigned_to: string | null;
  created_by: string; created_at: string; updated_at: string;
};
type Message = { id: number; ticket_id: string; sender_id: string; body: string; created_at: string };

const dateLabel = (value: string) => new Date(value).toLocaleString();
const errorText = (error: unknown) => error instanceof Error ? error.message : "The request could not be completed.";

export default function SuperAdminPortal({ embedded = false }: { embedded?: boolean }) {
  const [session, setSession] = useState<Session | null>(null);
  const [admin, setAdmin] = useState<PlatformAdmin | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [recoveryMode, setRecoveryMode] = useState(false);
  const [companies, setCompanies] = useState<Company[]>([]);
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [selectedTicket, setSelectedTicket] = useState<string>("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [message, setMessage] = useState("");
  const [companySearch, setCompanySearch] = useState("");
  const [ticketSearch, setTicketSearch] = useState("");
  const [companyId, setCompanyId] = useState("");
  const [subject, setSubject] = useState("");
  const [category, setCategory] = useState("technical");
  const [priority, setPriority] = useState("normal");
  const [description, setDescription] = useState("");
  const [showNewTicket, setShowNewTicket] = useState(false);

  async function loadPortal() {
    if (!db || !session) return;
    setLoading(true);
    setNotice("");
    try {
      const { data: profile, error: profileError } = await db.rpc("platform_admin_me");
      if (profileError) throw profileError;
      const access = Array.isArray(profile) ? profile[0] : profile;
      if (!access?.user_id || !["super_admin", "support_admin"].includes(access.role)) {
        setAdmin(null);
        setCompanies([]);
        setTickets([]);
        setNotice("This account is not authorized for the EBS PRO platform portal.");
        return;
      }
      setAdmin(access as PlatformAdmin);
      const [{ data: companyRows, error: companyError }, { data: ticketRows, error: ticketError }] = await Promise.all([
        db.rpc("platform_admin_list_companies"),
        db.from("platform_support_tickets").select("*").order("updated_at", { ascending: false }).limit(250)
      ]);
      if (companyError) throw companyError;
      if (ticketError) throw ticketError;
      setCompanies((companyRows || []) as Company[]);
      setTickets((ticketRows || []) as Ticket[]);
    } catch (error) {
      setAdmin(null);
      setNotice(errorText(error));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!db) { setLoading(false); return; }
    let live = true;
    db.auth.getSession().then(({ data }) => { if (live) setSession(data.session); });
    const { data: { subscription } } = db.auth.onAuthStateChange((event, next) => { if (event === "PASSWORD_RECOVERY") setRecoveryMode(true); setSession(next); });
    return () => { live = false; subscription.unsubscribe(); };
  }, []);

  useEffect(() => {
    if (!session) {
      setAdmin(null); setCompanies([]); setTickets([]); setLoading(false);
      return;
    }
    void loadPortal();
  }, [session?.user.id]);

  useEffect(() => {
    if (!db || !selectedTicket || !admin) { setMessages([]); return; }
    let live = true;
    db.from("platform_support_messages").select("*").eq("ticket_id", selectedTicket).order("created_at")
      .then(({ data, error }) => {
        if (!live) return;
        if (error) setNotice(error.message);
        else setMessages((data || []) as Message[]);
      });
    return () => { live = false; };
  }, [selectedTicket, admin?.user_id]);

  const filteredCompanies = useMemo(() => companies.filter(company =>
    (company.name + " " + (company.city || "")).toLowerCase().includes(companySearch.toLowerCase())
  ), [companies, companySearch]);
  const filteredTickets = useMemo(() => tickets.filter(ticket => {
    const company = companies.find(item => item.id === ticket.tenant_id)?.name || "";
    return (ticket.subject + " " + company + " " + ticket.status + " " + ticket.priority)
      .toLowerCase().includes(ticketSearch.toLowerCase());
  }), [tickets, companies, ticketSearch]);
  const activeTicket = tickets.find(ticket => ticket.id === selectedTicket) || null;

  async function signIn(event: FormEvent) {
    event.preventDefault();
    if (!db) return;
    setBusy(true); setNotice("");
    try {
      const { data, error } = await db.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
      setSession(data.session);
      setPassword("");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  async function sendPasswordReset() {
    if (!db || !email.trim()) { setNotice("Enter your account email address first."); return; }
    setBusy(true); setNotice("");
    try {
      const { error } = await db.auth.resetPasswordForEmail(email.trim(), { redirectTo: PUBLIC_APP_URL });
      if (error) throw error;
      setNotice("Password recovery email sent. Open the newest link on this website to set a new password.");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  async function saveRecoveredPassword(event: FormEvent) {
    event.preventDefault();
    if (!db) return;
    if (password.length < 12 || !/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/\d/.test(password) || !/[^A-Za-z0-9]/.test(password)) {
      setNotice("Use at least 12 characters with uppercase, lowercase, a number and a symbol."); return;
    }
    setBusy(true); setNotice("");
    try {
      const { error } = await db.auth.updateUser({ password });
      if (error) throw error;
      await db.auth.signOut(); setRecoveryMode(false); setPassword(""); setNotice("Password updated. Sign in with your new password.");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  async function createTicket(event: FormEvent) {
    event.preventDefault();
    if (!db || !admin || !companyId) return;
    setBusy(true); setNotice("");
    try {
      const { data, error } = await db.from("platform_support_tickets").insert({
        tenant_id: companyId, subject: subject.trim(), category, priority,
        description: description.trim(), status: "open", created_by: admin.user_id
      }).select("*").single();
      if (error) throw error;
      setTickets(current => [data as Ticket, ...current]);
      setSelectedTicket(data.id);
      setSubject(""); setDescription(""); setShowNewTicket(false);
      setNotice("Support ticket created.");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  async function updateTicket(changes: Partial<Pick<Ticket, "status" | "assigned_to" | "resolution">>) {
    if (!db || !activeTicket) return;
    setBusy(true); setNotice("");
    try {
      const { data, error } = await db.from("platform_support_tickets")
        .update({ ...changes, updated_at: new Date().toISOString() })
        .eq("id", activeTicket.id).select("*").single();
      if (error) throw error;
      setTickets(current => current.map(ticket => ticket.id === data.id ? data as Ticket : ticket));
      setNotice("Ticket updated.");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  async function sendMessage(event: FormEvent) {
    event.preventDefault();
    if (!db || !admin || !activeTicket || !message.trim()) return;
    setBusy(true); setNotice("");
    try {
      const { data, error } = await db.from("platform_support_messages")
        .insert({ ticket_id: activeTicket.id, sender_id: admin.user_id, body: message.trim() })
        .select("*").single();
      if (error) throw error;
      setMessages(current => [...current, data as Message]);
      setMessage("");
    } catch (error) { setNotice(errorText(error)); }
    finally { setBusy(false); }
  }

  if (!db) return <main className="platform-center"><section className="platform-auth"><h1>EBS PRO Administration</h1><p>Hosting environment is missing the Supabase URL or publishable key.</p></section></main>;
  if (loading) return <main className="platform-center"><div className="platform-loading">EBS PRO · Loading secure platform workspace…</div></main>;
  if (recoveryMode) return <main className="platform-auth-shell"><section className="platform-auth-brand"><div className="platform-mark">E</div><span>ACCOUNT SECURITY</span><h1>Secure your platform account.</h1><p>Choose a new password for your EBS PRO Super Admin account.</p></section><section className="platform-auth-side"><form className="platform-auth" onSubmit={saveRecoveredPassword}><small>RESET PASSWORD</small><h2>Set a new password</h2><p>At least 12 characters with uppercase, lowercase, a number and a symbol.</p><label>New password<input type="password" autoComplete="new-password" minLength={12} required value={password} onChange={event => setPassword(event.target.value)} /></label>{notice && <div className="platform-notice">{notice}</div>}<button disabled={busy}>{busy ? "Updating…" : "Update password"} <span>→</span></button></form></section></main>;
  if (embedded && !session) return <main className="platform-center"><div className="platform-loading">Checking your EBS PRO session…</div></main>;
  if (!session) return <main className="platform-auth-shell"><section className="platform-auth-brand"><div className="platform-mark">E</div><span>PLATFORM OPERATIONS</span><h1>One control room for every EBS PRO company.</h1><p>Internal platform administration for authorized EBS PRO staff.</p><small> EBS PRO V.01 · PLATFORM ADMINISTRATION</small></section><section className="platform-auth-side"><form className="platform-auth" onSubmit={signIn}><small>SECURE STAFF SIGN-IN</small><h2>Admin Portal Configuration</h2><p>Only provisioned Super Admin and Support Admin accounts can enter.</p><label>Email address<input type="email" autoComplete="username" required value={email} onChange={event => setEmail(event.target.value)} /></label><label>Password<input type="password" autoComplete="current-password" required value={password} onChange={event => setPassword(event.target.value)} /></label>{notice && <div className="platform-notice">{notice}</div>}<button disabled={busy}>{busy ? "Signing in…" : "Sign in securely"} <span>→</span></button><a href="#" onClick={event => { event.preventDefault(); void sendPasswordReset(); }}>Forgot password?</a><a href="/">Return to company ERP</a></form></section></main>;
  if (!admin && embedded) return <section className="module-empty"><h2>Platform access restricted</h2><p>This account does not have an active platform administration role.</p></section>;
  if (!admin) return <main className="platform-center"><section className="platform-auth"><div className="platform-mark">E</div><h1>Platform access restricted</h1><p>{notice || "This account has no active platform support role."}</p><button onClick={() => void db.auth.signOut()}>Sign out</button><a href="/">Return to company ERP</a></section></main>;

  return <div className="platform-shell">
    <aside className="platform-sidebar"><div className="platform-brand"><div className="platform-mark">E</div><div><b>EBS <em>PRO</em></b><small>ERP ADMINISTRATION</small></div></div><div className="platform-nav-label">WORKSPACE</div><a className="is-active" href="#overview">◈ Overview</a><a href="#companies">▦ Companies</a><a href="#tickets">▤ Support tickets</a><div className="platform-sidebar-foot"><span>{admin.role.replaceAll("_", " ").toUpperCase()}</span><small>{session.user.email}</small><button onClick={() => void db.auth.signOut()}>Sign out ↗</button></div></aside>
    <main className="platform-main">
      <header className="platform-topbar"><div><small>ERP ADMINISTRATION / PLATFORM CONTROL</small><h1>Admin Portal Configuration</h1></div><div className="platform-top-actions"><span>● SECURE SESSION</span><button onClick={() => void loadPortal()}>↻ Refresh</button></div></header>
      <section className="platform-content" id="overview">
        {notice && <div className="platform-notice">{notice}</div>}
        <div className="platform-welcome"><div><small>GOOD TO SEE YOU</small><h2>All companies. One support desk.</h2><p>Review customer organizations, open support cases and coordinate resolutions without entering tenant financial data.</p></div><button onClick={() => setShowNewTicket(true)}>＋ Create support ticket</button></div>
        <div className="platform-metrics">
          <article><small>REGISTERED COMPANIES</small><strong>{companies.length}</strong><span>All tenant workspaces</span></article>
          <article><small>ACTIVE COMPANIES</small><strong>{companies.filter(item => item.organization_status === "active").length}</strong><span>Available workspaces</span></article>
          <article><small>OPEN SUPPORT CASES</small><strong>{tickets.filter(item => !["resolved", "closed"].includes(item.status)).length}</strong><span>Need attention</span></article>
          <article><small>CRITICAL CASES</small><strong>{tickets.filter(item => item.priority === "critical" && !["resolved", "closed"].includes(item.status)).length}</strong><span>Priority queue</span></article>
        </div>
        {showNewTicket && <form className="platform-ticket-form" onSubmit={createTicket}>
          <div className="platform-section-title"><div><h3>New support ticket</h3><p>Create a case for a registered customer company.</p></div><button type="button" onClick={() => setShowNewTicket(false)}>Close</button></div>
          <label>Customer company<select required value={companyId} onChange={event => setCompanyId(event.target.value)}><option value="">Select company</option>{companies.map(company => <option key={company.id} value={company.id}>{company.name}</option>)}</select></label>
          <label>Subject<input required maxLength={180} value={subject} onChange={event => setSubject(event.target.value)} placeholder="Describe the issue briefly" /></label>
          <div className="platform-form-grid"><label>Category<select value={category} onChange={event => setCategory(event.target.value)}><option value="technical">Technical issue</option><option value="account">Account & access</option><option value="data">Data / transaction issue</option><option value="training">Training request</option><option value="feature">Feature request</option><option value="other">Other</option></select></label><label>Priority<select value={priority} onChange={event => setPriority(event.target.value)}><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="critical">Critical</option></select></label></div>
          <label>Issue details<textarea required rows={4} maxLength={8000} value={description} onChange={event => setDescription(event.target.value)} placeholder="What happened, which screen, and what result was expected?" /></label><button disabled={busy}>{busy ? "Creating…" : "Create ticket"}</button>
        </form>}
        <section className="platform-panel" id="companies"><div className="platform-section-title"><div><h3>Customer companies</h3><p>Tenant directory and account overview</p></div><input value={companySearch} onChange={event => setCompanySearch(event.target.value)} placeholder="Search company or city…" /></div>
          <div className="platform-table-wrap"><table><thead><tr><th>Company</th><th>City</th><th>Support contact</th><th>Status</th><th>Users</th><th>Branches</th><th>Open cases</th><th>Registered</th></tr></thead><tbody>{filteredCompanies.map(company => <tr key={company.id}><td><b>{company.name}</b><small>{company.id.slice(0, 8)}…</small></td><td>{company.city || "—"}</td><td>{company.contact_email || company.contact_phone || "—"}<small>{company.contact_phone || ""}</small></td><td><span className={"platform-status status-" + company.organization_status}>{company.organization_status}</span></td><td>{company.member_count}</td><td>{company.branch_count}</td><td>{company.open_ticket_count}</td><td>{new Date(company.created_at).toLocaleDateString()}</td></tr>)}{!filteredCompanies.length && <tr><td colSpan={8} className="platform-empty">No companies match this search.</td></tr>}</tbody></table></div>
        </section>
        <section className="platform-panel" id="tickets"><div className="platform-section-title"><div><h3>Support desk</h3><p>Track issues, assign ownership and record customer communication</p></div><input value={ticketSearch} onChange={event => setTicketSearch(event.target.value)} placeholder="Search tickets…" /></div>
          <div className="platform-ticket-layout"><div className="platform-ticket-list">{filteredTickets.map(ticket => <button key={ticket.id} className={selectedTicket === ticket.id ? "selected" : ""} onClick={() => setSelectedTicket(ticket.id)}><span className={"platform-priority priority-" + ticket.priority}>{ticket.priority}</span><b>{ticket.subject}</b><small>{companies.find(company => company.id === ticket.tenant_id)?.name || "Company"} · {ticket.status}</small><time>{dateLabel(ticket.updated_at)}</time></button>)}{!filteredTickets.length && <p className="platform-empty">No support tickets yet.</p>}</div>
            <div className="platform-ticket-detail">{activeTicket ? <><div className="platform-ticket-heading"><div><small>{companies.find(company => company.id === activeTicket.tenant_id)?.name || "Customer company"}</small><h4>{activeTicket.subject}</h4><p>{activeTicket.category} · Opened {dateLabel(activeTicket.created_at)}</p></div><span className={"platform-status status-" + activeTicket.status}>{activeTicket.status}</span></div><p className="platform-ticket-description">{activeTicket.description}</p><div className="platform-ticket-controls"><label>Status<select value={activeTicket.status} onChange={event => void updateTicket({ status: event.target.value })}><option value="open">Open</option><option value="in_progress">In progress</option><option value="waiting_customer">Waiting for customer</option><option value="resolved">Resolved</option><option value="closed">Closed</option></select></label><button disabled={busy} onClick={() => void updateTicket({ assigned_to: admin.user_id })}>Assign to me</button></div><div className="platform-messages"><b>Conversation history</b>{messages.map(item => <article key={item.id}><small>{item.sender_id === admin.user_id ? "You / Support" : "Platform staff"} · {dateLabel(item.created_at)}</small><p>{item.body}</p></article>)}{!messages.length && <p className="platform-empty">No messages recorded for this case.</p>}</div><form className="platform-reply" onSubmit={sendMessage}><textarea rows={3} value={message} onChange={event => setMessage(event.target.value)} placeholder="Write a support update…" /><button disabled={busy || !message.trim()}>Send update</button></form></> : <div className="platform-empty platform-empty-detail">Select a support ticket to review its history.</div>}</div>
          </div>
        </section>
        <footer className="platform-footer">EBS PRO V.01 · Platform administration · Every action is restricted by server-side platform roles.</footer>
      </section>
    </main>
  </div>;
}
