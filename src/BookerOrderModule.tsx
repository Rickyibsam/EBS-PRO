import { FormEvent, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, any>;
type CartLine = { product_id: string; unit_id: string; quantity: string };

export default function BookerOrderModule({ db, tenantId }: { db: SupabaseClient; tenantId: string }) {
  const [employee, setEmployee] = useState<Row | null>(null);
  const [routes, setRoutes] = useState<Row[]>([]);
  const [routeId, setRouteId] = useState("");
  const [customers, setCustomers] = useState<Row[]>([]);
  const [customerId, setCustomerId] = useState("");
  const [products, setProducts] = useState<Row[]>([]);
  const [units, setUnits] = useState<Row[]>([]);
  const [productUnits, setProductUnits] = useState<Row[]>([]);
  const [prices, setPrices] = useState<Row[]>([]);
  const [listId, setListId] = useState("");
  const [cart, setCart] = useState<CartLine[]>([{ product_id: "", unit_id: "", quantity: "1" }]);
  const [deliveryDate, setDeliveryDate] = useState("");
  const [notes, setNotes] = useState("");
  const [orders, setOrders] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");

  const money = (n: number) => "PKR " + Number(n || 0).toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const activeRoute = routes.find(x => x.id === routeId);
  const activeCustomer = customers.find(x => x.id === customerId);
  const estimate = useMemo(() => cart.reduce((sum, line) => {
    const qty = Number(line.quantity);
    const candidates = prices.filter(p => p.product_id === line.product_id && p.unit_id === line.unit_id && Number(p.min_quantity) <= qty).sort((a,b) => Number(b.min_quantity)-Number(a.min_quantity));
    const product = products.find(p => p.id === line.product_id);
    const subtotal = candidates[0] ? qty * Number(candidates[0].price) : 0;
    return sum + subtotal + subtotal * Number(product?.sales_tax_rate || 0) / 100;
  }, 0), [cart, prices]);

  async function load() {
    setLoading(true); setNotice("");
    try {
      const { data: auth, error: authError } = await db.auth.getUser();
      if (authError) throw authError;
      if (!auth.user) throw new Error("Please sign in again.");
      const [emp, prod, pu, u, recent] = await Promise.all([
        db.from("employees").select("id,employee_code,full_name,branch_id").eq("tenant_id", tenantId).eq("user_id", auth.user.id).eq("employment_status", "active").maybeSingle(),
        db.from("products").select("id,sku,name,sales_tax_rate").eq("tenant_id", tenantId).eq("is_active", true).order("name"),
        db.from("product_units").select("product_id,unit_id,conversion_to_base,is_sales_unit").eq("tenant_id", tenantId).eq("is_sales_unit", true),
        db.from("units_of_measure").select("id,name,symbol").eq("tenant_id", tenantId).order("name"),
        db.from("sales_orders").select("id,order_number,order_date,status,grand_total").eq("tenant_id", tenantId).eq("created_by", auth.user.id).eq("order_source", "order_booker").order("created_at", { ascending: false }).limit(30)
      ]);
      const err = emp.error || prod.error || pu.error || u.error || routeAssign.error || recent.error;
      if (err) throw err;
      if (!emp.data) throw new Error("Your active employee profile is not linked to this login. Ask the administrator to link your employee account and branch.");
      setEmployee(emp.data); setProducts(prod.data || []); setProductUnits(pu.data || []); setUnits(u.data || []); setOrders(recent.data || []);
      const { data: routeAssign, error: assignmentError } = await db.from("route_assignments").select("id,route_id,assigned_from,assigned_to").eq("tenant_id", tenantId).eq("employee_id", emp.data.id);
      if (assignmentError) throw assignmentError;
      const assignments = (routeAssign || []).filter(x => x.assigned_from <= new Date().toISOString().slice(0,10) && (!x.assigned_to || x.assigned_to >= new Date().toISOString().slice(0,10)));
      if (!assignments.length) { setRoutes([]); throw new Error("No active sales route is assigned to your employee account."); }
      const routeResult = await db.from("sales_routes").select("id,route_code,name,area_description").eq("tenant_id", tenantId).in("id", assignments.map(x => x.route_id)).eq("is_active", true).order("name");
      if (routeResult.error) throw routeResult.error;
      setRoutes(routeResult.data || []);
      if (!routeId && routeResult.data?.[0]) setRouteId(routeResult.data[0].id);
    } catch (e) { setNotice(e instanceof Error ? e.message : "Booker workspace could not be loaded."); }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId]);

  useEffect(() => {
    let cancelled = false;
    async function loadCustomers() {
      if (!routeId) { setCustomers([]); setCustomerId(""); return; }
      const { data: links, error } = await db.from("route_customers").select("customer_id,visit_order").eq("tenant_id", tenantId).eq("route_id", routeId).order("visit_order");
      if (error) { if (!cancelled) setNotice(error.message); return; }
      const ids = (links || []).map(x => x.customer_id);
      if (!ids.length) { if (!cancelled) { setCustomers([]); setCustomerId(""); } return; }
      const { data, error: partyError } = await db.from("parties").select("id,party_code,name,phone,credit_limit").eq("tenant_id", tenantId).in("id", ids).eq("status", "active").order("name");
      if (partyError) { if (!cancelled) setNotice(partyError.message); return; }
      if (!cancelled) { setCustomers(data || []); setCustomerId(""); setPrices([]); setListId(""); }
    }
    void loadCustomers();
    return () => { cancelled = true; };
  }, [routeId, tenantId]);

  useEffect(() => {
    let cancelled = false;
    async function loadCustomerPrices() {
      if (!customerId) { setPrices([]); setListId(""); return; }
      const { data: assigned, error } = await db.from("customer_price_lists").select("price_list_id").eq("tenant_id", tenantId).eq("customer_id", customerId).limit(1);
      if (error) { if (!cancelled) setNotice(error.message); return; }
      let selected = assigned?.[0]?.price_list_id || "";
      if (!selected) {
        const { data: defaults, error: defaultError } = await db.from("price_lists").select("id").eq("tenant_id", tenantId).eq("is_default", true).or("valid_from.is.null,valid_from.lte." + new Date().toISOString().slice(0,10)).or("valid_to.is.null,valid_to.gte." + new Date().toISOString().slice(0,10)).order("created_at", { ascending: false }).limit(1);
        if (defaultError) { if (!cancelled) setNotice(defaultError.message); return; }
        selected = defaults?.[0]?.id || "";
      }
      if (!selected) { if (!cancelled) { setPrices([]); setListId(""); setNotice("No active customer/default price list is configured. Contact sales administration."); } return; }
      const { data, error: priceError } = await db.from("product_prices").select("product_id,unit_id,price,min_quantity").eq("tenant_id", tenantId).eq("price_list_id", selected);
      if (priceError) { if (!cancelled) setNotice(priceError.message); return; }
      if (!cancelled) { setListId(selected); setPrices(data || []); setNotice(""); }
    }
    void loadCustomerPrices();
    return () => { cancelled = true; };
  }, [customerId, tenantId]);

  function updateLine(i: number, key: keyof CartLine, value: string) {
    setCart(old => old.map((line, index) => index === i ? { ...line, [key]: value, ...(key === "product_id" ? { unit_id: "" } : {}) } : line));
  }
  function linePrice(line: CartLine) {
    const qty = Number(line.quantity);
    return prices.filter(p => p.product_id === line.product_id && p.unit_id === line.unit_id && Number(p.min_quantity) <= qty).sort((a,b) => Number(b.min_quantity)-Number(a.min_quantity))[0]?.price;
  }
  async function submit(e: FormEvent) {
    e.preventDefault(); setSaving(true); setNotice("");
    try {
      if (!employee || !routeId || !customerId || !listId) throw new Error("Select your assigned route, customer and ensure a valid price list is available.");
      const valid = cart.filter(x => x.product_id && x.unit_id && Number.isFinite(Number(x.quantity)) && Number(x.quantity) > 0);
      if (!valid.length) throw new Error("Add at least one valid product line.");
      for (const line of valid) if (linePrice(line) == null) throw new Error("A valid price is missing for one or more product quantities. Ask sales administration to update the price list.");
      const requestId = crypto.randomUUID();
      const { data, error } = await db.rpc("create_order_booker_order", {
        p_tenant_id: tenantId, p_route_id: routeId, p_customer_id: customerId,
        p_client_request_id: requestId, p_required_delivery_date: deliveryDate || null,
        p_notes: notes.trim() || null,
        p_lines: valid.map(x => ({ product_id: x.product_id, unit_id: x.unit_id, quantity: Number(x.quantity) }))
      });
      if (error) throw error;
      setNotice("Order submitted successfully. Reference: " + String(data).slice(0, 8));
      setCart([{ product_id: "", unit_id: "", quantity: "1" }]); setNotes(""); setDeliveryDate("");
      await load();
    } catch (e) { setNotice(e instanceof Error ? e.message : "Order could not be submitted."); }
    setSaving(false);
  }

  if (loading) return <section className="module-page"><div className="table-empty">Loading Booker workspace…</div></section>;
  return <section className="module-page">
    <div className="module-toolbar"><div><h2>Mobile Booker App</h2><p>Assigned route customers, live product pricing and secure order submission.</p></div><button onClick={() => void load()}>↻ Refresh</button></div>
    {notice && <div className="notice">{notice}</div>}
    {employee && <><div className="table-tools"><strong>{employee.full_name}</strong><span>{employee.employee_code}</span><span>{activeRoute?.name || "Assigned route"}</span></div>
    <form className="transaction-form" onSubmit={submit}>
      <h3>New customer order</h3>
      <div className="form-grid">
        <label>Assigned route<select required value={routeId} onChange={e => setRouteId(e.target.value)}><option value="">Select route</option>{routes.map(r => <option key={r.id} value={r.id}>{r.route_code} · {r.name}</option>)}</select></label>
        <label>Route customer<select required value={customerId} onChange={e => setCustomerId(e.target.value)}><option value="">Select assigned customer</option>{customers.map(c => <option key={c.id} value={c.id}>{c.party_code} · {c.name}</option>)}</select></label>
        <label>Required delivery date<input type="date" min={new Date().toISOString().slice(0,10)} value={deliveryDate} onChange={e => setDeliveryDate(e.target.value)}/></label>
      </div>
      <h3>Order items</h3>
      {cart.map((line,i) => {
        const options = productUnits.filter(x => x.product_id === line.product_id);
        const price = linePrice(line);
        return <div className="form-grid" key={i}>
          <label>Product<select required value={line.product_id} onChange={e => updateLine(i,"product_id",e.target.value)}><option value="">Select product</option>{products.map(p => <option key={p.id} value={p.id}>{p.sku} · {p.name}</option>)}</select></label>
          <label>Sales unit<select required value={line.unit_id} onChange={e => updateLine(i,"unit_id",e.target.value)}><option value="">Select unit</option>{options.map(x => <option key={x.unit_id} value={x.unit_id}>{units.find(u => u.id === x.unit_id)?.symbol || units.find(u => u.id === x.unit_id)?.name || x.unit_id} (×{x.conversion_to_base})</option>)}</select></label>
          <label>Quantity<input required type="number" min="0.001" step="0.001" value={line.quantity} onChange={e => updateLine(i,"quantity",e.target.value)}/></label>
          <label>Unit price<input readOnly value={price == null ? "Price unavailable" : money(Number(price))}/></label>
          <label>Line total<input readOnly value={price == null ? "—" : money(Number(price)*Number(line.quantity))}/></label>
          <button type="button" onClick={() => setCart(old => old.length === 1 ? [{product_id:"",unit_id:"",quantity:"1"}] : old.filter((_,n)=>n!==i))}>Remove line</button>
        </div>;
      })}
      <div className="table-tools"><button type="button" onClick={() => setCart(old => [...old,{product_id:"",unit_id:"",quantity:"1"}])}>+ Add product</button><strong>Estimated total (incl. product tax): {money(estimate)}</strong></div>
      <label>Order notes<textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Optional delivery instructions"/></label>
      <button disabled={saving || !prices.length}>{saving ? "Submitting order…" : "Submit order"}</button>
      <p className="module-footnote">Orders are submitted using the database's assigned-route, customer, active price-list and duplicate-request checks. Final approval and stock dispatch remain with authorized office/warehouse staff.</p>
    </form>
    <h3>My recent orders</h3>
    <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Order</th><th>Date</th><th>Status</th><th>Total</th></tr></thead><tbody>{orders.map(o=><tr key={o.id}><td>{o.order_number}</td><td>{new Date(o.order_date).toLocaleDateString("en-PK")}</td><td>{o.status}</td><td>{money(o.grand_total)}</td></tr>)}{!orders.length&&<tr><td colSpan={4} className="table-empty">No orders submitted yet.</td></tr>}</tbody></table></div>
    </>}
  </section>;
}
