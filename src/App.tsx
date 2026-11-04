import { FormEvent, useEffect, useState } from "react";
import { createClient, Session } from "@supabase/supabase-js";
import WorkspaceModule from "./WorkspaceModule";
import TransactionsModule from "./TransactionsModule";
import OperationsModule from "./OperationsModule";
import AdminModule from "./AdminModule";
import AccountingModule from "./AccountingModule";
import DashboardModule from "./DashboardModule";
import PricingModule from "./PricingModule";
import InvoiceModule from "./InvoiceModule";
import TransfersModule from "./TransfersModule";
import AuditModule from "./AuditModule";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
const db = url && key ? createClient(url, key) : null;

type Organization = { id: string; name: string; city: string | null; currency: string };
const nav = ["Overview","Sales","Booker App","Inventory","Purchases","Goods Receiving","Customers","Products","Distribution","Recovery","Accounts","Reports","Team & Employees","Routes","Branches & Warehouses","Price Lists","Stock Transfers","Invoices","Audit Trail","Settings"];
const roleAccess: Record<string,string[]> = {
 owner: nav, admin: nav,
 manager: ["Overview","Sales","Booker App","Inventory","Purchases","Goods Receiving","Customers","Products","Distribution","Recovery","Accounts","Reports","Routes","Price Lists","Stock Transfers","Invoices"],
 accounts: ["Overview","Recovery","Accounts","Invoices","Reports"],
 purchase: ["Overview","Purchases","Goods Receiving","Products","Inventory","Reports"],
 sales: ["Overview","Sales","Booker App","Customers","Products","Routes","Invoices","Reports"],
 order_booker: ["Overview","Booker App","Sales","Customers","Products"],
 warehouse: ["Overview","Inventory","Distribution","Goods Receiving","Stock Transfers","Products","Purchases"],
 cashier: ["Overview","Sales","Recovery","Accounts","Invoices"],
 viewer: ["Overview","Reports"]
};

