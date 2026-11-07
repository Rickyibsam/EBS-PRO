import { resolveAllowedNavigation } from "./lib/erpAccess";
import {ModulePermissionProvider,type ModuleActionPermission} from "./lib/modulePermissionContext";
import { FormEvent, lazy, Suspense, useEffect, useState } from "react";
import { createClient, Session } from "@supabase/supabase-js";
const WorkspaceModule = lazy(() => import("./WorkspaceModule"));
const UserPermissionsModule = lazy(() => import("./UserPermissionsModule"));
const TransactionsModule = lazy(() => import("./TransactionsModule"));
const OperationsModule = lazy(() => import("./OperationsModule"));
const AdminModule = lazy(() => import("./AdminModule"));
const BookerOrderModule = lazy(() => import("./BookerOrderModule"));
const AccountingModule = lazy(() => import("./AccountingModule"));
const ReturnsModule = lazy(() => import("./ReturnsModule"));
const DashboardModule = lazy(() => import("./DashboardModule"));
const PricingModule = lazy(() => import("./PricingModule"));
const InvoiceModule = lazy(() => import("./InvoiceModule"));
const TransfersModule = lazy(() => import("./TransfersModule"));
const AuditModule = lazy(() => import("./AuditModule"));
const VendorCatalogModule = lazy(() => import("./VendorCatalogModule"));
const PayrollModule = lazy(() => import("./PayrollModule"));
const TargetsModule = lazy(() => import("./TargetsModule"));
const PurchaseInvoiceModule = lazy(() => import("./PurchaseInvoiceModule"));
const PurchaseReturnsModule = lazy(() => import("./PurchaseReturnsModule"));
const DeliveryManModule = lazy(() => import("./DeliveryManModule"));
const BankReconciliationModule = lazy(() => import("./BankReconciliationModule"));
const VendorReconciliationModule = lazy(() => import("./VendorReconciliationModule"));
const ChequeRegisterModule = lazy(() => import("./ChequeRegisterModule"));
const CustomerCreditControlModule = lazy(() => import("./CustomerCreditControlModule"));
const TaxRegisterModule = lazy(() => import("./TaxRegisterModule"));
const BatchExpiryModule = lazy(() => import("./BatchExpiryModule"));
const AssetBudgetModule = lazy(() => import("./AssetBudgetModule"));
const VanStockModule = lazy(() => import("./VanStockModule"));
const StockTakeModule = lazy(() => import("./StockTakeModule"));
const HRModule = lazy(() => import("./HRModule"));
const DeliveryChargeModule = lazy(() => import("./DeliveryChargeModule"));
const LoginHistoryModule = lazy(() => import("./LoginHistoryModule"));
const BackupRestoreModule = lazy(() => import("./BackupRestoreModule"));
const VoucherHistoryModule = lazy(() => import("./VoucherHistoryModule"));

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
const db = url && key ? createClient(url, key) : null;

