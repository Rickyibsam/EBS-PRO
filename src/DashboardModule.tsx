import {useEffect,useMemo,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Metric={label:string;value:string;detail:string;icon:string;tone:string};
const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{maximumFractionDigits:0});
const localDate=(d:Date)=>[d.getFullYear(),String(d.getMonth()+1).padStart(2,"0"),String(d.getDate()).padStart(2,"0")].join("-");
const launchers=[
 {title:"1. Dashboard & Management",description:"Owner overview, business KPIs, alerts and activity monitoring",icon:"✦",modules:["Overview","Reports","Audit Trail","Login History"]},
 {title:"2. Sales & Customer Management",description:"Customer accounts, orders, invoicing, returns and credit control",icon:"◈",modules:["Sales","Customers","Invoices","Sales Returns","Customer Credit Control","Recovery","Price Lists"]},
 {title:"3. Order Booking App",description:"Salesman booking, customer visits, product access and incentives",icon:"▣",modules:["Booker App","Booker Product Access","Targets & Incentives"]},
 {title:"4. Inventory & Warehouse",description:"Product masters, stock, batches, expiry, transfers and stock takes",icon:"▦",modules:["Inventory","Products","Batch & Expiry","Stock Take","Van Stock","Stock Transfers","Branches & Warehouses"]},
 {title:"5. Purchase & Supplier Management",description:"Supplier accounts, purchasing, goods receiving and returns",icon:"⇩",modules:["Purchases","Vendors","Goods Receiving","Vendor Invoices","Purchase Returns","Vendor Feeding"]},
 {title:"6. Accounts & Finance",description:"General ledger, cash/bank, reconciliation, assets and budgets",icon:"◉",modules:["Accounts","Bank Reconciliation","Vendor Statement Reconciliation","Cheque Register","Tax Register","Asset & Budget Control"]},
 {title:"7. Distribution & Delivery",description:"Delivery assignments, route operations, drivers and charges",icon:"⌖",modules:["Delivery Man App","Distribution","Delivery Charges","Routes"]},
 {title:"8. HR & Payroll",description:"Employee records, attendance, leave, payroll and commissions",icon:"♙",modules:["Team & Employees","HR & Attendance","Payroll","Targets & Incentives"]},
 {title:"9. Reports & Analytics",description:"Sales, purchase, stock, recovery, profitability and audit reports",icon:"▤",modules:["Reports","Targets & Incentives","Audit Trail"]},
 {title:"10. Administration & Security",description:"User access, roles, login history, settings and voucher controls",icon:"⚙",modules:["Team & Employees","Login History","Settings","Voucher Revision History","Audit Trail"]}
];
export default function DashboardModule({db,tenantId,company,allowedModules,onNavigate}:{db:SupabaseClient;tenantId:string;company:string;allowedModules:string[];onNavigate:(module:string)=>void}){
 const [metrics,setMetrics]=useState<Metric[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const [updatedAt,setUpdatedAt]=useState("");
 const [expandedLauncher,setExpandedLauncher]=useState("1. Dashboard & Management");
 useEffect(()=>{let live=true;async function load(){setLoading(true);setError("");try{
  const now=new Date(),today=localDate(now),since=new Date(now.getTime()-24*60*60*1000).toISOString(),monthStart=localDate(new Date(now.getFullYear(),now.getMonth(),1)),weekStartDate=new Date(now);weekStartDate.setDate(now.getDate()-((now.getDay()+6)%7));const weekStart=localDate(weekStartDate);
  const [sales,salesPeriod,orders,purchases,purchaseInvoices,products,customers,vendors,receipts,deliveries,lowStock,activity,inventoryValuation,coa,journalLines]=await Promise.all([
   db.from("sales_invoices").select("id,grand_total,status,invoice_date",{count:"exact"}).eq("tenant_id",tenantId).eq("invoice_date",today).eq("status","posted"),
   db.from("sales_invoices").select("grand_total,invoice_date").eq("tenant_id",tenantId).eq("status","posted").gte("invoice_date",monthStart).lte("invoice_date",today),
   db.from("sales_orders").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("status",["draft","submitted","approved","allocated"]),
   db.from("purchase_orders").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId),
   db.from("purchase_invoices").select("id,grand_total,status,invoice_date",{count:"exact"}).eq("tenant_id",tenantId).eq("invoice_date",today).eq("status","posted"),
   db.from("products").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).eq("is_active",true),
   db.from("parties").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("party_type",["customer","both"]).eq("status","active"),
   db.from("parties").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("party_type",["supplier","both"]).eq("status","active"),
   db.from("payments").select("amount,payment_type").eq("tenant_id",tenantId).eq("payment_date",today),
   db.from("deliveries").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("status",["pending","picked","dispatched"]),
   db.rpc("get_low_stock_alerts",{p_tenant_id:tenantId}),
   db.from("audit_logs").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).gte("created_at",since),
   db.rpc("get_inventory_valuation",{p_tenant_id:tenantId}),
   db.from("chart_of_accounts").select("id,account_type").eq("tenant_id",tenantId),
   db.from("journal_lines").select("account_id,debit,credit,journal_entries!inner(entry_date,status)").eq("tenant_id",tenantId).eq("journal_entries.status","posted").eq("journal_entries.entry_date",today)
  ]);
  const err=[sales,orders,purchases,purchaseInvoices,products,customers,vendors,receipts,deliveries].find(x=>x.error);if(err)throw err.error;
  const daySales=(sales.data??[]).reduce((s,x)=>s+Number(x.grand_total||0),0);
  const weekSales=(salesPeriod.data??[]).filter(x=>x.invoice_date>=weekStart).reduce((s,x)=>s+Number(x.grand_total||0),0);
  const monthSales=(salesPeriod.data??[]).reduce((s,x)=>s+Number(x.grand_total||0),0);
  const dayReceipts=(receipts.data??[]).filter(x=>x.payment_type==="receipt").reduce((s,x)=>s+Number(x.amount||0),0);
  const dayPurchases=(purchaseInvoices.data??[]).reduce((s,x)=>s+Number(x.grand_total||0),0);
  const accountTypes=new Map((coa.data??[]).map(x=>[x.id,x.account_type]));
  const netProfit=(journalLines.data??[]).reduce((sum,x)=>{const type=accountTypes.get(x.account_id);return sum+(type==="income"?Number(x.credit||0)-Number(x.debit||0):type==="expense"?Number(x.debit||0)-Number(x.credit||0):0);},0);
  const stockValue=inventoryValuation.error?null:Number(inventoryValuation.data?.total_value||0),profitValue=coa.error||journalLines.error?null:netProfit;
  const lowCount=lowStock.error?null:(lowStock.data||[]).length,activityCount=activity.error?null:(activity.count??0);
  const next:Metric[]=[
   {label:"Sales today",value:money(daySales),detail:(sales.count??0)+" posted invoices",icon:"↗",tone:"mint"},
   {label:"Sales this week",value:money(weekSales),detail:"Monday-to-date · posted invoices",icon:"◷",tone:"blue"},
   {label:"Sales this month",value:money(monthSales),detail:"Month-to-date · posted invoices",icon:"▤",tone:"violet"},
   {label:"Open sales orders",value:String(orders.count??0),detail:"Awaiting next workflow step",icon:"▤",tone:"blue"},
   {label:"Pending deliveries",value:String(deliveries.count??0),detail:"Pending, picked or dispatched",icon:"⌖",tone:"amber"},
   {label:"Receipts today",value:money(dayReceipts),detail:"Customer receipts recorded",icon:"₨",tone:"violet"},
   {label:"Low stock alerts",value:lowCount===null?"—":String(lowCount),detail:lowCount===null?"Not available for this role":"At or below reorder threshold",icon:"!",tone:"amber"},
   {label:"Purchases today",value:money(dayPurchases),detail:(purchaseInvoices.count??0)+" posted supplier invoices",icon:"⇩",tone:"blue"},
   {label:"Purchase orders",value:String(purchases.count??0),detail:"Purchase documents",icon:"▱",tone:"blue"},
   {label:"Stock value",value:stockValue===null?"—":money(stockValue),detail:"Warehouse and van ledger valuation",icon:"▦",tone:"mint"},
   {label:"Net profit today",value:profitValue===null?"—":money(profitValue),detail:"Posted GL income less expenses",icon:"✧",tone:"violet"},
   {label:"Active products",value:String(products.count??0),detail:"Product master records",icon:"▦",tone:"mint"},
   {label:"Customers",value:String(customers.count??0),detail:"Active customer accounts",icon:"♙",tone:"violet"},
   {label:"Vendors",value:String(vendors.count??0),detail:"Active supplier accounts",icon:"⌂",tone:"amber"},
   {label:"Activity (24h)",value:activityCount===null?"—":String(activityCount),detail:activityCount===null?"Not available for this role":"Recorded audit events",icon:"◷",tone:"blue"}
  ];
  if(live){setMetrics(next);setUpdatedAt(now.toLocaleTimeString("en-PK",{hour:"2-digit",minute:"2-digit"}));}
 }catch(e){if(live)setError(e instanceof Error?e.message:"Dashboard could not load.");}finally{if(live)setLoading(false);}}
 void load();return()=>{live=false;};
 },[db,tenantId]);
 const openOrders=Number(metrics.find(x=>x.label==="Open sales orders")?.value||0),pending=Number(metrics.find(x=>x.label==="Pending deliveries")?.value||0),low=Number(metrics.find(x=>x.label==="Low stock alerts")?.value||0);
 const pulse=useMemo(()=>low>0?low+" products are at or below their reorder threshold. Review replenishment before accepting more orders.":pending>0?pending+" deliveries are in the dispatch pipeline. Review assignments and proof of delivery.":openOrders>0?openOrders+" sales orders are waiting for the next processing step.":"Your current stock, sales and delivery indicators show no urgent queue.",[low,pending,openOrders]);
 const hour=new Date().getHours(),greeting=hour<12?"Good morning":hour<17?"Good afternoon":"Good evening";
 return <section className="ai-dashboard">
  <div className="dashboard-hero"><div className="hero-orb hero-orb-one"/><div className="hero-orb hero-orb-two"/><div className="hero-copy"><span className="hero-eyebrow"><i/> EBS PRO INTELLIGENCE · V.01</span><h1>{greeting}, welcome back.</h1><p>Your {company} workspace at a glance. Monitor operations, spot priorities and move directly into the next task.</p><div className="hero-meta"><span>◷ {new Date().toLocaleDateString("en-PK",{weekday:"long",day:"2-digit",month:"long",year:"numeric"})}</span><span>● Live workspace</span>{updatedAt&&<span>Updated {updatedAt}</span>}</div></div><div className="hero-mark"><div className="hero-mark-inner">E<span>AI</span></div><small>BUSINESS PULSE</small></div></div>
  <div className="dashboard-section-head"><div><span className="section-kicker">LIVE PERFORMANCE</span><h2>Business snapshot</h2><p>Posted invoices, open workflows and current stock signals</p></div><button className="dashboard-refresh" onClick={()=>window.location.reload()}>↻ Refresh view</button></div>
  {error&&<div className="notice">{error}</div>}
  {loading?<div className="dashboard-loading"><span className="loading-pulse"/> Reading live business data…</div>:<div className="ai-metric-grid">{metrics.map(m=><article className="ai-metric" key={m.label}><div className={"metric-icon "+m.tone}>{m.icon}</div><div className="metric-label">{m.label}</div><strong>{m.value}</strong><small>{m.detail}</small><span className="metric-glow"/></article>)}</div>}
  <div className="dashboard-lower"><article className="pulse-card"><div className="pulse-heading"><span className="pulse-spark">✦</span><div><small>SMART BUSINESS PULSE</small><h3>Operations insight</h3></div><span className="pulse-live">LIVE</span></div><p>{loading?"Preparing your operations summary…":pulse}</p><div className="pulse-actions"><button onClick={()=>onNavigate(low>0?"Inventory":pending>0?"Distribution":"Sales")}>{low>0?"Review stock alerts":pending>0?"Review deliveries":"Open sales workspace"} <span>→</span></button><button onClick={()=>onNavigate("Reports")}>View reports <span>→</span></button></div></article>
   <article className="focus-card"><div><small>QUICK CREATE</small><h3>Start a workflow</h3><p>Jump into a frequently used task.</p></div><div className="focus-actions"><button onClick={()=>onNavigate("Sales")}>＋ New sales order</button><button onClick={()=>onNavigate("Customers")}>＋ Add customer</button><button onClick={()=>onNavigate("Products")}>＋ Add product</button><button onClick={()=>onNavigate("Purchases")}>＋ Purchase order</button></div></article></div>
  <div className="dashboard-section-head launcher-head"><div><span className="section-kicker">WORKSPACE</span><h2>Explore modules</h2><p>Choose a business area to open its tools</p></div></div>
  <div className="launcher-grid">{launchers.map(group=>{const modules=group.modules.filter((module,index,all)=>allowedModules.includes(module)&&all.indexOf(module)===index);if(!modules.length)return null;const opened=expandedLauncher===group.title;return <article className={"launcher-card"+(opened?" expanded":"")} key={group.title}><button className="launcher-toggle" aria-expanded={opened} onClick={()=>setExpandedLauncher(opened?"":group.title)}><span className="launcher-top"><span>{group.icon}</span><b>{opened?"−":"+"}</b></span><strong>{group.title}</strong><small>{group.description}</small><span className="launcher-count">{modules.length} available options <i>{opened?"⌃":"⌄"}</i></span></button>{opened&&<div className="launcher-links">{modules.map(module=><button key={module} onClick={()=>onNavigate(module)}>{module}<span>→</span></button>)}</div>}</article>})}</div>
  <p className="dashboard-disclaimer">Operational indicators are read from your company database. They are not audited financial statements or AI-generated forecasts.</p>
 </section>;
}
