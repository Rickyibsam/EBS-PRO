import { FormEvent, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Product = { id: string; sku: string; name: string; brand: string | null; barcode: string | null; is_active: boolean; min_stock: number; track_expiry: boolean; track_batch: boolean };
type Party = { id: string; party_code: string; party_type: string; name: string; contact_person: string | null; phone: string | null; city: string | null; credit_limit: number; opening_balance: number; status: string };

export default function WorkspaceModule({ db, tenantId, module }: { db: SupabaseClient; tenantId: string; module: string }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [search, setSearch] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [productForm, setProductForm] = useState({ sku: "", name: "", brand: "", barcode: "", min_stock: "0", unit_name: "Piece", unit_symbol: "pcs", track_batch: false, track_expiry: false });
  const [partyForm, setPartyForm] = useState({ party_code: "", party_type: "customer", name: "", contact_person: "", phone: "", city: "", credit_limit: "0", opening_balance: "0" });

  const isProducts = module === "Products";
  const isParties = module === "Customers" || module === "Suppliers";
  const partyType = module === "Suppliers" ? "supplier" : "customer";

  async function load() {
    setLoading(true); setNotice("");
    if (isProducts) {
      const { data, error } = await db.from("products").select("id,sku,name,brand,barcode,is_active,min_stock,track_expiry,track_batch").eq("tenant_id", tenantId).order("name").limit(250);
      if (error) setNotice(error.message); else setProducts((data ?? []) as Product[]);
    } else if (isParties) {
      const { data, error } = await db.from("parties").select("id,party_code,party_type,name,contact_person,phone,city,credit_limit,opening_balance,status").eq("tenant_id", tenantId).in("party_type", partyType === "supplier" ? ["supplier","both"] : ["customer","both"]).order("name").limit(250);
      if (error) setNotice(error.message); else setParties((data ?? []) as Party[]);
    }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId, module]);

  const filteredProducts = useMemo(() => products.filter(p => [p.name,p.sku,p.brand,p.barcode].some(v => (v ?? "").toLowerCase().includes(search.toLowerCase()))), [products,search]);
  const filteredParties = useMemo(() => parties.filter(p => [p.name,p.party_code,p.phone,p.city].some(v => (v ?? "").toLowerCase().includes(search.toLowerCase()))), [parties,search]);

  async function saveProduct(e: FormEvent) {
    e.preventDefault(); setSaving(true); setNotice("");
    const unitName = productForm.unit_name.trim() || "Piece";
    const unitSymbol = productForm.unit_symbol.trim() || "pcs";
    const { data: existingUnit, error: unitReadError } = await db.from("units_of_measure").select("id").eq("tenant_id", tenantId).eq("symbol", unitSymbol).maybeSingle();
    if (unitReadError) { setNotice(unitReadError.message); setSaving(false); return; }
    let unitId = existingUnit?.id as string | undefined;
    if (!unitId) {
      const { data: createdUnit, error: unitError } = await db.from("units_of_measure").insert({ tenant_id: tenantId, name: unitName, symbol: unitSymbol, unit_type: "quantity", decimal_places: 3 }).select("id").single();
      if (unitError) { setNotice(unitError.message); setSaving(false); return; }
      unitId = createdUnit.id;
    }
    const { data: createdProduct, error } = await db.from("products").insert({ tenant_id: tenantId, sku: productForm.sku.trim(), name: productForm.name.trim(), brand: productForm.brand.trim() || null, barcode: productForm.barcode.trim() || null, base_unit_id: unitId, min_stock: Number(productForm.min_stock) || 0, track_batch: productForm.track_batch, track_expiry: productForm.track_expiry }).select("id").single();
    if (error) setNotice(error.message);
    else {
      const { error: linkError } = await db.from("product_units").insert({ tenant_id: tenantId, product_id: createdProduct.id, unit_id: unitId, conversion_to_base: 1, is_purchase_unit: true, is_sales_unit: true });
      if (linkError) setNotice("Product saved, but the unit mapping could not be created: " + linkError.message);
      else setNotice("Product and base unit saved successfully.");
      setProductForm({ sku:"", name:"", brand:"", barcode:"", min_stock:"0", unit_name:"Piece", unit_symbol:"pcs", track_batch:false, track_expiry:false }); setShowForm(false); await load();
    }
    setSaving(false);
  }

  async function saveParty(e: FormEvent) {
    e.preventDefault(); setSaving(true); setNotice("");
    const { error } = await db.from("parties").insert({ tenant_id: tenantId, party_code: partyForm.party_code.trim(), party_type: partyType, name: partyForm.name.trim(), contact_person: partyForm.contact_person.trim() || null, phone: partyForm.phone.trim() || null, city: partyForm.city.trim() || null, credit_limit: Number(partyForm.credit_limit) || 0, opening_balance: Number(partyForm.opening_balance) || 0 });
    if (error) setNotice(error.message);
    else { setPartyForm({ party_code:"", party_type:partyType, name:"", contact_person:"", phone:"", city:"", credit_limit:"0", opening_balance:"0" }); setShowForm(false); await load(); }
    setSaving(false);
  }

  if (!isProducts && !isParties) return <section className="module-empty"><h2>{module}</h2><p>Is module ka database-backed workflow aglay development phase mein add hoga. Existing data aur database structure ko preserve kiya ja raha hai.</p></section>;

  return <section className="module-page">
    <div className="module-toolbar"><div><h2>{isProducts ? "Product Master" : partyType === "supplier" ? "Supplier Master" : "Customer Master"}</h2><p>{isProducts ? "Manage SKUs, brands, barcodes, and stock controls." : "Manage business contacts, credit limits, and opening balances."}</p></div><button className="primary-action" onClick={() => { setShowForm(!showForm); setNotice(""); }}>{showForm ? "Close form" : isProducts ? "+ Add product" : partyType === "supplier" ? "+ Add supplier" : "+ Add customer"}</button></div>
    {notice && <div className="notice">{notice}</div>}
    {showForm && (isProducts ? <form className="data-form" onSubmit={saveProduct}>
      <label>SKU / Item code<input required value={productForm.sku} onChange={e=>setProductForm({...productForm,sku:e.target.value})} /></label>
      <label>Product name<input required value={productForm.name} onChange={e=>setProductForm({...productForm,name:e.target.value})} /></label>
      <label>Brand<input value={productForm.brand} onChange={e=>setProductForm({...productForm,brand:e.target.value})} /></label>
      <label>Barcode<input value={productForm.barcode} onChange={e=>setProductForm({...productForm,barcode:e.target.value})} /></label>
      <label>Base unit name<input required value={productForm.unit_name} onChange={e=>setProductForm({...productForm,unit_name:e.target.value})} /></label>
      <label>Unit symbol<input required value={productForm.unit_symbol} onChange={e=>setProductForm({...productForm,unit_symbol:e.target.value})} /></label>
      <label>Minimum stock<input type="number" min="0" step="0.001" value={productForm.min_stock} onChange={e=>setProductForm({...productForm,min_stock:e.target.value})} /></label>
      <label className="check-label"><input type="checkbox" checked={productForm.track_batch} onChange={e=>setProductForm({...productForm,track_batch:e.target.checked})}/> Track batches</label>
      <label className="check-label"><input type="checkbox" checked={productForm.track_expiry} onChange={e=>setProductForm({...productForm,track_expiry:e.target.checked})}/> Track expiry</label>
      <button disabled={saving}>{saving ? "Saving…" : "Save product"}</button>
    </form> : <form className="data-form" onSubmit={saveParty}>
      <label>Party code<input required value={partyForm.party_code} onChange={e=>setPartyForm({...partyForm,party_code:e.target.value})}/></label>
      <label>{partyType === "supplier" ? "Supplier name" : "Customer name"}<input required value={partyForm.name} onChange={e=>setPartyForm({...partyForm,name:e.target.value})}/></label>
      <label>Contact person<input value={partyForm.contact_person} onChange={e=>setPartyForm({...partyForm,contact_person:e.target.value})}/></label>
      <label>Phone<input value={partyForm.phone} onChange={e=>setPartyForm({...partyForm,phone:e.target.value})}/></label>
      <label>City<input value={partyForm.city} onChange={e=>setPartyForm({...partyForm,city:e.target.value})}/></label>
      <label>Credit limit (PKR)<input type="number" min="0" step="0.01" value={partyForm.credit_limit} onChange={e=>setPartyForm({...partyForm,credit_limit:e.target.value})}/></label>
      <label>Opening balance (PKR)<input type="number" step="0.01" value={partyForm.opening_balance} onChange={e=>setPartyForm({...partyForm,opening_balance:e.target.value})}/></label>
      <button disabled={saving}>{saving ? "Saving…" : "Save record"}</button>
    </form>)}
    <div className="table-tools"><input placeholder={isProducts ? "Search SKU, product, brand or barcode…" : "Search code, name, phone or city…"} value={search} onChange={e=>setSearch(e.target.value)}/><span>{isProducts ? filteredProducts.length : filteredParties.length} records</span><button onClick={()=>void load()}>↻ Refresh</button></div>
    {loading ? <div className="table-empty">Loading records…</div> : isProducts ? <div className="data-table-wrap"><table className="data-table"><thead><tr><th>SKU</th><th>Product</th><th>Brand</th><th>Barcode</th><th>Min. stock</th><th>Tracking</th><th>Status</th></tr></thead><tbody>{filteredProducts.map(p=><tr key={p.id}><td>{p.sku}</td><td>{p.name}</td><td>{p.brand || "—"}</td><td>{p.barcode || "—"}</td><td>{p.min_stock}</td><td>{[p.track_batch && "Batch",p.track_expiry && "Expiry"].filter(Boolean).join(" · ") || "—"}</td><td><span className={p.is_active ? "status-active":"status-inactive"}>{p.is_active ? "Active":"Inactive"}</span></td></tr>)}{!filteredProducts.length&&<tr><td colSpan={7} className="table-empty">No products found. Add your first product.</td></tr>}</tbody></table></div> : <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Contact</th><th>Phone</th><th>City</th><th>Credit limit</th><th>Opening balance</th><th>Status</th></tr></thead><tbody>{filteredParties.map(p=><tr key={p.id}><td>{p.party_code}</td><td>{p.name}</td><td>{p.contact_person || "—"}</td><td>{p.phone || "—"}</td><td>{p.city || "—"}</td><td>{Number(p.credit_limit).toLocaleString("en-PK")}</td><td>{Number(p.opening_balance).toLocaleString("en-PK")}</td><td><span className={p.status === "active" ? "status-active":"status-inactive"}>{p.status}</span></td></tr>)}{!filteredParties.length&&<tr><td colSpan={8} className="table-empty">No records found. Add your first record.</td></tr>}</tbody></table></div>}
    <p className="module-footnote">Records are restricted to this company workspace by Supabase Row Level Security.</p>
  </section>;
}