type Organization = { id: string; name: string; city: string | null; currency: string };
const nav = ["Overview","User Permissions","Sales","Booker App","Delivery Man App","Inventory","Batch & Expiry","Stock Take","Van Stock","Purchases","Goods Receiving","Vendor Invoices","Purchase Returns","Customers","Vendors","Products","Distribution","Delivery Charges","Recovery","Customer Credit Control","Accounts","Reports","Team & Employees","HR & Attendance","Login History","Routes","Branches & Warehouses","Price Lists","Stock Transfers","Invoices","Sales Returns","Vendor Feeding","Payroll","Asset & Budget Control","Bank Reconciliation","Vendor Statement Reconciliation","Cheque Register","Tax Register","Voucher Revision History","Audit Trail","Booker Product Access","Targets & Incentives","Settings","Backup & Restore"];
const navGroups = [
 {name:"1. Dashboard & Management",icon:"✦",items:["Overview"]},
 {name:"2. Sales & Customer Management",icon:"◈",items:["Sales","Customers","Invoices","Sales Returns","Customer Credit Control","Recovery","Price Lists"]},
 {name:"3. Order Booking App",icon:"▣",items:["Booker App","Booker Product Access"]},
 {name:"4. Inventory & Warehouse",icon:"▦",items:["Inventory","Products","Batch & Expiry","Stock Take","Van Stock","Stock Transfers","Branches & Warehouses"]},
 {name:"5. Purchase & Supplier Management",icon:"⇩",items:["Purchases","Goods Receiving","Vendor Invoices","Purchase Returns","Vendors","Vendor Feeding"]},
 {name:"6. Accounts & Finance",icon:"◉",items:["Accounts","Bank Reconciliation","Vendor Statement Reconciliation","Cheque Register","Tax Register","Asset & Budget Control"]},
 {name:"7. Distribution & Delivery",icon:"⌖",items:["Delivery Man App","Distribution","Delivery Charges","Routes"]},
 {name:"8. HR & Payroll",icon:"♙",items:["Team & Employees","HR & Attendance","Payroll"]},
 {name:"9. Reports & Analytics",icon:"▤",items:["Reports","Targets & Incentives"]},
 {name:"10. Administration & Security",icon:"⚙",items:["User Permissions","Login History","Settings","Backup & Restore","Voucher Revision History","Audit Trail"]}
];
const roleAccess: Record<string,string[]> = {
 owner: nav, admin: nav.filter(item=>item!=="User Permissions"),
 manager: ["Overview","Sales","Booker App","Inventory","Batch & Expiry","Stock Take","Van Stock","Purchases","Goods Receiving","Vendor Invoices","Purchase Returns","Customers","Vendors","Products","Distribution","Delivery Charges","Recovery","Customer Credit Control","Accounts","Reports","Routes","Price Lists","Stock Transfers","Invoices","Sales Returns","Vendor Feeding","Payroll","Asset & Budget Control","HR & Attendance","Login History","Booker Product Access","Targets & Incentives"],
 accounts: ["Overview","Recovery","Accounts","Invoices","Vendor Invoices","Purchase Returns","Sales Returns","Payroll","Asset & Budget Control","Bank Reconciliation","Vendor Statement Reconciliation","Cheque Register","Tax Register","Voucher Revision History","Customer Credit Control","Reports"],
 purchase: ["Overview","Purchases","Goods Receiving","Vendor Invoices","Purchase Returns","Vendors","Products","Inventory","Vendor Feeding","Reports"],
 sales: ["Overview","Sales","Booker App","Customers","Products","Routes","Invoices","Sales Returns","Reports","Booker Product Access","Targets & Incentives"],
 order_booker: ["Overview","Booker App","Sales","Customers","Products","HR & Attendance"],
 warehouse: ["Overview","Inventory","Batch & Expiry","Stock Take","Van Stock","Distribution","Delivery Charges","Goods Receiving","Stock Transfers","Products","Purchases"],
 cashier: ["Overview","Sales","Invoices"],
 delivery_man: ["Overview","Delivery Man App","Delivery Charges","HR & Attendance"],
 viewer: ["Overview","Reports"]
};

const isStrongPassword=(value:string)=>value.length>=12&&/[a-z]/.test(value)&&/[A-Z]/.test(value)&&/\d/.test(value)&&/[^A-Za-z0-9]/.test(value);

