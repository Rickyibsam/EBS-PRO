-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.products
  add column if not exists cost_price numeric(18,4) not null default 0 check (cost_price >= 0),
  add column if not exists sale_price numeric(18,4) not null default 0 check (sale_price >= 0);

create table if not exists public.vendor_product_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  supplier_id uuid not null,
  product_id uuid not null,
  supplier_item_code text,
  purchase_cost numeric(18,4) not null default 0 check (purchase_cost >= 0),
  minimum_order_qty numeric(18,4) not null default 1 check (minimum_order_qty > 0),
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  is_preferred boolean not null default false,
  last_cost_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_product_catalog_supplier_fk foreign key (supplier_id,tenant_id) references public.parties(id,tenant_id),
  constraint vendor_product_catalog_product_fk foreign key (product_id,tenant_id) references public.products(id,tenant_id),
  constraint vendor_product_catalog_supplier_product_uq unique (tenant_id,supplier_id,product_id)
);
create index if not exists vendor_product_catalog_tenant_supplier_idx on public.vendor_product_catalog(tenant_id,supplier_id);
create index if not exists vendor_product_catalog_tenant_product_idx on public.vendor_product_catalog(tenant_id,product_id);
alter table public.vendor_product_catalog enable row level security;
grant select,insert,update,delete on public.vendor_product_catalog to authenticated;
drop policy if exists vendor_product_catalog_select on public.vendor_product_catalog;
drop policy if exists vendor_product_catalog_insert on public.vendor_product_catalog;
drop policy if exists vendor_product_catalog_update on public.vendor_product_catalog;
drop policy if exists vendor_product_catalog_delete on public.vendor_product_catalog;
create policy vendor_product_catalog_select on public.vendor_product_catalog for select to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase','accounts']));
create policy vendor_product_catalog_insert on public.vendor_product_catalog for insert to authenticated
with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy vendor_product_catalog_update on public.vendor_product_catalog for update to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']))
with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy vendor_product_catalog_delete on public.vendor_product_catalog for delete to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin']));