export default function App() {
  const [session,setSession] = useState<Session|null>(null);
  const [loading,setLoading] = useState(true);
  const [organization,setOrganization] = useState<Organization|null>(null);
  const [currentRole,setCurrentRole] = useState("viewer");
  const [mode,setMode] = useState<"login"|"signup">("login");
  const [email,setEmail] = useState("");
  const [password,setPassword] = useState("");
  const [fullName,setFullName] = useState("");
  const [companyName,setCompanyName] = useState("");
  const [city,setCity] = useState("");
  const [active,setActive] = useState("Overview");
  const [busy,setBusy] = useState(false);
  const allowedNav = roleAccess[currentRole] || roleAccess.viewer;
  const [notice,setNotice] = useState("");

  useEffect(() => {
    if (!db) { setLoading(false); return; }
    db.auth.getSession().then(({data}) => setSession(data.session));
    const {data:{subscription}} = db.auth.onAuthStateChange((_event,next) => setSession(next));
    return () => subscription.unsubscribe();
  },[]);

  useEffect(() => {
    let live = true;
    async function load() {
      if (!db || !session) { if(live){setOrganization(null);setLoading(false);} return; }
      setLoading(true);
      const {data: memberships,error} = await db.from("tenant_memberships")
        .select("tenant_id,role").eq("user_id",session.user.id).eq("is_active",true);
      if(error){if(live)setNotice(error.message);setLoading(false);return;}
      const ids = (memberships ?? []).map(row => row.tenant_id);
      if(live)setCurrentRole((memberships?.[0]?.role as string) || "viewer");
      if(ids.length){
        const {data,error:orgError} = await db.from("organizations")
          .select("id,name,city,currency").in("id",ids).limit(1);
        if(orgError){if(live)setNotice(orgError.message);}
        if(live)setOrganization((data?.[0] as Organization|undefined) ?? null);
      } else if(live) setOrganization(null);
      if(live)setLoading(false);
    }
    void load();
    return ()=>{live=false;};
  },[session]);

  async function authenticate(e:FormEvent) {
    e.preventDefault(); if(!db)return; setBusy(true);setNotice("");
    try {
      if(mode==="signup"){
        const {data,error}=await db.auth.signUp({email,password,options:{data:{full_name:fullName},emailRedirectTo:window.location.origin}});
        if(error)throw error;
        if(!data.session)setNotice("Account created. Check your inbox and confirm your email address before signing in.");
        else setSession(data.session);
      } else {
        const {data,error}=await db.auth.signInWithPassword({email,password});
        if(error)throw error;setSession(data.session);
      }
    } catch(err){setNotice(err instanceof Error?err.message:"Login process failed.");}
    finally{setBusy(false);}
  }

  async function addOrganization(e:FormEvent) {
    e.preventDefault();if(!db)return;setBusy(true);setNotice("");
    const slug=companyName.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,50);
    try {
      const {data,error}=await db.rpc("create_tenant",{p_name:companyName.trim(),p_slug:slug,p_city:city.trim()||null,p_phone:null});
      if(error)throw error;
      const {data:org,error:readError}=await db.from("organizations").select("id,name,city,currency").eq("id",data).single();
      if(readError)throw readError;setOrganization(org as Organization);
    } catch(err){setNotice(err instanceof Error?err.message:"Company setup failed.");}
    finally{setBusy(false);}
  }

  if(!db)return <main className="center"><section className="setup"><div className="logo">E</div><h1>Connect EBS PRO</h1><p>Set the Supabase project URL and publishable key in your hosting environment:</p><code>VITE_SUPABASE_URL</code><code>VITE_SUPABASE_PUBLISHABLE_KEY</code><small>Never expose the service-role key in the browser.</small></section></main>;
  if(loading)return <main className="center"><div className="logo">E</div><p>Loading workspace…</p></main>;

  if(!session)return <main className="auth"><section className="brand"><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em></b></div><div><small>WHOLESALE · DISTRIBUTION · CONTROL</small><h1>One workspace.<br/>Complete business control.</h1><p>Sales, stock, purchasing, recovery and field order booking — connected in one place.</p></div><footer>VERSION 01 · PAKISTAN · PKR</footer></section><section className="authside"><form onSubmit={authenticate} className="form"><small>WELCOME TO EBS PRO</small><h2>{mode==="login"?"Sign in to your account":"Create your account"}</h2><p>{mode==="login"?"Access your distribution workspace.":"Register your owner account to get started."}</p>
  {mode==="signup"&&<label>Full name<input required value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Your full name"/></label>}
  <label>Email address<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@company.com"/></label>
  <label>Password<input type="password" minLength={8} required value={password} onChange={e=>setPassword(e.target.value)} placeholder="At least 8 characters"/></label>
  {notice&&<div className="notice">{notice}</div>}<button disabled={busy}>{busy?"Please wait…":mode==="login"?"Sign in":"Create account"} <span>→</span></button>
  <div className="switch">{mode==="login"?"New to EBS PRO?":"Already registered?"} <a onClick={()=>{setMode(mode==="login"?"signup":"login");setNotice("");}}>{mode==="login"?"Create account":"Sign in"}</a></div></form></section></main>;

  if(!organization)return <main className="center"><form className="setup" onSubmit={addOrganization}><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em></b></div><small>COMPANY SETUP</small><h1>Create your business workspace</h1><p>Enter your company name and city. You will be the owner, and the Main Branch will be created automatically.</p><label>Company name<input required minLength={2} value={companyName} onChange={e=>setCompanyName(e.target.value)} placeholder="ABC Distributors"/></label><label>City<input value={city} onChange={e=>setCity(e.target.value)} placeholder="Rawalpindi"/></label>{notice&&<div className="notice">{notice}</div>}<button disabled={busy}>{busy?"Creating…":"Create company"} <span>→</span></button><a className="signout" onClick={()=>void db.auth.signOut()}>Sign out</a></form></main>;

  const moduleContent = !allowedNav.includes(active)
    ? <><h2>Access restricted</h2><p>Your assigned role ({currentRole.replaceAll("_"," ")}) does not have permission to open this module. Contact your company administrator.</p></>
    : active === "Sales" || active === "Purchases"
      ? <TransactionsModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
      : active === "Accounts"
        ? <AccountingModule db={db} tenantId={organization.id} />
        : active === "Price Lists"
          ? <PricingModule db={db} tenantId={organization.id} />
        : active === "Invoices"
          ? <InvoiceModule db={db} tenantId={organization.id} />
        : active === "Stock Transfers"
          ? <TransfersModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Audit Trail"
          ? <AuditModule db={db} tenantId={organization.id} />
        : ["Inventory","Distribution","Recovery","Reports","Goods Receiving"].includes(active)
          ? <OperationsModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
          : ["Team & Employees","Routes","Branches & Warehouses","Booker App","Settings"].includes(active)
            ? <AdminModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
            : active !== "Overview"
              ? <WorkspaceModule db={db} tenantId={organization.id} module={active} />
              : <DashboardModule db={db} tenantId={organization.id} company={organization.name} onNavigate={setActive} />;

  return <div className="shell"><aside className="sidebar"><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em><small>V.01</small></b></div><div className="org"><strong>{organization.name}</strong><small>{organization.city||"Pakistan"} · {organization.currency}</small></div><small className="caption">WORKSPACE</small><nav>{nav.filter(item=>allowedNav.includes(item)).map((item,i)=><button className={active===item?"selected":""} key={item} onClick={()=>setActive(item)}><span>{["⌂","▤","◉","▦","⇩","♙","▣","➜","₨","∑","▥","⚙"][i]}</span>{item}</button>)}</nav><div className="account"><b>{session.user.email}</b><button onClick={()=>void db.auth.signOut()}>Sign out ↗</button></div></aside><main className="main"><header><span>EBS PRO / <b>{active}</b></span><span className="live">● {currentRole.replaceAll("_"," ").toUpperCase()} ACCESS</span></header><section className="content">{moduleContent}</section></main></div>;
}