export default function App() {
  const [session,setSession] = useState<Session|null>(null);
  const [loading,setLoading] = useState(true);
  const [organization,setOrganization] = useState<Organization|null>(null);
  const [tenantChoices,setTenantChoices] = useState<Array<Organization & {role:string}>>([]);
  const [currentRole,setCurrentRole] = useState("viewer");
  const [modulePermissions,setModulePermissions] = useState<Record<string,boolean>>({});
  const [moduleActionPermissions,setModuleActionPermissions] = useState<Record<string,ModuleActionPermission>>({});
  const [mode,setMode] = useState<"login"|"signup">("login");
  const [recoveryMode,setRecoveryMode] = useState(false);
  const [authEvent,setAuthEvent] = useState("");
  const [email,setEmail] = useState("");
  const [password,setPassword] = useState("");
  const [fullName,setFullName] = useState("");
  const [companyName,setCompanyName] = useState("");
  const [city,setCity] = useState("");
  const [active,setActive] = useState(()=>{const app=new URLSearchParams(window.location.search).get("app");return app==="booker"?"Booker App":app==="delivery"?"Delivery Man App":"Overview";});
  const [expandedGroup,setExpandedGroup] = useState(()=>{const app=new URLSearchParams(window.location.search).get("app");const initial=app==="booker"?"Booker App":app==="delivery"?"Delivery Man App":"Overview";return navGroups.find(g=>g.items.includes(initial))?.name||"Overview";});
  const [busy,setBusy] = useState(false);
  const allowedNav = resolveAllowedNavigation(currentRole,nav,roleAccess,navGroups,modulePermissions);
  const [notice,setNotice] = useState("");
  useEffect(()=>{const group=navGroups.find(item=>item.items.includes(active));if(group)setExpandedGroup(group.name);},[active]);

  useEffect(()=>{
    let live=true;
    async function loadOverrides(){
      if(live){setModulePermissions({});setModuleActionPermissions({});}
      if(!db||!session||!organization||["owner","admin"].includes(currentRole)){if(live){setModulePermissions({});setModuleActionPermissions({});}return;}
      const {data,error}=await db.from("tenant_user_module_permissions").select("module_key,can_view,can_create,can_update,can_delete").eq("tenant_id",organization.id).eq("user_id",session.user.id);
      if(!live)return;
      if(error){setNotice("Could not load individual module permissions: "+error.message);setModulePermissions({});setModuleActionPermissions({});return;}
      setModulePermissions(Object.fromEntries((data||[]).map(row=>[row.module_key,Boolean(row.can_view)])));
      setModuleActionPermissions(Object.fromEntries((data||[]).map(row=>[row.module_key,{can_view:Boolean(row.can_view),can_create:Boolean(row.can_create),can_update:Boolean(row.can_update),can_delete:Boolean(row.can_delete)}])));
    }
    void loadOverrides();
    return()=>{live=false;};
  },[organization?.id,session?.user.id,currentRole]);

  useEffect(() => {
    if (!db) { setLoading(false); return; }
    db.auth.getSession().then(({data}) => setSession(data.session));
    const {data:{subscription}} = db.auth.onAuthStateChange((event,next) => {setAuthEvent(event);if(event==="PASSWORD_RECOVERY")setRecoveryMode(true);setSession(next);});
    return () => subscription.unsubscribe();
  },[]);

  useEffect(()=>{if(db&&session&&["SIGNED_IN","INITIAL_SESSION"].includes(authEvent)){void db.rpc("record_login_history",{p_user_agent:typeof navigator!=="undefined"?navigator.userAgent.slice(0,500):""});}},[session?.user.id,authEvent]);

  useEffect(() => {
    let live = true;
    async function load() {
      if (!db || !session) { if(live){setOrganization(null);setLoading(false);} return; }
      setLoading(true);
      const {data: memberships,error} = await db.from("tenant_memberships")
        .select("tenant_id,role").eq("user_id",session.user.id).eq("is_active",true);
      if(error){if(live)setNotice(error.message);setLoading(false);return;}
      const ids = (memberships ?? []).map(row => row.tenant_id);
      if(ids.length){
        const {data,error:orgError} = await db.from("organizations")
          .select("id,name,city,currency").in("id",ids).order("name");
        if(orgError){if(live)setNotice(orgError.message);}
        const choices=(data??[]).map(org=>({...org,role:String(memberships?.find(m=>m.tenant_id===org.id)?.role||"viewer")}));
        if(live){setTenantChoices(choices);setOrganization(choices[0]??null);setCurrentRole(choices[0]?.role??"viewer");}
      } else if(live){setOrganization(null);setTenantChoices([]);setCurrentRole("viewer");}
      if(live)setLoading(false);
    }
    void load();
    return ()=>{live=false;};
  },[session]);

  async function authenticate(e:FormEvent) {
    e.preventDefault(); if(!db)return; if((recoveryMode||mode==="signup")&&!isStrongPassword(password)){setNotice("Use at least 12 characters with uppercase, lowercase, a number and a symbol.");return;} setBusy(true);setNotice("");
    try {
      if(recoveryMode){const {error}=await db.auth.updateUser({password});if(error)throw error;await db.auth.signOut();setRecoveryMode(false);setPassword("");setNotice("Password updated successfully. Sign in with your new password.");return;}
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

  async function sendPasswordReset(){
    if(!db)return;
    if(!email.trim()){setNotice("Enter your account email address first.");return;}
    setBusy(true);setNotice("");
    try{const {error}=await db.auth.resetPasswordForEmail(email.trim(),{redirectTo:window.location.origin});if(error)throw error;setNotice("Password recovery email sent. Open the link in that email on this device to set a new password.");}
    catch(err){setNotice(err instanceof Error?err.message:"Password recovery email could not be sent.");}
    finally{setBusy(false);}
  }

  async function addOrganization(e:FormEvent) {
    e.preventDefault();if(!db)return;setBusy(true);setNotice("");
    const slug=companyName.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,50);
    try {
      const {data,error}=await db.rpc("create_tenant",{p_name:companyName.trim(),p_slug:slug,p_city:city.trim()||null,p_phone:null});
      if(error)throw error;
      const {data:org,error:readError}=await db.from("organizations").select("id,name,city,currency").eq("id",data).single();
      if(readError)throw readError;setOrganization(org as Organization);setTenantChoices([{...(org as Organization),role:"owner"}]);setCurrentRole("owner");
    } catch(err){setNotice(err instanceof Error?err.message:"Company setup failed.");}
    finally{setBusy(false);}
  }

  if(!db)return <main className="center"><section className="setup"><div className="logo">E</div><h1>Connect EBS PRO</h1><p>Set the Supabase project URL and publishable key in your hosting environment:</p><code>VITE_SUPABASE_URL</code><code>VITE_SUPABASE_PUBLISHABLE_KEY</code><small>Never expose the service-role key in the browser.</small></section></main>;
  if(loading)return <main className="center"><div className="logo">E</div><p>Loading workspace…</p></main>;

  if(recoveryMode) return <main className="auth"><section className="brand"><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em></b></div><div><small>ACCOUNT SECURITY</small><h1>Secure your workspace.</h1><p>Choose a new password for your EBS PRO account.</p></div><footer>VERSION 01 · PAKISTAN · PKR</footer></section><section className="authside"><form onSubmit={authenticate} className="form"><small>RESET PASSWORD</small><h2>Set a new password</h2><p>Use at least 12 characters with uppercase, lowercase, a number and a symbol.</p><label>New password<input type="password" minLength={12} required value={password} onChange={e=>setPassword(e.target.value)} placeholder="Strong new password"/></label>{notice&&<div className="notice">{notice}</div>}<button disabled={busy}>{busy?"Updating…":"Update password"} <span>→</span></button></form></section></main>;
  if(!session)return <main className="auth"><section className="brand"><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em></b></div><div><small>WHOLESALE · DISTRIBUTION · CONTROL</small><h1>One workspace.<br/>Complete business control.</h1><p>Sales, stock, purchasing, recovery and field order booking — connected in one place.</p></div><footer>VERSION 01 · PAKISTAN · PKR</footer></section><section className="authside"><form onSubmit={authenticate} className="form"><small>WELCOME TO EBS PRO</small><h2>{mode==="login"?"Sign in to your account":"Create your account"}</h2><p>{mode==="login"?"Access your distribution workspace.":"Register your owner account to get started."}</p>
  {mode==="signup"&&<label>Full name<input required value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Your full name"/></label>}
  <label>Email address<input type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@company.com"/></label>
  <label>Password<input type="password" minLength={mode==="signup"?12:1} required value={password} onChange={e=>setPassword(e.target.value)} placeholder={mode==="signup"?"12+ chars · upper/lower · number · symbol":"Your password"}/></label>{mode==="signup"&&<p className="password-hint">12+ characters, uppercase and lowercase letters, a number and a symbol.</p>}
  {mode==="login"&&<div className="switch"><a onClick={()=>void sendPasswordReset()}>Forgot password?</a></div>}
  {notice&&<div className="notice">{notice}</div>}<button disabled={busy}>{busy?"Please wait…":mode==="login"?"Sign in":"Create account"} <span>→</span></button>
  <div className="switch">{mode==="login"?"New to EBS PRO?":"Already registered?"} <a onClick={()=>{setMode(mode==="login"?"signup":"login");setNotice("");}}>{mode==="login"?"Create account":"Sign in"}</a></div></form></section></main>;

  if(!organization)return <main className="center"><form className="setup" onSubmit={addOrganization}><div className="brandline"><div className="logo">E</div><b>EBS <em>PRO</em></b></div><small>COMPANY SETUP</small><h1>Create your business workspace</h1><p>Enter your company name and city. You will be the owner, and the Main Branch will be created automatically.</p><label>Company name<input required minLength={2} value={companyName} onChange={e=>setCompanyName(e.target.value)} placeholder="ABC Distributors"/></label><label>City<input value={city} onChange={e=>setCity(e.target.value)} placeholder="Rawalpindi"/></label>{notice&&<div className="notice">{notice}</div>}<button disabled={busy}>{busy?"Creating…":"Create company"} <span>→</span></button><a className="signout" onClick={()=>void db.auth.signOut()}>Sign out</a></form></main>;

  const moduleContent = !allowedNav.includes(active)
    ? <><h2>Access restricted</h2><p>Your assigned role ({currentRole.replaceAll("_"," ")}) does not have permission to open this module. Contact your company administrator.</p></>
    : active === "Sales" || active === "Purchases"
      ? <TransactionsModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
      : active === "Accounts"
        ? <AccountingModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Sales Returns"
          ? <ReturnsModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Price Lists"
          ? <PricingModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Invoices"
          ? <InvoiceModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Stock Transfers"
          ? <TransfersModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Purchase Returns"
          ? <PurchaseReturnsModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Vendor Invoices"
          ? <PurchaseInvoiceModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Targets & Incentives"
          ? <TargetsModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Payroll"
          ? <PayrollModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Bank Reconciliation"
          ? <BankReconciliationModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Vendor Statement Reconciliation"
          ? <VendorReconciliationModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Cheque Register"
          ? <ChequeRegisterModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Customer Credit Control"
          ? <CustomerCreditControlModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Tax Register"
          ? <TaxRegisterModule db={db} tenantId={organization.id} />
        : active === "Batch & Expiry"
          ? <BatchExpiryModule db={db} tenantId={organization.id} />
        : active === "Stock Take"
          ? <StockTakeModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "HR & Attendance"
          ? <HRModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Delivery Charges"
          ? <DeliveryChargeModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Login History"
          ? <LoginHistoryModule db={db} tenantId={organization.id} />
        : active === "Backup & Restore"
          ? <BackupRestoreModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Asset & Budget Control"
          ? <AssetBudgetModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Van Stock"
          ? <VanStockModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Voucher Revision History"
          ? <VoucherHistoryModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Vendor Feeding"
          ? <VendorCatalogModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : active === "Audit Trail"
          ? <AuditModule db={db} tenantId={organization.id} />
        : active === "User Permissions"
          ? <UserPermissionsModule db={db} tenantId={organization.id} currentRole={currentRole} />
        : ["Inventory","Distribution","Recovery","Reports","Goods Receiving"].includes(active)
          ? <OperationsModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
          : active === "Booker App" && currentRole === "order_booker"
            ? <BookerOrderModule db={db} tenantId={organization.id} />
        : active === "Delivery Man App"
          ? currentRole === "delivery_man"
            ? <DeliveryManModule db={db} tenantId={organization.id} />
            : <section className="module-page"><div className="module-toolbar"><div><h2>Delivery Man App</h2><p>This mobile workflow is for users assigned the Delivery Man role. Office staff can assign and monitor deliveries in Distribution, and manage deliveryman accounts in Team & Employees.</p></div><div className="table-tools"><button onClick={() => setActive("Distribution")}>Open Distribution</button><button onClick={() => setActive("Team & Employees")}>Manage delivery staff</button></div></div></section>
        : ["Team & Employees","Routes","Branches & Warehouses","Booker App","Booker Product Access","Settings"].includes(active)
            ? <AdminModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
        : ["Products","Customers","Vendors"].includes(active)
            ? <WorkspaceModule db={db} tenantId={organization.id} module={active} currentRole={currentRole} />
            : active !== "Overview"
              ? <section className="module-empty"><h2>Module route unavailable</h2><p>This navigation item has no assigned workflow component. Please contact the system administrator.</p></section>
              : <DashboardModule db={db} tenantId={organization.id} company={organization.name} allowedModules={allowedNav} onNavigate={setActive} />;

  const renderNavigationGroups=(groups:typeof navGroups)=>groups.map(group=>{const items=group.items.filter(item=>allowedNav.includes(item));if(!items.length)return null;const opened=expandedGroup===group.name;const hasActive=items.includes(active);return <div className="landscape-nav-group" key={group.name}><button className={"landscape-nav-trigger"+(hasActive?" has-active":"")+(opened?" is-open":"")} aria-expanded={opened} onClick={()=>setExpandedGroup(opened?"":group.name)}><span className="landscape-nav-icon">{group.icon}</span><b>{group.name.replace(/^\d+\.\s*/,"")}</b><span className="landscape-caret">⌄</span></button>{opened&&<div className="landscape-dropdown"><div className="dropdown-heading"><span>{group.icon}</span><div><b>{group.name.replace(/^\d+\.\s*/,"")}</b><small>{items.length} available workspaces</small></div></div><div className="dropdown-links">{items.map(item=><button className={active===item?"selected":""} key={item} onClick={()=>{setActive(item);setExpandedGroup("");}}>{item}<span>→</span></button>)}</div></div>}</div>});

  return <div className="shell landscape-shell">
    <div className="workspace-topbar">
      <div className="topbar-brand"><div className="logo">E</div><div><b>EBS <em>PRO</em></b><small>V.01 · DISTRIBUTION ERP</small></div></div>
      <div className="topbar-company"><strong>{organization.name}</strong><small>{organization.city||"Pakistan"} · {organization.currency}</small>{tenantChoices.length>1&&<select aria-label="Switch company workspace" value={organization.id} onChange={e=>{const choice=tenantChoices.find(x=>x.id===e.target.value);if(choice){setOrganization(choice);setCurrentRole(choice.role);setActive("Overview");setExpandedGroup(navGroups[0].name);}}}>{tenantChoices.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select>}</div>
      <div className="topbar-user"><span className="topbar-role">● {currentRole.replaceAll("_"," ").toUpperCase()}</span><span className="topbar-email">{session.user.email}</span><button onClick={()=>void db.auth.signOut()}>Sign out ↗</button></div>
    </div>
    <nav className="landscape-nav" aria-label="ERP modules">
      <button className={"landscape-home"+(active==="Overview"?" active":"")} onClick={()=>{setActive("Overview");setExpandedGroup("");}}><span>⌂</span> Dashboard</button>
      <div className="landscape-nav-rows">
        <div className="landscape-nav-items landscape-nav-row" aria-label="Primary modules">{renderNavigationGroups(navGroups.slice(0,5))}</div>
        <div className="landscape-nav-items landscape-nav-row" aria-label="Finance and administration modules">{renderNavigationGroups(navGroups.slice(5))}</div>
      </div>
      <div className="landscape-nav-end"><span>● LIVE</span></div>
    </nav>
    <main className="main landscape-main">
      <header><span>EBS PRO <i>/</i> <b>{active}</b></span><span className="live">● {currentRole.replaceAll("_"," ").toUpperCase()} ACCESS</span></header>
      <section className="content"><ModulePermissionProvider permissions={moduleActionPermissions}><Suspense fallback={<div className="table-empty">Loading module…</div>}>{moduleContent}</Suspense></ModulePermissionProvider></section>
    </main>
  </div>;
}
