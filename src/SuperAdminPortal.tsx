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
  id: string; tenant_id: string; ticket_number: number; subject: string; category: string; priority: string;
  status: string; description: string; resolution: string | null; assigned_to: string | null;
  created_by: string; created_at: string; updated_at: string; sla_due_at: string | null;
  first_response_at: string | null;
};
type Message = { id: number; ticket_id: string; sender_id: string; body: string; created_at: string };
type Attachment = { id: string; ticket_id: string; storage_path: string; file_name: string; mime_type: string; file_size: number; created_at: string };
type Notification = { id: string; ticket_id: string | null; event_type: string; title: string; body: string; read_at: string | null; created_at: string };
type Staff = { user_id: string; email: string; role: "super_admin" | "support_admin"; is_active: boolean; created_at: string; last_sign_in_at: string | null };
type StaffAudit = { id: number; actor_email: string; target_email: string; action: string; old_role: string | null; new_role: string; old_is_active: boolean | null; new_is_active: boolean; created_at: string };

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
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [securityBusy, setSecurityBusy] = useState(false);
  const [seoResults, setSeoResults] = useState<Array<{label:string;ok:boolean;detail:string}>>([]);
  const [seoCheckedAt, setSeoCheckedAt] = useState("");
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [attachmentFiles, setAttachmentFiles] = useState<File[]>([]);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [staff, setStaff] = useState<Staff[]>([]);
  const [staffAudit, setStaffAudit] = useState<StaffAudit[]>([]);
  const [staffEmail, setStaffEmail] = useState("");
  const [staffRole, setStaffRole] = useState<"super_admin" | "support_admin">("support_admin");
  const [staffBusy, setStaffBusy] = useState(false);

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
      const [
        { data: companyRows, error: companyError },
        { data: ticketRows, error: ticketError },
        { data: notificationRows, error: notificationError }
      ] = await Promise.all([
        db.rpc("platform_admin_list_companies"),
        db.from("platform_support_tickets").select("*").order("updated_at", { ascending: false }).limit(250),
        db.from("platform_support_notifications").select("*").eq("recipient_id", access.user_id).order("created_at", { ascending: false }).limit(50)
      ]);
      if (companyError) throw companyError;
      if (ticketError) throw ticketError;
      if (notificationError) throw notificationError;
      setCompanies((companyRows || []) as Company[]);
      setTickets((ticketRows || []) as Ticket[]);
      setNotifications((notificationRows || []) as Notification[]);
      if (access.role === "super_admin") {
        const [{ data: staffRows, error: staffError }, { data: auditRows, error: auditError }] = await Promise.all([
          db.rpc("platform_admin_list_staff"),
          db.rpc("platform_admin_list_staff_audit")
        ]);
        if (staffError) throw staffError;
        if (auditError) throw auditError;
        setStaff((staffRows || []) as Staff[]);
        setStaffAudit((auditRows || []) as StaffAudit[]);
      } else {
        setStaff([]);
        setStaffAudit([]);
      }
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
    if (!db || !admin) return;
    const channel = db.channel("platform-support-notifications-" + admin.user_id)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "platform_support_notifications", filter: "recipient_id=eq." + admin.user_id }, payload => {
        const item = payload.new as Notification;
        setNotifications(current => current.some(row => row.id === item.id) ? current : [item, ...current].slice(0, 50));
      }).subscribe();
    return () => { void db.removeChannel(channel); };
  }, [admin?.user_id]);

  useEffect(() => {
    if (!db || !selectedTicket || !admin) { setMessages([]); setAttachments([]); return; }
    let live = true;
    Promise.all([
      db.from("platform_support_messages").select("*").eq("ticket_id", selectedTicket).order("created_at"),
      db.from("platform_support_attachments").select("*").eq("ticket_id", selectedTicket).order("created_at")
    ]).then(([messageResult, attachmentResult]) => {
      if (!live) return;
      if (messageResult.error) setNotice(messageResult.error.message);
      else setMessages((messageResult.data || []) as Message[]);
      if (attachmentResult.error) setNotice(attachmentResult.error.message);
      else setAttachments((attachmentResult.data || []) as Attachment[]);
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

  async function changeOwnPassword(event: FormEvent) {
    event.preventDefault();
    if (!db || !session?.user.email) return;
    if (newPassword.length < 12 || !/[a-z]/.test(newPassword) || !/[A-Z]/.test(newPassword) || !/\d/.test(newPassword) || !/[^A-Za-z0-9]/.test(newPassword)) {
      setNotice("Use at least 12 characters with uppercase, lowercase, a number and a symbol."); return;
    }
    if (newPassword !== confirmPassword) { setNotice("New password and confirmation do not match."); return; }
    setSecurityBusy(true); setNotice("");
    try {
      const { error: verifyError } = await db.auth.signInWithPassword({ email: session.user.email, password: currentPassword });
      if (verifyError) throw new Error("Current password is incorrect. Your password was not changed.");
      const { error } = await db.auth.updateUser({ password: newPassword });
      if (error) throw error;
      setCurrentPassword(""); setNewPassword(""); setConfirmPassword("");
      setNotice("Your password has been changed successfully.");
    } catch (error) { setNotice(errorText(error)); }
    finally { setSecurityBusy(false); }
  }

  function runWebsiteAudit() {
    const navEntry = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined;
    const images = Array.from(document.images);
    const missingAlt = images.filter(image => !image.hasAttribute("alt"));
    const title = document.title.trim();
    const description = document.querySelector('meta[name="description"]')?.getAttribute("content")?.trim() || "";
    const viewport = Boolean(document.querySelector('meta[name="viewport"]'));
    const canonical = Boolean(document.querySelector('link[rel="canonical"]'));
    const h1Count = document.querySelectorAll("h1").length;
    const loadMs = navEntry?.loadEventEnd ? Math.round(navEntry.loadEventEnd - navEntry.startTime) : 0;
    const checks = [
      {label:"HTTPS connection",ok:location.protocol === "https:",detail:location.protocol === "https:" ? "Secure HTTPS is active." : "Use HTTPS for all production pages."},
      {label:"Page title",ok:title.length >= 10 && title.length <= 60,detail:title ? title.length + " characters: " + title : "Add a descriptive page title."},
      {label:"Meta description",ok:description.length >= 50 && description.length <= 160,detail:description ? description.length + " characters. Recommended range: 50–160." : "Add a concise meta description."},
      {label:"Mobile viewport",ok:viewport,detail:viewport ? "Viewport meta tag is present." : "Add a responsive viewport meta tag."},
      {label:"Canonical URL",ok:canonical,detail:canonical ? "Canonical link is present." : "Add a canonical URL on public/indexable pages; do not expose private ERP routes."},
      {label:"Heading structure",ok:h1Count === 1,detail:"Found " + h1Count + " H1 headings on the current view; aim for one clear page heading."},
      {label:"Image alternative text",ok:missingAlt.length === 0,detail:missingAlt.length ? missingAlt.length + " of " + images.length + " images have no alt attribute." : images.length + " images checked; alt attributes are present."},
      {label:"Page load timing",ok:loadMs > 0 && loadMs <= 2500,detail:loadMs ? "Browser load event: " + (loadMs/1000).toFixed(2) + " seconds (single browser sample)." : "Timing unavailable until the next full page load."},
      {label:"Private ERP indexing protection",ok:Boolean(document.querySelector('meta[name="robots"][content*="noindex"]')),detail:"Authenticated ERP pages should be noindex; public marketing pages need a separate indexable site."}
    ];
    setSeoResults(checks); setSeoCheckedAt(new Date().toLocaleString());
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

  async function uploadTicketFiles(ticketId: string, files: File[]) {
    if (!db || !admin) return;
    const allowed = new Set(["application/pdf", "image/jpeg", "image/png", "image/webp", "text/plain"]);
    for (const file of files) {
      if (!allowed.has(file.type) || file.size < 1 || file.size > 10 * 1024 * 1024) {
        throw new Error("Attachments must be PDF, JPG, PNG, WEBP or TXT files up to 10 MiB each.");
      }
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 100);
      const path = ticketId + "/" + admin.user_id + "/" + crypto.randomUUID() + "-" + safeName;
      const { error: uploadError } = await db.storage.from("platform-support-attachments").upload(path, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;
      const { data, error } = await db.from("platform_support_attachments").insert({
        ticket_id: ticketId, storage_path: path, file_name: file.name, mime_type: file.type,
        file_size: file.size, uploaded_by: admin.user_id
      }).select("*").single();
      if (error) { await db.storage.from("platform-support-attachments").remove([path]); throw error; }
      setAttachments(current => [...current, data as Attachment]);
    }
  }

  async function openAttachment(item: Attachment) {
    if (!db) return;
    const { data, error } = await db.storage.from("platform-support-attachments").createSignedUrl(item.storage_path, 60);
    if (error) { setNotice(error.message); return; }
    window.open(data.signedUrl, "_blank", "noopener,noreferrer");
  }

  async function provisionStaff(event: FormEvent) {
    event.preventDefault();
    if (!db || admin?.role !== "super_admin" || !staffEmail.trim()) return;
    setStaffBusy(true); setNotice("");
    try {
      const { error } = await db.rpc("platform_admin_upsert_staff_by_email", {
        p_email: staffEmail.trim(), p_role: staffRole, p_is_active: true
      });
      if (error) throw error;
      setStaffEmail("");
      setNotice("Platform staff access updated.");
      await loadPortal();
    } catch (error) { setNotice(errorText(error)); }
    finally { setStaffBusy(false); }
  }

  async function changeStaffAccess(item: Staff, isActive: boolean) {
    if (!db || admin?.role !== "super_admin") return;
    setStaffBusy(true); setNotice("");
    try {
      const { error } = await db.rpc("platform_admin_upsert_staff_by_email", {
        p_email: item.email, p_role: item.role, p_is_active: isActive
      });
      if (error) throw error;
      setNotice("Staff access updated.");
      await loadPortal();
    } catch (error) { setNotice(errorText(error)); }
    finally { setStaffBusy(false); }
  }

  async function sendStaffPasswordReset(item: Staff) {
    if (!db || admin?.role !== "super_admin") return;
    setStaffBusy(true); setNotice("");
    try {
      const { error } = await db.auth.resetPasswordForEmail(item.email, { redirectTo: PUBLIC_APP_URL });
      if (error) throw error;
      setNotice("Password recovery email sent to " + item.email + ".");
    } catch (error) { setNotice(errorText(error)); }
    finally { setStaffBusy(false); }
  }

  async function markNotificationRead(item: Notification) {
    if (!db || !admin || item.read_at) return;
    const readAt = new Date().toISOString();
    const { error } = await db.from("platform_support_notifications").update({ read_at: readAt }).eq("id", item.id).eq("recipient_id", admin.user_id);
    if (error) { setNotice(error.message); return; }
    setNotifications(current => current.map(row => row.id === item.id ? { ...row, read_at: readAt } : row));
    if (item.ticket_id) setSelectedTicket(item.ticket_id);
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
      if (attachmentFiles.length) {
        await uploadTicketFiles(activeTicket.id, attachmentFiles);
        setAttachmentFiles([]);
      }
      setMessage("");
      setNotice("Support update sent.");
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
    <aside className="platform-sidebar"><div className="platform-brand"><div className="platform-mark">E</div><div><b>EBS <em>PRO</em></b><small>ERP ADMINISTRATION</small></div></div><div className="platform-nav-label">WORKSPACE</div><a className="is-active" href="#overview">◈ Overview</a><a href="#companies">▦ Companies</a><a href="#tickets">▤ Support tickets</a><a href="#notifications">♧ Notifications {notifications.some(item => !item.read_at) ? "•" : ""}</a>{admin.role === "super_admin" && <a href="#staff">♙ Support Staff</a>}<a href="#security">♙ Password & Security</a><a href="#website-optimization">⚡ Website Optimization</a><div className="platform-sidebar-foot"><span>{admin.role.replaceAll("_", " ").toUpperCase()}</span><small>{session.user.email}</small><button onClick={() => void db.auth.signOut()}>Sign out ↗</button></div></aside>
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
        <section className="platform-panel" id="notifications">
          <div className="platform-section-title"><div><h3>Notifications</h3><p>New customer cases, replies, assignments and status updates.</p></div><span>{notifications.filter(item => !item.read_at).length} unread</span></div>
          <div className="platform-notification-list">
            {notifications.map(item => <button key={item.id} className={item.read_at ? "is-read" : "is-unread"} onClick={() => void markNotificationRead(item)}>
              <span>{item.read_at ? "READ" : "NEW"}</span><b>{item.title}</b><p>{item.body}</p><time>{dateLabel(item.created_at)}</time>
            </button>)}
            {!notifications.length && <p className="platform-empty">No platform notifications yet.</p>}
          </div>
        </section>
        <section className="platform-panel" id="companies"><div className="platform-section-title"><div><h3>Customer companies</h3><p>Tenant directory and account overview</p></div><input value={companySearch} onChange={event => setCompanySearch(event.target.value)} placeholder="Search company or city…" /></div>
          <div className="platform-table-wrap"><table><thead><tr><th>Company</th><th>City</th><th>Support contact</th><th>Status</th><th>Users</th><th>Branches</th><th>Open cases</th><th>Registered</th></tr></thead><tbody>{filteredCompanies.map(company => <tr key={company.id}><td><b>{company.name}</b><small>{company.id.slice(0, 8)}…</small></td><td>{company.city || "—"}</td><td>{company.contact_email || company.contact_phone || "—"}<small>{company.contact_phone || ""}</small></td><td><span className={"platform-status status-" + company.organization_status}>{company.organization_status}</span></td><td>{company.member_count}</td><td>{company.branch_count}</td><td>{company.open_ticket_count}</td><td>{new Date(company.created_at).toLocaleDateString()}</td></tr>)}{!filteredCompanies.length && <tr><td colSpan={8} className="platform-empty">No companies match this search.</td></tr>}</tbody></table></div>
        </section>
        {admin.role === "super_admin" && <section className="platform-panel" id="staff">
          <div className="platform-section-title"><div><h3>Platform Staff Management</h3><p>Provision only registered, email-confirmed EBS PRO accounts. Support staff do not receive tenant financial access.</p></div></div>
          <form className="platform-staff-form" onSubmit={provisionStaff}>
            <label>Registered account email<input type="email" required value={staffEmail} onChange={event => setStaffEmail(event.target.value)} placeholder="staff@example.com" /></label>
            <label>Platform role<select value={staffRole} onChange={event => setStaffRole(event.target.value as "super_admin" | "support_admin")}><option value="support_admin">Support Admin</option><option value="super_admin">Super Admin</option></select></label>
            <button disabled={staffBusy || !staffEmail.trim()}>{staffBusy ? "Saving…" : "Grant platform access"}</button>
          </form>
          <p className="platform-staff-hint">The staff member must first create an EBS PRO account and confirm its email. Passwords are never visible here; use the recovery email action to let a staff member set their own password.</p>
          <div className="platform-table-wrap"><table><thead><tr><th>Staff account</th><th>Role</th><th>Access</th><th>Last sign-in</th><th>Actions</th></tr></thead><tbody>
            {staff.map(item => <tr key={item.user_id}><td><b>{item.email}</b><small>{item.user_id.slice(0, 8)}…</small></td><td>{item.role.replaceAll("_", " ")}</td><td><span className={"platform-status " + (item.is_active ? "status-active" : "status-closed")}>{item.is_active ? "Active" : "Inactive"}</span></td><td>{item.last_sign_in_at ? dateLabel(item.last_sign_in_at) : "Never"}</td><td><div className="platform-staff-actions"><button disabled={staffBusy || (item.user_id === admin.user_id && item.is_active)} onClick={() => void changeStaffAccess(item, !item.is_active)}>{item.is_active ? "Deactivate" : "Activate"}</button><button disabled={staffBusy} onClick={() => void sendStaffPasswordReset(item)}>Send password reset</button></div></td></tr>)}
            {!staff.length && <tr><td colSpan={5} className="platform-empty">No platform staff accounts have been provisioned.</td></tr>}
          </tbody></table></div>
          <div className="platform-section-title"><div><h3>Staff access audit</h3><p>Immutable record of staff provisioning and role/access changes.</p></div></div>
          <div className="platform-table-wrap"><table><thead><tr><th>Time</th><th>Performed by</th><th>Target account</th><th>Action</th><th>Role change</th><th>Access</th></tr></thead><tbody>
            {staffAudit.map(item => <tr key={item.id}><td>{dateLabel(item.created_at)}</td><td>{item.actor_email}</td><td>{item.target_email}</td><td>{item.action.replaceAll("_", " ")}</td><td>{item.old_role || "—"} → {item.new_role}</td><td>{item.old_is_active === null ? "—" : item.old_is_active ? "Active" : "Inactive"} → {item.new_is_active ? "Active" : "Inactive"}</td></tr>)}
            {!staffAudit.length && <tr><td colSpan={6} className="platform-empty">No staff access changes recorded yet.</td></tr>}
          </tbody></table></div>
        </section>}
        <section className="platform-panel" id="security">
          <div className="platform-section-title"><div><h3>Password & Security</h3><p>Change your own Super Admin password with current-password verification.</p></div></div>
          <form className="platform-security-form" onSubmit={changeOwnPassword}>
            <label>Current password<input type="password" autoComplete="current-password" required value={currentPassword} onChange={event => setCurrentPassword(event.target.value)} /></label>
            <label>New password<input type="password" autoComplete="new-password" minLength={12} required value={newPassword} onChange={event => setNewPassword(event.target.value)} /></label>
            <label>Confirm new password<input type="password" autoComplete="new-password" minLength={12} required value={confirmPassword} onChange={event => setConfirmPassword(event.target.value)} /></label>
            <small>Minimum 12 characters, uppercase, lowercase, number and symbol. Never share your password or recovery link.</small>
            <button disabled={securityBusy}>{securityBusy ? "Updating…" : "Change my password"}</button>
          </form>
        </section>
        <section className="platform-panel" id="website-optimization">
          <div className="platform-section-title"><div><h3>Website Optimization</h3><p>Run an on-page technical audit of the current EBS PRO page in this browser.</p></div><button type="button" onClick={runWebsiteAudit}>Run website audit</button></div>
          <div className="platform-optimization-intro"><b>Performance · Technical SEO · Accessibility · Security</b><p>This audit checks the current page only. It does not crawl the whole website, measure real-user Core Web Vitals, or replace Google Search Console / Lighthouse.</p></div>
          {seoCheckedAt && <p className="platform-audit-time">Last checked: {seoCheckedAt} · {seoResults.filter(item => item.ok).length}/{seoResults.length} checks passed</p>}
          {seoResults.length > 0 && <div className="platform-audit-grid">{seoResults.map(item => <article key={item.label}><span className={item.ok ? "audit-pass" : "audit-review"}>{item.ok ? "PASS" : "REVIEW"}</span><b>{item.label}</b><p>{item.detail}</p></article>)}</div>}
        </section>
        <section className="platform-panel" id="tickets"><div className="platform-section-title"><div><h3>Support desk</h3><p>Track issues, assign ownership and record customer communication</p></div><input value={ticketSearch} onChange={event => setTicketSearch(event.target.value)} placeholder="Search tickets…" /></div>
          <div className="platform-ticket-layout"><div className="platform-ticket-list">{filteredTickets.map(ticket => <button key={ticket.id} className={selectedTicket === ticket.id ? "selected" : ""} onClick={() => setSelectedTicket(ticket.id)}><span className={"platform-priority priority-" + ticket.priority}>{ticket.priority}</span><b>#{ticket.ticket_number} · {ticket.subject}</b><small>{companies.find(company => company.id === ticket.tenant_id)?.name || "Company"} · {ticket.status}</small><time>{dateLabel(ticket.updated_at)}</time></button>)}{!filteredTickets.length && <p className="platform-empty">No support tickets yet.</p>}</div>
            <div className="platform-ticket-detail">{activeTicket ? <><div className="platform-ticket-heading"><div><small>{companies.find(company => company.id === activeTicket.tenant_id)?.name || "Customer company"}</small><h4>{activeTicket.subject}</h4><p>{activeTicket.category} · Opened {dateLabel(activeTicket.created_at)}</p><p className="platform-sla-line">First response: {activeTicket.first_response_at ? dateLabel(activeTicket.first_response_at) : "Pending"} · SLA target: {activeTicket.sla_due_at ? dateLabel(activeTicket.sla_due_at) : "Not set"}</p></div><span className={"platform-status status-" + activeTicket.status}>{activeTicket.status}</span></div><p className="platform-ticket-description">{activeTicket.description}</p><div className="platform-ticket-controls"><label>Status<select value={activeTicket.status} onChange={event => void updateTicket({ status: event.target.value })}><option value="open">Open</option><option value="in_progress">In progress</option><option value="waiting_customer">Waiting for customer</option><option value="resolved">Resolved</option><option value="closed">Closed</option></select></label><button disabled={busy} onClick={() => void updateTicket({ assigned_to: admin.user_id })}>Assign to me</button></div><div className="platform-messages"><b>Conversation history</b>{messages.map(item => <article key={item.id}><small>{item.sender_id === admin.user_id ? "You / Support" : "Platform staff"} · {dateLabel(item.created_at)}</small><p>{item.body}</p></article>)}{!messages.length && <p className="platform-empty">No messages recorded for this case.</p>}</div>
              <div className="platform-attachment-list"><b>Attachments</b>{attachments.map(item => <button type="button" key={item.id} onClick={() => void openAttachment(item)}>{item.file_name} · {(item.file_size / 1024).toFixed(0)} KB</button>)}{!attachments.length && <small>No files attached.</small>}</div>
              <form className="platform-reply" onSubmit={sendMessage}><textarea rows={3} value={message} onChange={event => setMessage(event.target.value)} placeholder="Write a support update…" /><label className="platform-file-picker">Attach files<input type="file" multiple accept=".pdf,.jpg,.jpeg,.png,.webp,.txt" onChange={event => setAttachmentFiles(Array.from(event.target.files || []))} /></label>{attachmentFiles.length > 0 && <small>{attachmentFiles.length} file(s) selected</small>}<button disabled={busy || !message.trim()}>Send update</button></form></> : <div className="platform-empty platform-empty-detail">Select a support ticket to review its history.</div>}</div>
          </div>
        </section>
        <footer className="platform-footer">EBS PRO V.01 · Platform administration · Every action is restricted by server-side platform roles.</footer>
      </section>
    </main>
  </div>;
}
