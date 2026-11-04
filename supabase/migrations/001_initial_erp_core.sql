-- EBS-PRO | Initial multi-tenant ERP database
-- Paste into Supabase SQL Editor for the CONFIRMED EBS-PRO project.
-- Safe baseline: creates tables/indexes and enables tenant-isolated RLS.
-- Do not place service_role keys or database passwords in frontend code.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  slug text not null unique,
  email text,
  phone text,
  address text,
  currency_code char(3) not null default 'PKR',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'staff' check (role in ('owner','admin','manager','accountant','sales','booker','warehouse','delivery','hr','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text not null,
  name text not null,
  phone text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  code text not null,
  name text not null,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  parent_id uuid references public.product_categories(id) on delete set null,
  name text not null,
  code text,
  created_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table if not exists public.units_of_measure (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  abbreviation text not null,
  decimal_places smallint not null default 2 check (decimal_places between 0 and 4),
  unique (organization_id, abbreviation)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.product_categories(id) on delete set null,
  base_unit_id uuid references public.units_of_measure(id) on delete restrict,
  sku text not null,
  barcode text,
  name text not null,
  description text,
  image_url text,
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  sale_price numeric(14,2) not null default 0 check (sale_price >= 0),
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);
create unique index if not exists products_org_barcode_uidx
  on public.products(organization_id, barcode) where barcode is not null;

create table if not exists public.parties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  party_type text not null check (party_type in ('customer','supplier','both')),
  code text not null,
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  tax_number text,
  credit_limit numeric(14,2) not null default 0 check (credit_limit >= 0),
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  employee_code text not null,
  full_name text not null,
  phone text,
  email text,
  job_title text,
  employment_status text not null default 'active' check (employment_status in ('active','inactive','left')),
  joining_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, employee_code)
);

create table if not exists public.sales_routes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  route_code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, route_code)
);

create table if not exists public.route_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid not null references public.sales_routes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_on date not null default current_date,
  unique (organization_id, route_id, user_id, assigned_on)
);

create table if not exists public.route_customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid not null references public.sales_routes(id) on delete cascade,
  customer_id uuid not null references public.parties(id) on delete cascade,
  visit_order integer not null default 0,
  unique (organization_id, route_id, customer_id)
);

create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  customer_id uuid not null references public.parties(id) on delete restrict,
  route_id uuid references public.sales_routes(id) on delete set null,
  booked_by uuid references auth.users(id) on delete set null,
  order_number text not null,
  order_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','submitted','approved','processing','dispatched','delivered','cancelled')),
  subtotal numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, order_number)
);

create table if not exists public.sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  free_quantity numeric(14,3) not null default 0 check (free_quantity >= 0),
  line_total numeric(14,2) not null default 0
);

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  supplier_id uuid not null references public.parties(id) on delete restrict,
  order_number text not null,
  order_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','submitted','approved','part_received','received','cancelled')),
  grand_total numeric(14,2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, order_number)
);

create table if not exists public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  received_quantity numeric(14,3) not null default 0 check (received_quantity >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  line_total numeric(14,2) not null default 0
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening','purchase','sale','sale_return','purchase_return','transfer_in','transfer_out','adjustment')),
  quantity_in numeric(14,3) not null default 0 check (quantity_in >= 0),
  quantity_out numeric(14,3) not null default 0 check (quantity_out >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reference_type text,
  reference_id uuid,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (quantity_in = 0 or quantity_out = 0)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  party_id uuid references public.parties(id) on delete restrict,
  payment_number text not null,
  payment_type text not null check (payment_type in ('receipt','payment')),
  payment_method text not null default 'cash' check (payment_method in ('cash','bank','cheque','online')),
  amount numeric(14,2) not null check (amount > 0),
  payment_date date not null default current_date,
  reference_number text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id, payment_number)
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists memberships_user_org_idx on public.tenant_memberships(user_id, organization_id) where is_active;
create index if not exists products_org_name_idx on public.products(organization_id, name);
create index if not exists parties_org_name_idx on public.parties(organization_id, name);
create index if not exists sales_orders_org_date_idx on public.sales_orders(organization_id, order_date desc);
create index if not exists stock_movements_org_product_idx on public.stock_movements(organization_id, product_id, warehouse_id);
create index if not exists payments_org_date_idx on public.payments(organization_id, payment_date desc);

-- RLS: each tenant can only access rows belonging to an organization
-- where the signed-in user has an active membership.
alter table public.organizations enable row level security;
alter table public.user_profiles enable row level security;
alter table public.tenant_memberships enable row level security;

create policy "profile_select_own" on public.user_profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profile_insert_own" on public.user_profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profile_update_own" on public.user_profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "membership_select_own" on public.tenant_memberships
  for select to authenticated using (user_id = (select auth.uid()));

create policy "organization_select_member" on public.organizations
  for select to authenticated using (
    exists (select 1 from public.tenant_memberships m
      where m.organization_id = id and m.user_id = (select auth.uid()) and m.is_active)
  );

do $$
declare t text;
begin
  foreach t in array array[
    'branches','warehouses','product_categories','units_of_measure','products',
    'parties','employees','sales_routes','route_assignments','route_customers',
    'sales_orders','sales_order_lines','purchase_orders','purchase_order_lines',
    'stock_movements','payments','audit_logs'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using ' ||
      '(exists (select 1 from public.tenant_memberships m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active)) ' ||
      'with check (exists (select 1 from public.tenant_memberships m where m.organization_id = organization_id and m.user_id = (select auth.uid()) and m.is_active))',
      t || '_tenant_access', t
    );
  end loop;
end $$;

-- Updated-at triggers
do $$
declare t text;
begin
  foreach t in array array[
    'organizations','user_profiles','branches','warehouses','products',
    'parties','employees','sales_orders','purchase_orders'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t);
  end loop;
end $$;

-- No anonymous access is granted. Membership creation / invitations must be
-- performed by a trusted server-side onboarding function, never by the browser.
