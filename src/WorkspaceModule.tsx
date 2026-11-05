import { FormEvent, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Product = { id: string; sku: string; name: string; brand: string | null; barcode: string | null; is_active: boolean; min_stock: number; track_expiry: boolean; track_batch: boolean };
type Party = { id: string; party_code: string; party_type: string; name: string; contact_person: string | null; phone: string | null; city: string | null; credit_limit: number; opening_balance: number; status: string };

export default function WorkspaceModule({ db, tenantId, module, currentRole }: { db: SupabaseClient; tenantId: string; module: string; currentRole: string }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [categories,setCategories] = useState<Array<{id:string;name:string}>>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [search, setSearch] = useState("");
  const [categoryName,setCategoryName]=useState("");
  const [showForm, setShowForm] = useState(false);
  const [productForm, setProductForm] = useState({ sku: "", name: "", brand: "", barcode: "", category_id:"", min_stock: "0", unit_name: "Piece", unit_symbol: "pcs", alternate_unit_name:"", alternate_unit_symbol:"", conversion_to_base:"1", alternate_purchase:true, alternate_sales:true, track_batch: false, track_expiry: false });
  const [partyForm, setPartyForm] = useState({ party_code: "", party_type: "customer", name: "", contact_person: "", phone: "", city: "", credit_limit: "0", opening_balance: "0" });

  const isProducts = module === "Products";
  const isParties = module === "Customers" || module === "Suppliers";
  const partyType = module === "Suppliers" ? "supplier" : "customer";

  async function load() {
    setLoading(true); setNotice("");
    if (isProducts) {
      const [productResult,categoryResult] = await Promise.all([db.from("products").select("id,sku,name,brand,barcode,is_active,min_stock,track_expiry,track_batch").eq("tenant_id", tenantId).order("name").limit(250),db.from("product_categories").select("id,name").eq("tenant_id",tenantId).eq("is_active",true).order("name")]);
      if (productResult.error||categoryResult.error) setNotice(productResult.error?.message||categoryResult.error?.message||"Product master could not be loaded."); else {setProducts((productResult.data ?? []) as Product[]);setCategories(categoryResult.data??[]);}
    } else if (isParties) {
      const { data, error } = await db.from("parties").select("id,party_code,party_type,name,contact_person,phone,city,credit_limit,opening_balance,status").eq("tenant_id", tenantId).in("party_type", partyType === "supplier" ? ["supplier","both"] : ["customer","both"]).order("name").limit(250);
      if (error) setNotice(error.message); else setParties((data ?? []) as Party[]);
    }
    setLoading(false);
  }

  useEffect(() => { void load(); }, [tenantId, module]);

  const filteredProducts = useMemo(() => products.filter(p => [p.name,p.sku,p.brand,p.barcode].some(v => (v ?? "").toLowerCase().includes(search.toLowerCase()))), [products,search]);
  const filteredParties = useMemo(() => parties.filter(p => [p.name,p.party_code,p.phone,p.city].some(v => (v ?? "").toLowerCase().includes(search.toLowerCase()))), [parties,search]);

  async function toggleActive(id:string,active:boolean){
    setNotice("");
    const result=isProducts
      ? await db.from("products").update({is_active:!active}).eq("id",id).eq("tenant_id",tenantId)
      : await db.from("parties").update({status:active?"inactive":"active"}).eq("id",id).eq("tenant_id",tenantId);
    if(result.error){setNotice(result.error.message);return;}
    setNotice(isProducts?"Product status updated.":"Party status updated.");await load();
  }

  async function saveCategory(){
    const name=categoryName.trim();if(!name){setNotice("Enter a category name.");return;}
    const code=name.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,40);
    const {data,error}=await db.from("product_categories").insert({tenant_id:tenantId,name,code,is_active:true}).select("id,name").single();
    if(error){setNotice(error.message);return;}
    setCategories(old=>[...old,data].sort((a,b)=>a.name.localeCompare(b.name)));setProductForm(old=>({...old,category_id:data.id}));setCategoryName("");setNotice("Product category created.");
  }

  async function saveProduct(e: FormEvent) {
    e.preventDefault(); setSaving(true); setNotice("");
    const unitName = productForm.unit_name.trim() || "Piece";
    const unitSymbol = productForm.unit_symbol.trim() || "pcs";
    if(!productForm.sku.trim()||!productForm.name.trim()) {setNotice("SKU and product name are required.");setSaving(false);return;}
    const conversion=Number(productForm.conversion_to_base);
    if(productForm.alternate_unit_symbol.trim()&&(!Number.isFinite(conversion)||conversion<=0)){setNotice("Alternate unit conversion must be greater than zero.");setSaving(false);return;}
    if(productForm.alternate_unit_symbol.trim().toLowerCase()===unitSymbol.toLowerCase()){setNotice("Alternate unit symbol must differ from the base unit symbol.");setSaving(false);return;}
    const { data: existingUnit, error: unitReadError } = await db.from("units_of_measure").select("id").eq("tenant_id", tenantId).eq("symbol", unitSymbol).maybeSingle();
    if (unitReadError) { setNotice(unitReadError.message); setSaving(false); return; }
    let unitId = existingUnit?.id as string | undefined;
    if (!unitId) {
      const { data: createdUnit, error: unitError } = await db.from("units_of_measure").insert({ tenant_id: tenantId, name: unitName, symbol: unitSymbol, unit_type: "quantity", decimal_places: 3 }).select("id").single();
      if (unitError) { setNotice(unitError.message); setSaving(false); return; }
      unitId = createdUnit.id;
    }
    const { data: createdProduct, error } = await db.from("products").insert({ tenant_id: tenantId, sku: productForm.sku.trim(), name: productForm.name.trim(), brand: productForm.brand.trim() || null, barcode: productForm.barcode.trim() || null, category_id:productForm.category_id||null, base_unit_id: unitId, min_stock: Number(productForm.min_stock) || 0, track_batch: productForm.track_batch, track_expiry: productForm.track_expiry }).select("id").single();
    if (error) setNotice(error.message);
    else {
      const { error: linkError } = await db.from("product_units").insert({ tenant_id: tenantId, product_id: createdProduct.id, unit_id: unitId, conversion_to_base: 1, is_purchase_unit: true, is_sales_unit: true });
      if (linkError) {setNotice("Product saved, but base unit mapping failed: " + linkError.message);}
      else if(productForm.alternate_unit_symbol.trim()){
        const altSymbol=productForm.alternate_unit_symbol.trim();
        let {data:altUnit,error:altReadError}=await db.from("units_of_measure").select("id").eq("tenant_id",tenantId).eq("symbol",altSymbol).maybeSingle();
        if(altReadError){setNotice("Product and base unit saved, but alternate unit lookup failed: "+altReadError.message);setSaving(false);await load();return;}
        if(!altUnit){const made=await db.from("units_of_measure").insert({tenant_id:tenantId,name:productForm.alternate_unit_name.trim()||altSymbol,symbol:altSymbol,unit_type:"quantity",decimal_places:3}).select("id").single();if(made.error){setNotice("Product and base unit saved, but alternate unit creation failed: "+made.error.message);setSaving(false);await load();return;}altUnit=made.data;}
        const altLink=await db.from("product_units").insert({tenant_id:tenantId,product_id:createdProduct.id,unit_id:altUnit.id,conversion_to_base:conversion,is_purchase_unit:productForm.alternate_purchase,is_sales_unit:productForm.alternate_sales});
        if(altLink.error){setNotice("Product and base unit saved, but alternate conversion failed: "+altLink.error.message);setSaving(false);await load();return;}
        setNotice("Product, base unit and alternate unit conversion saved.");
      }else setNotice("Product and base unit saved successfully.");
      setProductForm({ sku:"", name:"", brand:"", barcode:"", category_id:"", min_stock:"0", unit_name:"Piece", unit_symbol:"pcs", alternate_unit_name:"", alternate_unit_symbol:"", conversion_to_base:"1", alternate_purchase:true, alternate_sales:true, track_batch:false, track_expiry:false }); setShowForm(false); await load();
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
    <div className="module-toolbar"><div><h2>{isProducts ? "Product Master" : partyType === "supplier" ? "Supplier Master" : "Customer Master"}</h2><p>{isProducts ? "Manage SKUs, brands, barcodes, and stock controls." : "Manage business contacts, credit limits, and opening balances."}</p></div>{(isProducts?["owner","admin","manager","purchase"]:partyType==="supplier"?["owner","admin","manager","purchase"]:["owner","admin","manager","sales","purchase"]).includes(currentRole)&&<button className="primary-action" onClick={() => { setShowForm(!showForm); setNotice(""); }}>{showForm ? "Close form" : isProducts ? "+ Add product" : partyType === "supplier" ? "+ Add supplier" : "+ Add customer"}</button>}</div>
    {notice && <div className="notice">{notice}</div>}
    {showForm && (isProducts ? <form className="data-form" onSubmit={saveProduct}>
      <label>SKU / Item code<input required value={productForm.sku} onChange={e=>setProductForm({...productForm,sku:e.target.value})} /></label>
      <label>Product name<input required value={productForm.name} onChange={e=>setProductForm({...productForm,name:e.target.value})} /></label>
      <label>Brand<input value={productForm.brand} onChange={e=>setProductForm({...productForm,brand:e.target.value})} /></label>
      <label>Barcode<input value={productForm.barcode} onChange={e=>setProductForm({...productForm,barcode:e.target.value})} /></label>
      <label>Category<select value={productForm.category_id} onChange={e=>setProductForm({...productForm,category_id:e.target.value})}><option value="">Uncategorised</option>{categories.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select></label>{["owner","admin","manager","purchase"].includes(currentRole)&&<div className="form-grid"><label>New category<input value={categoryName} onChange={e=>setCategoryName(e.target.value)} placeholder="Beverages / Grocery"/></label><button type="button" onClick={()=>void saveCategory()}>Add category</button></div>}
      <label>Base unit name<input required value={productForm.unit_name} onChange={e=>setProductForm({...productForm,unit_name:e.target.value})} /></label>
      <label>Unit symbol<input required value={productForm.unit_symbol} onChange={e=>setProductForm({...productForm,unit_symbol:e.target.value})} /></label>
      <h3>Optional alternate unit / carton conversion</h3>
      <label>Alternate unit name<input value={productForm.alternate_unit_name} onChange={e=>setProductForm({...productForm,alternate_unit_name:e.target.value})} placeholder="Carton / Box"/></label>
      <label>Alternate unit symbol<input value={productForm.alternate_unit_symbol} onChange={e=>setProductForm({...productForm,alternate_unit_symbol:e.target.value})} placeholder="ctn"/></label>
      <label>1 alternate unit = base units<input type="number" min="0.000001" step="0.000001" value={productForm.conversion_to_base} onChange={e=>setProductForm({...productForm,conversion_to_base:e.target.value})}/></label>
      <label className="check-label"><input type="checkbox" checked={productForm.alternate_purchase} onChange={e=>setProductForm({...productForm,alternate_purchase:e.target.checked})}/> Use alternate unit for purchases</label>
      <label className="check-label"><input type="checkbox" checked={productForm.alternate_sales} onChange={e=>setProductForm({...productForm,alternate_sales:e.target.checked})}/> Use alternate unit for sales</label>
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
    {loading ? <div className="table-empty">Loading records…</div> : isProducts ? <div className="data-table-wrap"><table className="data-table"><thead><tr><th>SKU</th><th>Product</th><th>Brand</th><th>Barcode</th><th>Min. stock</th><th>Tracking</th><th>Status</th><th>Action</th></tr></thead><tbody>{filteredProducts.map(p=><tr key={p.id}><td>{p.sku}</td><td>{p.name}</td><td>{p.brand || "—"}</td><td>{p.barcode || "—"}</td><td>{p.min_stock}</td><td>{[p.track_batch && "Batch",p.track_expiry && "Expiry"].filter(Boolean).join(" · ") || "—"}</td><td><span className={p.is_active ? "status-active":"status-inactive"}>{p.is_active ? "Active":"Inactive"}</span></td><td>{["owner","admin","manager","purchase"].includes(currentRole)?<button onClick={()=>void toggleActive(p.id,p.is_active)}>{p.is_active?"Deactivate":"Activate"}</button>:"—"}</td></tr>)}{!filteredProducts.length&&<tr><td colSpan={8} className="table-empty">No products found. Add your first product.</td></tr>}</tbody></table></div> : <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Code</th><th>Name</th><th>Contact</th><th>Phone</th><th>City</th><th>Credit limit</th><th>Opening balance</th><th>Status</th><th>Action</th></tr></thead><tbody>{filteredParties.map(p=><tr key={p.id}><td>{p.party_code}</td><td>{p.name}</td><td>{p.contact_person || "—"}</td><td>{p.phone || "—"}</td><td>{p.city || "—"}</td><td>{Number(p.credit_limit).toLocaleString("en-PK")}</td><td>{Number(p.opening_balance).toLocaleString("en-PK")}</td><td><span className={p.status === "active" ? "status-active":"status-inactive"}>{p.status}</span></td><td>{["owner","admin","manager","accounts","purchase","sales"].includes(currentRole)?<button onClick={()=>void toggleActive(p.id,p.status==="active")}>{p.status==="active"?"Deactivate":"Activate"}</button>:"—"}</td></tr>)}{!filteredParties.length&&<tr><td colSpan={9} className="table-empty">No records found. Add your first record.</td></tr>}</tbody></table></div>}
    <p className="module-footnote">Records are restricted to this company workspace by Supabase Row Level Security.</p>
  </section>;
}
