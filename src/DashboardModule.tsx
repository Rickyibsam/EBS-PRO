import {useEffect,useMemo,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Metric={label:string;value:string;detail:string;icon:string;tone:string};
const money=(v:number)=>"PKR "+Number(v||0).toLocaleString("en-PK",{maximumFractionDigits:0});
const launchers=[
 {title:"Sales & Customers",description:"Orders, invoices, returns and customer accounts",icon:"◈",modules:["Sales","Customers","Invoices","Sales Returns"]},
 {title:"Inventory & Warehouse",description:"Stock, batches, expiry and vehicle inventory",icon:"▦",modules:["Inventory","Batch & Expiry","Van Stock","Stock Transfers"]},
 {title:"Purchase & Vendors",description:"Procurement, GRN, supplier invoices and returns",icon:"⇩",modules:["Purchases","Goods Receiving","Vendor Invoices","Purchase Returns"]},
 {title:"Finance & Control",description:"Ledgers, reconciliation, payroll and budgets",icon:"◉",modules:["Accounts","Payroll","Asset & Budget Control","Bank Reconciliation"]},
 {title:"Distribution",description:"Booker orders, delivery routes and proof of delivery",icon:"⌖",modules:["Booker App","Delivery Man App","Distribution","Routes"]},
 {title:"Reports & Governance",description:"Performance, incentives, audit and voucher history",icon:"▤",modules:["Reports","Targets & Incentives","Audit Trail","Voucher Revision History"]}
];
export default function DashboardModule({db,tenantId,company,onNavigate}:{db:SupabaseClient;tenantId:string;company:string;onNavigate:(module:string)=>void}){
 const [metrics,setMetrics]=useState<Metric[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const [updatedAt,setUpdatedAt]=useState("");
 useEffect(()=>{let live=true;async function load(){setLoading(true);setError("");try{
  const now=new Date(),fmt=(v:Date)=>[v.getFullYear(),String(v.getMonth()+1).padStart(2,"0"),String(v.getDate()).padStart(2,"0")].join("-");
  const today=fmt(now),tomorrow=fmt(new Date(now.getFullYear(),now.getMonth(),now.getDate()+1));
  const [sales,orders,purchases,products,customers,vendors,receipts,stock,deliveries]=await Promise.all([
   db.from("sales_orders").select("id,grand_total,status,order_date",{count:"exact"}).eq("tenant_id",tenantId).gte("order_date",today).lt("order_date",tomorrow),
   db.from("sales_orders").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("status",["draft","submitted","approved","allocated"]),
   db.from("purchase_orders").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId),
   db.from("products").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).eq("is_active",true),
   db.from("parties").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("party_type",["customer","both"]).eq("status","active"),
   db.from("parties").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("party_type",["supplier","both"]).eq("status","active"),
   db.from("payments").select("amount,payment_type").eq("tenant_id",tenantId).eq("payment_date",today),
   db.from("stock_movements").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId),
   db.from("deliveries").select("id",{count:"exact",head:true}).eq("tenant_id",tenantId).in("status",["pending","picked","dispatched"])
  ]);
  const err=[sales,orders,purchases,products,customers,vendors,receipts,stock,deliveries].find(x=>x.error);if(err)throw err.error;
  const daySales=(sales.data??[]).filter(x=>!["draft","cancelled"].includes(x.status)).reduce((s,x)=>s+Number(x.grand_total||0),0);
  const dayReceipts=(receipts.data??[]).filter(x=>x.payment_type==="receipt").reduce((s,x)=>s+Number(x.amount||0),0);
  const next:Metric[]=[
   {label:"Sales today",value:money(daySales),detail:(sales.count??0)+" documents today",icon:"↗",tone:"mint"},
   {label:"Open sales orders",value:String(orders.count??0),detail:"Awaiting next workflow step",icon:"▤",tone:"blue"},
   {label:"Pending deliveries",value:String(deliveries.count??0),detail:"Pending, picked or dispatched",icon:"⌖",tone:"amber"},
   {label:"Receipts today",value:money(dayReceipts),detail:"Customer receipts recorded",icon:"₨",tone:"violet"},
   {label:"Purchase orders",value:String(purchases.count??0),detail:"Purchase documents",icon:"⇩",tone:"blue"},
   {label:"Active products",value:String(products.count??0),detail:"Product master records",icon:"▦",tone:"mint"},
   {label:"Customers",value:String(customers.count??0),detail:"Active customer accounts",icon:"♙",tone:"violet"},
   {label:"Vendors",value:String(vendors.count??0),detail:"Active supplier accounts",icon:"⌂",tone:"amber"}
  ];
  if(live){setMetrics(next);setUpdatedAt(now.toLocaleTimeString("en-PK",{hour:"2-digit",minute:"2-digit"}));}
 }catch(e){if(live)setError(e instanceof Error?e.message:"Dashboard could not load.");}finally{if(live)setLoading(false);}}
 void load();return()=>{live=false;};
 },[db,tenantId]);
 const openOrders=Number(metrics.find(x=>x.label==="Open sales orders")?.value||0),pending=Number(metrics.find(x=>x.label==="Pending deliveries")?.value||0);
 const pulse=useMemo(()=>pending>0?pending+" deliveries are in the dispatch pipeline. Review delivery assignments and proof of delivery.":openOrders>0?openOrders+" sales orders are waiting for the next processing step.":"Your current sales and delivery queues show no pending items.",[pending,openOrders]);
 const hour=new Date().getHours(),greeting=hour<12?"Good morning":hour<17?"Good afternoon":"Good evening";
 return <section className="ai-dashboard">
  <div className="dashboard-hero"><div className="hero-orb hero-orb-one"/><div className="hero-orb hero-orb-two"/><div className="hero-copy"><span className="hero-eyebrow"><i/> EBS PRO INTELLIGENCE · V.01</span><h1>{greeting}, welcome back.</h1><p>Your {company} workspace at a glance. Monitor operations, spot priorities and move directly into the next task.</p><div className="hero-meta"><span>◷ {new Date().toLocaleDateString("en-PK",{weekday:"long",day:"2-digit",month:"long",year:"numeric"})}</span><span>● Live workspace</span>{updatedAt&&<span>Updated {updatedAt}</span>}</div></div><div className="hero-mark"><div className="hero-mark-inner">E<span>AI</span></div><small>BUSINESS PULSE</small></div></div>
  <div className="dashboard-section-head"><div><span className="section-kicker">LIVE PERFORMANCE</span><h2>Business snapshot</h2><p>Key activity from your company database</p></div><button className="dashboard-refresh" onClick={()=>window.location.reload()}>↻ Refresh view</button></div>
  {error&&<div className="notice">{error}</div>}
  {loading?<div className="dashboard-loading"><span className="loading-pulse"/> Reading live business data…</div>:<div className="ai-metric-grid">{metrics.map(m=><article className="ai-metric" key={m.label}><div className={"metric-icon "+m.tone}>{m.icon}</div><div className="metric-label">{m.label}</div><strong>{m.value}</strong><small>{m.detail}</small><span className="metric-glow"/></article>)}</div>}
  <div className="dashboard-lower"><article className="pulse-card"><div className="pulse-heading"><span className="pulse-spark">✦</span><div><small>SMART BUSINESS PULSE</small><h3>Operations insight</h3></div><span className="pulse-live">LIVE</span></div><p>{loading?"Preparing your operations summary…":pulse}</p><div className="pulse-actions"><button onClick={()=>onNavigate(pending>0?"Distribution":"Sales")}>{pending>0?"Review deliveries":"Open sales workspace"} <span>→</span></button><button onClick={()=>onNavigate("Reports")}>View reports <span>→</span></button></div></article>
   <article className="focus-card"><div><small>QUICK CREATE</small><h3>Start a workflow</h3><p>Jump into a frequently used task.</p></div><div className="focus-actions"><button onClick={()=>onNavigate("Sales")}>＋ New sales order</button><button onClick={()=>onNavigate("Customers")}>＋ Add customer</button><button onClick={()=>onNavigate("Products")}>＋ Add product</button><button onClick={()=>onNavigate("Purchases")}>＋ Purchase order</button></div></article></div>
  <div className="dashboard-section-head launcher-head"><div><span className="section-kicker">WORKSPACE</span><h2>Explore modules</h2><p>Choose a business area to open its tools</p></div></div>
  <div className="launcher-grid">{launchers.map(group=><article className="launcher-card" key={group.title}><div className="launcher-top"><span>{group.icon}</span><b>↗</b></div><h3>{group.title}</h3><p>{group.description}</p><div className="launcher-links">{group.modules.map(module=><button key={module} onClick={()=>onNavigate(module)}>{module}<span>→</span></button>)}</div></article>)}</div>
  <p className="dashboard-disclaimer">Operational indicators are read from your company database. They are not audited financial statements or AI-generated forecasts.</p>
 </section>;
}
