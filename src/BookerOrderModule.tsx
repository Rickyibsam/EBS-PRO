import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {enqueueBookerOrder,getPendingBookerOrders,removePendingBookerOrder,cacheBookerSnapshot,getBookerSnapshot,enqueueBookerVisit,getPendingBookerVisits,removePendingBookerVisit} from "./bookerOfflineQueue";

type Row = Record<string, any>;
type CartLine = { product_id: string; unit_id: string; quantity: string; is_free:boolean };
let deferredInstallPrompt:any=null;
if(typeof window!=="undefined")window.addEventListener("beforeinstallprompt",(event:Event)=>{event.preventDefault();deferredInstallPrompt=event;});

export default function BookerOrderModule({ db, tenantId }: { db: SupabaseClient; tenantId: string }) {
  const [employee, setEmployee] = useState<Row | null>(null);
  const [routes, setRoutes] = useState<Row[]>([]);
  const [routeId, setRouteId] = useState("");
  const [customers, setCustomers] = useState<Row[]>([]);
  const [customerId, setCustomerId] = useState("");
  const [showNewCustomer,setShowNewCustomer]=useState(false);
  const [newCustomer,setNewCustomer]=useState({name:"",phone:"",address:"",city:""});
  const [products, setProducts] = useState<Row[]>([]);
  const [units, setUnits] = useState<Row[]>([]);
  const [productUnits, setProductUnits] = useState<Row[]>([]);
  const [prices, setPrices] = useState<Row[]>([]);
  const [listId, setListId] = useState("");
  const [cart, setCart] = useState<CartLine[]>([{ product_id: "", unit_id: "", quantity: "1", is_free:false }]);
  const [productSearch,setProductSearch]=useState("");
  const [barcodeInput,setBarcodeInput]=useState("");
  const [deliveryDate, setDeliveryDate] = useState("");
  const [notes, setNotes] = useState("");
  const [orders, setOrders] = useState<Row[]>([]);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [authUserId,setAuthUserId]=useState("");
  const [installPrompt,setInstallPrompt]=useState<any>(deferredInstallPrompt);
  useEffect(()=>{const handler=(event:Event)=>{event.preventDefault();setInstallPrompt(event as any);};window.addEventListener("beforeinstallprompt",handler);return()=>window.removeEventListener("beforeinstallprompt",handler);},[]);
  const [pendingCount,setPendingCount]=useState(0);
  const [pendingVisitCount,setPendingVisitCount]=useState(0);
  const [syncing,setSyncing]=useState(false);
  const syncLock=useRef(false);

  const money = (n: number) => "PKR " + Number(n || 0).toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const activeRoute = routes.find(x => x.id === routeId);
  const activeCustomer = customers.find(x => x.id === customerId);
  const filteredProducts=useMemo(()=>{const q=productSearch.trim().toLowerCase();return q?products.filter(p=>[p.name,p.sku,p.barcode,p.brand].some(v=>String(v||"").toLowerCase().includes(q))):products;},[products,productSearch]);
  const estimate = useMemo(() => cart.reduce((sum, line) => {
    const qty = Number(line.quantity);
    const candidates = prices.filter(p => p.product_id === line.product_id && p.unit_id === line.unit_id && Number(p.min_quantity) <= qty).sort((a,b) => Number(b.min_quantity)-Number(a.min_quantity));
    const product = products.find(p => p.id === line.product_id);
    const subtotal = !line.is_free && candidates[0] ? qty * Number(candidates[0].price) : 0;
    return sum + subtotal + subtotal * Number(product?.sales_tax_rate || 0) / 100;
  }, 0), [cart, prices]);

  async function load() {
    setLoading(true); setNotice("");
    try {
      const { data: auth, error: authError } = await db.auth.getUser();
      if (authError) throw authError;
      if (!auth.user) throw new Error("Please sign in again.");
      setAuthUserId(auth.user.id);
      const [emp, prod, pu, u, recent] = await Promise.all([
        db.from("employees").select("id,employee_code,full_name,branch_id").eq("tenant_id", tenantId).eq("user_id", auth.user.id).eq("employment_status", "active").maybeSingle(),
        db.from("products").select("id,sku,barcode,name,brand,sales_tax_rate").eq("tenant_id", tenantId).eq("is_active", true).order("name"),
        db.from("product_units").select("product_id,unit_id,conversion_to_base,is_sales_unit").eq("tenant_id", tenantId).eq("is_sales_unit", true),
        db.from("units_of_measure").select("id,name,symbol").eq("tenant_id", tenantId).order("name"),
        db.from("sales_orders").select("id,order_number,order_date,status,grand_total").eq("tenant_id", tenantId).eq("created_by", auth.user.id).eq("order_source", "order_booker").order("created_at", { ascending: false }).limit(30)
      ]);
      const err = emp.error || prod.error || pu.error || u.error || recent.error;
      if (err) throw err;
      if (!emp.data) throw new Error("Your active employee profile is not linked to this login. Ask the administrator to link your employee account and branch.");
      const [ruleResult,vendorMap]=await Promise.all([
        db.from("booker_product_visibility").select("vendor_id,brand,product_id,is_allowed,require_stock").eq("tenant_id",tenantId).eq("employee_id",emp.data.id),
        db.from("vendor_product_catalog").select("product_id,supplier_id").eq("tenant_id",tenantId)
      ]);
      if(ruleResult.error)throw ruleResult.error;if(vendorMap.error)throw vendorMap.error;
      const rules=ruleResult.data||[];
      let visibleProducts=(prod.data||[]).filter(product=>{
        const matching=rules.filter(rule=>(rule.product_id&&rule.product_id===product.id)||(rule.brand&&rule.brand.toLowerCase()===(product.brand||"").toLowerCase())||(rule.vendor_id&&(vendorMap.data||[]).some(v=>v.product_id===product.id&&v.supplier_id===rule.vendor_id)));
        if(!matching.length)return !rules.some(rule=>rule.is_allowed===true);
        const specific=matching.filter(rule=>rule.product_id===product.id);
        const brandRules=matching.filter(rule=>rule.brand&&rule.brand.toLowerCase()===(product.brand||"").toLowerCase());
        const vendorRules=matching.filter(rule=>rule.vendor_id&&(vendorMap.data||[]).some(v=>v.product_id===product.id&&v.supplier_id===rule.vendor_id));
        const applicable=specific.length?specific:brandRules.length?brandRules:vendorRules;
        return applicable.some(rule=>rule.is_allowed===true)&&!applicable.some(rule=>rule.is_allowed===false);
      });
      const stockRules=rules.some(rule=>rule.require_stock&&rule.is_allowed);
      if(stockRules&&visibleProducts.length){
        const stockResult=await db.rpc("get_booker_stock_balances",{p_tenant_id:tenantId});
        if(stockResult.error)throw stockResult.error;
        const stockRows: Array<{product_id:string;quantity_on_hand:number}> = (stockResult.data||[]) as Array<{product_id:string;quantity_on_hand:number}>;
        const balances=stockRows.reduce<Record<string,number>>((acc,row)=>{acc[row.product_id]=Number(row.quantity_on_hand||0);return acc;},{});
        visibleProducts=visibleProducts.filter(product=>{
          const applicable=rules.filter(rule=>rule.require_stock&&rule.is_allowed&&((rule.product_id&&rule.product_id===product.id)||(rule.brand&&rule.brand.toLowerCase()===(product.brand||"").toLowerCase())||(rule.vendor_id&&(vendorMap.data||[]).some(v=>v.product_id===product.id&&v.supplier_id===rule.vendor_id))));
          return !applicable.length||Number(balances[product.id]||0)>0;
        });
      }
      setEmployee(emp.data); setProducts(visibleProducts); setProductUnits(pu.data || []); setUnits(u.data || []); setOrders(recent.data || []);
      const { data: routeAssign, error: assignmentError } = await db.from("route_assignments").select("id,route_id,assigned_from,assigned_to").eq("tenant_id", tenantId).eq("employee_id", emp.data.id);
      if (assignmentError) throw assignmentError;
      const assignments = (routeAssign || []).filter(x => x.assigned_from <= new Date().toISOString().slice(0,10) && (!x.assigned_to || x.assigned_to >= new Date().toISOString().slice(0,10)));
      if (!assignments.length) { setRoutes([]); throw new Error("No active sales route is assigned to your employee account."); }
      const routeResult = await db.from("sales_routes").select("id,route_code,name,area_description").eq("tenant_id", tenantId).in("id", assignments.map(x => x.route_id)).eq("is_active", true).order("name");
      if (routeResult.error) throw routeResult.error;
      setRoutes(routeResult.data || []);
      const effectiveRouteId=routeId||routeResult.data?.[0]?.id||"";
      if (!routeId && routeResult.data?.[0]) setRouteId(routeResult.data[0].id);
      await cacheBookerSnapshot(tenantId,auth.user.id,{employee:emp.data,products:visibleProducts,productUnits:pu.data||[],units:u.data||[],orders:recent.data||[],routes:routeResult.data||[],routeId:effectiveRouteId});
    } catch (e) {
      if(!navigator.onLine||/fetch|network|offline|connection|timeout/i.test(e instanceof Error?e.message:"")){
        try{const {data:{session}}=await db.auth.getSession();const offlineUserId=session?.user.id||"";if(!offlineUserId)throw new Error("Sign in on this device before using offline Booker data.");setAuthUserId(offlineUserId);const cached=await getBookerSnapshot(tenantId,offlineUserId);const d=cached?.data;if(d){setEmployee((d.employee as Row)||null);setProducts((d.products as Row[])||[]);setProductUnits((d.productUnits as Row[])||[]);setUnits((d.units as Row[])||[]);setOrders((d.orders as Row[])||[]);setRoutes((d.routes as Row[])||[]);setRouteId(String(d.routeId||""));setCustomers((d.customers as Row[])||[]);setCustomerId(String(d.customerId||""));setPrices((d.prices as Row[])||[]);setListId(String(d.listId||""));setNotice("Offline mode: using the last saved route, customer list and price list. Orders will sync when online.");}else setNotice("Offline and no saved Booker catalogue is available on this device. Connect once to cache route data.");}
        catch(cacheError){setNotice(cacheError instanceof Error?cacheError.message:"Offline Booker data could not be loaded.");}
      }else setNotice(e instanceof Error ? e.message : "Booker workspace could not be loaded.");
    }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId]);

  async function createRouteCustomer(e:FormEvent){
    e.preventDefault();
    if(!navigator.onLine){setNotice("New customer registration requires an internet connection.");return;}
    if(!activeRoute){setNotice("Select your assigned route first.");return;}
    setSaving(true);setNotice("");
    try{
      const {data,error}=await db.rpc("create_booker_customer",{p_tenant_id:tenantId,p_route_id:routeId,p_name:newCustomer.name.trim(),p_phone:newCustomer.phone.trim()||null,p_address:newCustomer.address.trim()||null,p_city:newCustomer.city.trim()||null});
      if(error)throw error;
      await load();setCustomerId(data.customer_id);setShowNewCustomer(false);setNewCustomer({name:"",phone:"",address:"",city:""});
      setNotice(data.existing_customer?"Existing customer linked to your route.":"New route customer registered successfully.");
    }catch(err){setNotice(err instanceof Error?err.message:"Customer could not be registered.");}
    finally{setSaving(false);}
  }

  async function syncQueuedOrders(){
    if(!navigator.onLine||syncLock.current)return;
    syncLock.current=true;setSyncing(true);
    try{
      const {data:{session}}=await db.auth.getSession();const userId=authUserId||session?.user.id||"";
      if(!userId)throw new Error("Sign in on this device before synchronizing offline Booker work.");
      const pending=await getPendingBookerOrders(tenantId,userId);setPendingCount(pending.length);
      for(const order of pending){
        const {error}=await db.rpc("create_order_booker_order",{p_tenant_id:order.tenantId,p_route_id:order.routeId,p_customer_id:order.customerId,p_client_request_id:order.requestId,p_required_delivery_date:order.requiredDeliveryDate,p_notes:order.notes,p_lines:order.lines});
        if(error){setNotice("Offline order sync paused. "+error.message);break;}
        await removePendingBookerOrder(order.id);
      }
      const queuedVisits=await getPendingBookerVisits(tenantId,userId);setPendingVisitCount(queuedVisits.length);
      for(const visit of queuedVisits){
        const {error}=await db.rpc("record_booker_visit",{p_tenant_id:visit.tenantId,p_route_id:visit.routeId,p_customer_id:visit.customerId,p_visit_at:visit.visitAt,p_latitude:visit.latitude,p_longitude:visit.longitude,p_idempotency_key:visit.requestId,p_notes:visit.notes});
        if(error){setNotice("Offline visit sync paused. "+error.message);break;}
        await removePendingBookerVisit(visit.id);
      }
      const [remainingOrders,remainingVisits]=await Promise.all([getPendingBookerOrders(tenantId,userId),getPendingBookerVisits(tenantId,userId)]);
      setPendingCount(remainingOrders.length);setPendingVisitCount(remainingVisits.length);
      if(pending.length+queuedVisits.length>0&&remainingOrders.length+remainingVisits.length===0){setNotice("All offline Booker orders and GPS visits have synchronized.");await load();}
    }catch(e){setNotice(e instanceof Error?e.message:"Offline Booker synchronization is waiting for a stable connection.");}
    finally{syncLock.current=false;setSyncing(false);}
  }

  useEffect(()=>{void db.auth.getSession().then(async({data})=>{const userId=data.session?.user.id||"";const [orders,visits]=await Promise.all([getPendingBookerOrders(tenantId,userId),getPendingBookerVisits(tenantId,userId)]);setPendingCount(orders.length);setPendingVisitCount(visits.length);}).catch(()=>{});const onOnline=()=>void syncQueuedOrders();window.addEventListener('online',onOnline);if(navigator.onLine)void syncQueuedOrders();return()=>window.removeEventListener('online',onOnline);},[tenantId]);

  useEffect(() => {
    let cancelled = false;
    async function loadCustomers() {
      if(!navigator.onLine)return;
      if (!routeId) { setCustomers([]); setCustomerId(""); return; }
      const { data: links, error } = await db.from("route_customers").select("customer_id,visit_order").eq("tenant_id", tenantId).eq("route_id", routeId).order("visit_order");
      if (error) { if (!cancelled) setNotice(error.message); return; }
      const ids = (links || []).map(x => x.customer_id);
      if (!ids.length) { if (!cancelled) { setCustomers([]); setCustomerId(""); } return; }
      const { data, error: partyError } = await db.from("parties").select("id,party_code,name,phone,credit_limit").eq("tenant_id", tenantId).in("id", ids).eq("status", "active").order("name");
      if (partyError) { if (!cancelled) setNotice(partyError.message); return; }
      if (!cancelled) { setCustomers(data || []); setCustomerId(""); setPrices([]); setListId(""); await cacheBookerSnapshot(tenantId,authUserId,{customers:data||[],routeId,customerId:"",prices:[],listId:""}); }
    }
    void loadCustomers();
    return () => { cancelled = true; };
  }, [routeId, tenantId]);

  useEffect(() => {
    let cancelled = false;
    async function loadCustomerPrices() {
      if(!navigator.onLine)return;
      if (!customerId) { setPrices([]); setListId(""); return; }
      const { data: assigned, error } = await db.from("customer_price_lists").select("price_list_id").eq("tenant_id", tenantId).eq("customer_id", customerId).limit(1);
      if (error) { if (!cancelled) setNotice(error.message); return; }
      const today = new Date().toISOString().slice(0,10);
      let selected = "";
      const assignedId = assigned?.[0]?.price_list_id;
      if (assignedId) {
        const { data: assignedList, error: assignedListError } = await db.from("price_lists").select("id,valid_from,valid_to").eq("tenant_id",tenantId).eq("id",assignedId).maybeSingle();
        if (assignedListError) { if (!cancelled) setNotice(assignedListError.message); return; }
        if (assignedList && (!assignedList.valid_from || assignedList.valid_from <= today) && (!assignedList.valid_to || assignedList.valid_to >= today)) selected = assignedList.id;
      }
      if (!selected) {
        const { data: defaults, error: defaultError } = await db.from("price_lists").select("id,valid_from,valid_to").eq("tenant_id", tenantId).eq("is_default", true).order("created_at", { ascending: false });
        if (defaultError) { if (!cancelled) setNotice(defaultError.message); return; }
        selected = (defaults || []).find(x => (!x.valid_from || x.valid_from <= today) && (!x.valid_to || x.valid_to >= today))?.id || "";
      }
      if (!selected) { if (!cancelled) { setPrices([]); setListId(""); setNotice("No active customer/default price list is configured. Contact sales administration."); } return; }
      const { data, error: priceError } = await db.from("product_prices").select("product_id,unit_id,price,min_quantity").eq("tenant_id", tenantId).eq("price_list_id", selected);
      if (priceError) { if (!cancelled) setNotice(priceError.message); return; }
      if (!cancelled) { setListId(selected); setPrices(data || []); setNotice(""); await cacheBookerSnapshot(tenantId,authUserId,{customerId,prices:data||[],listId:selected}); }
    }
    void loadCustomerPrices();
    return () => { cancelled = true; };
  }, [customerId, tenantId]);

  function updateLine(i: number, key: keyof CartLine, value: string) {
    setCart(old => old.map((line, index) => index === i ? { ...line, [key]: value, ...(key === "product_id" ? { unit_id: "" } : {}) } : line));
  }
  function addScannedProduct(raw:string){
    const code=raw.trim();if(!code)return;
    const product=products.find(p=>String(p.barcode||"").trim()===code||String(p.sku||"").trim().toLowerCase()===code.toLowerCase());
    if(!product){setNotice("No product matched barcode / SKU: "+code);setBarcodeInput("");return;}
    const unit=productUnits.find(x=>x.product_id===product.id);
    if(!unit){setNotice("No sales unit is configured for "+product.name+".");setBarcodeInput("");return;}
    setCart(old=>{const index=old.findIndex(x=>x.product_id===product.id&&x.unit_id===unit.unit_id&&!x.is_free);if(index>=0)return old.map((x,i)=>i===index?{...x,quantity:String(Number(x.quantity)+1)}:x);const line={product_id:product.id,unit_id:unit.unit_id,quantity:"1",is_free:false};return old.length===1&&!old[0].product_id?[line]:[...old,line];});
    setNotice("Added "+product.name+" from barcode / SKU scan.");setBarcodeInput("");
  }
  function linePrice(line: CartLine) {
    if(line.is_free)return 0;
    const qty = Number(line.quantity);
    return prices.filter(p => p.product_id === line.product_id && p.unit_id === line.unit_id && Number(p.min_quantity) <= qty).sort((a,b) => Number(b.min_quantity)-Number(a.min_quantity))[0]?.price;
  }
  async function recordVisit(){
    if(!employee||!routeId||!customerId){setNotice("Select an assigned route and customer before check-in.");return;}
    if(!navigator.geolocation){setNotice("GPS is not supported by this device/browser.");return;}
    setSaving(true);setNotice("");
    try{
      const position=await new Promise<GeolocationPosition>((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,reject,{enableHighAccuracy:true,timeout:15000,maximumAge:30000}));
      const {data:{session}}=await db.auth.getSession();const userId=authUserId||session?.user.id||"";
      if(!userId)throw new Error("Sign in on this device once while online before saving offline GPS visits.");
      const requestId=crypto.randomUUID(),visitAt=new Date().toISOString();
      const queued={id:requestId,kind:"visit" as const,tenantId,userId,routeId,customerId,requestId,visitAt,latitude:position.coords.latitude,longitude:position.coords.longitude,notes:"GPS check-in",createdAt:visitAt};
      if(!navigator.onLine){
       await enqueueBookerVisit(queued);setPendingVisitCount(n=>n+1);setNotice("GPS check-in saved offline. It will sync automatically when internet returns.");
      }else{
       const {error}=await db.rpc("record_booker_visit",{p_tenant_id:tenantId,p_route_id:routeId,p_customer_id:customerId,p_visit_at:visitAt,p_latitude:position.coords.latitude,p_longitude:position.coords.longitude,p_idempotency_key:requestId,p_notes:"GPS check-in"});
       if(error){
        if(!navigator.onLine||/fetch|network|offline|connection|timeout/i.test(error.message||"")){await enqueueBookerVisit(queued);setPendingVisitCount(n=>n+1);setNotice("Connection interrupted. GPS check-in queued for automatic synchronization.");}
        else throw error;
       }else setNotice("Customer visit check-in saved with GPS coordinates.");
      }
    }catch(e){setNotice(e instanceof Error?e.message:"GPS check-in could not be saved.");}
    finally{setSaving(false);}
  }

  async function submit(e: FormEvent) {
    e.preventDefault(); setSaving(true); setNotice("");
    try {
      if (!employee || !routeId || !customerId || !listId) throw new Error("Select your assigned route, customer and ensure a valid price list is available.");
      const valid = cart.filter(x => x.product_id && x.unit_id && Number.isFinite(Number(x.quantity)) && Number(x.quantity) > 0);
      if (!valid.length) throw new Error("Add at least one valid product line.");
      for (const line of valid) if (linePrice(line) == null) throw new Error("A valid price is missing for one or more product quantities. Ask sales administration to update the price list.");
      const {data:{session}}=await db.auth.getSession();const offlineUserId=authUserId||session?.user.id||"";if(!offlineUserId)throw new Error("Please sign in before saving an offline order.");
      const queuedOrder={id:requestId,kind:"order" as const,tenantId,userId:offlineUserId,routeId,customerId,requestId,requiredDeliveryDate:deliveryDate||null,notes:notes.trim()||null,lines:valid.map(x=>({product_id:x.product_id,unit_id:x.unit_id,quantity:Number(x.quantity),is_free_item:x.is_free})),createdAt:new Date().toISOString()};
      if(!navigator.onLine){
        await enqueueBookerOrder(queuedOrder);setPendingCount(n=>n+1);setNotice("Order saved securely on this device. It will sync automatically when internet returns.");
      }else{
        try{
          const {data,error}=await db.rpc("create_order_booker_order",{p_tenant_id:tenantId,p_route_id:routeId,p_customer_id:customerId,p_client_request_id:requestId,p_required_delivery_date:deliveryDate||null,p_notes:notes.trim()||null,p_lines:queuedOrder.lines});
          if(error)throw error;
          setNotice("Order submitted successfully. Reference: "+String(data).slice(0,8));
        }catch(networkError){
          if(navigator.onLine)throw networkError;
          await enqueueBookerOrder(queuedOrder);setPendingCount(n=>n+1);setNotice("Connection dropped. Order saved on this device and will sync automatically.");
        }
      }
      setCart([{ product_id: "", unit_id: "", quantity: "1", is_free:false }]); setNotes(""); setDeliveryDate(""); setRequestId(crypto.randomUUID());
      if(navigator.onLine)await load();
    } catch (e) { setNotice(e instanceof Error ? e.message : "Order could not be submitted."); }
    setSaving(false);
  }

  if (loading) return <section className="module-page"><div className="table-empty">Loading Booker workspace…</div></section>;
  return <section className="module-page">
    <div className="module-toolbar"><div><h2>Mobile Booker App</h2><p>Assigned route customers, product search and barcode scanning, free-item booking, live customer pricing, offline order and GPS visit capture.</p></div>{installPrompt&&<button onClick={async()=>{await installPrompt.prompt();setInstallPrompt(null);}}>Install Booker App</button>}{!installPrompt&&<button title="iPhone/iPad: Share → Add to Home Screen. Chrome/Edge: browser menu → Install app." onClick={()=>setNotice("Install on iPhone/iPad: open Share and choose Add to Home Screen. On Chrome/Edge, use the browser menu and choose Install app.")}>Install help</button>}<button onClick={() => void syncQueuedOrders()}>↻ Sync now</button><button onClick={() => void load()}>Refresh</button></div>
    {notice && <div className="notice">{notice}</div>}
    {employee && <><div className="table-tools"><strong>{employee.full_name}</strong><span>{employee.employee_code}</span><span>{activeRoute?.name || "Assigned route"}</span><span>{pendingCount} offline orders · {pendingVisitCount} GPS visits pending</span>{syncing&&<span>Syncing…</span>}</div>
    <form className="transaction-form" onSubmit={submit}>
      <h3>New customer order</h3>
      <div className="form-grid">
        <label>Assigned route<select required disabled={!navigator.onLine} value={routeId} onChange={e => setRouteId(e.target.value)}><option value="">Select route</option>{routes.map(r => <option key={r.id} value={r.id}>{r.route_code} · {r.name}</option>)}</select></label>
        <label>Route customer<select required disabled={!navigator.onLine} value={customerId} onChange={e => setCustomerId(e.target.value)}><option value="">Select assigned customer</option>{customers.map(c => <option key={c.id} value={c.id}>{c.party_code} · {c.name}</option>)}</select></label><button type="button" disabled={!navigator.onLine||!routeId||saving} onClick={()=>setShowNewCustomer(x=>!x)}>＋ New customer</button><label>Field visit<button type="button" disabled={saving||!customerId} onClick={()=>void recordVisit()}>GPS check-in</button></label>
        <label>Required delivery date<input type="date" min={new Date().toISOString().slice(0,10)} value={deliveryDate} onChange={e => setDeliveryDate(e.target.value)}/></label>
      </div>
      {showNewCustomer&&<div className="transaction-form"><h3>Register route customer</h3><form className="form-grid" onSubmit={createRouteCustomer}><label>Customer name<input required value={newCustomer.name} onChange={e=>setNewCustomer({...newCustomer,name:e.target.value})}/></label><label>Phone<input value={newCustomer.phone} onChange={e=>setNewCustomer({...newCustomer,phone:e.target.value})}/></label><label>Address<input value={newCustomer.address} onChange={e=>setNewCustomer({...newCustomer,address:e.target.value})}/></label><label>City / Area<input value={newCustomer.city} onChange={e=>setNewCustomer({...newCustomer,city:e.target.value})}/></label><button disabled={saving}>Save customer to route</button></form></div>}
      <h3>Order items</h3>
      <div className="form-grid"><label>Search product<input type="search" value={productSearch} onChange={e=>setProductSearch(e.target.value)} placeholder="Search product, SKU or brand"/></label><label>Scan barcode / SKU<input value={barcodeInput} onChange={e=>setBarcodeInput(e.target.value)} onKeyDown={e=>{if(e.key==="Enter"){e.preventDefault();addScannedProduct(barcodeInput);}}} placeholder="Scan barcode then press Enter"/></label></div>
      {cart.map((line,i) => {
        const options = productUnits.filter(x => x.product_id === line.product_id);
        const price = linePrice(line);
        return <div className="form-grid" key={i}>
          <label>Product<select required value={line.product_id} onChange={e => updateLine(i,"product_id",e.target.value)}><option value="">Select product</option>{filteredProducts.map(p => <option key={p.id} value={p.id}>{p.sku} · {p.name}</option>)}</select></label>
          <label>Sales unit<select required value={line.unit_id} onChange={e => updateLine(i,"unit_id",e.target.value)}><option value="">Select unit</option>{options.map(x => <option key={x.unit_id} value={x.unit_id}>{units.find(u => u.id === x.unit_id)?.symbol || units.find(u => u.id === x.unit_id)?.name || x.unit_id} (×{x.conversion_to_base})</option>)}</select></label>
          <label>Quantity<input required type="number" min="0.001" step="0.001" value={line.quantity} onChange={e => updateLine(i,"quantity",e.target.value)}/></label>
          <label>Unit price<input readOnly value={line.is_free?"FREE ITEM":price == null ? "Price unavailable" : money(Number(price))}/></label>
          <label>Line total<input readOnly value={line.is_free?money(0):price == null ? "—" : money(Number(price)*Number(line.quantity))}/></label><label><span>Free item (FOC)</span><input type="checkbox" checked={line.is_free} onChange={e=>setCart(old=>old.map((x,n)=>n===i?{...x,is_free:e.target.checked}:x))}/></label>
          <button type="button" onClick={() => setCart(old => old.length === 1 ? [{product_id:"",unit_id:"",quantity:"1",is_free:false}] : old.filter((_,n)=>n!==i))}>Remove line</button>
        </div>;
      })}
      <div className="table-tools"><button type="button" onClick={() => setCart(old => [...old,{product_id:"",unit_id:"",quantity:"1",is_free:false}])}>+ Add product</button><strong>Estimated total (incl. product tax): {money(estimate)}</strong></div>
      <label>Order notes<textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Optional delivery instructions"/></label>
      <button disabled={saving || !prices.length}>{saving ? "Submitting order…" : "Submit order"}</button>
      <p className="module-footnote">Orders are submitted using the database's assigned-route, customer, active price-list and duplicate-request checks. Final approval and stock dispatch remain with authorized office/warehouse staff.</p>
    </form>
    <h3>My recent orders</h3>
    <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Order</th><th>Date</th><th>Status</th><th>Total</th></tr></thead><tbody>{orders.map(o=><tr key={o.id}><td>{o.order_number}</td><td>{new Date(o.order_date).toLocaleDateString("en-PK")}</td><td>{o.status}</td><td>{money(o.grand_total)}</td></tr>)}{!orders.length&&<tr><td colSpan={4} className="table-empty">No orders submitted yet.</td></tr>}</tbody></table></div>
    </>}
  </section>;
}
