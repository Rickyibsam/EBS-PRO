-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

-- EBS PRO | Wholesale Distribution & Supply Chain ERP
-- Initial secure multi-tenant foundation. All monetary values are PKR unless configured otherwise.
create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  slug text not null unique,
  phone text,
  email text,
  tax_number text,
  address text,
  city text,
  country text not null default 'Pakistan',
  currency char(3) not null default 'PKR',
  timezone text not null default 'Asia/Karachi',
  fiscal_year_start date,
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','manager','accounts','purchase','sales','order_booker','warehouse','cashier','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id,user_id)
);
create index tenant_memberships_user_idx on public.tenant_memberships(user_id,tenant_id) where is_active;

create or replace function public.is_tenant_member(p_tenant_id uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.tenant_memberships m
    where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid()) and m.is_active
  );
$$;

create or replace function public.has_tenant_role(p_tenant_id uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.tenant_memberships m
    where m.tenant_id = p_tenant_id and m.user_id = (select auth.uid())
      and m.is_active and m.role = any(p_roles)
  );
$$;

create or replace function public.create_tenant(
  p_name text, p_slug text, p_city text default null, p_phone text default null
)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_tenant_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Business name is required'; end if;
  if p_slug !~ '^[a-z0-9][a-z0-9-]{2,49}$' then raise exception 'Use a valid 3-50 character lowercase slug'; end if;
  insert into public.organizations(name,slug,city,phone)
  values (trim(p_name),lower(p_slug),nullif(trim(p_city),''),nullif(trim(p_phone),''))
  returning id into v_tenant_id;
  insert into public.tenant_memberships(tenant_id,user_id,role)
  values (v_tenant_id,auth.uid(),'owner');
  insert into public.branches(tenant_id,name,code,is_default)
  values (v_tenant_id,'Main Branch','MAIN',true);
  return v_tenant_id;
end;
$$;

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  address text,
  city text,
  phone text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code), unique(id,tenant_id)
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null,
  name text not null,
  code text not null,
  address text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,code), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id)
);

create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  parent_id uuid references public.product_categories(id) on delete set null,
  name text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id,name), unique(id,tenant_id)
);

create table public.units_of_measure (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  symbol text not null,
  unit_type text not null default 'quantity',
  decimal_places smallint not null default 0 check(decimal_places between 0 and 4),
  unique(tenant_id,symbol), unique(id,tenant_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid,
  sku text not null,
  barcode text,
  name text not null,
  description text,
  brand text,
  base_unit_id uuid,
  purchase_tax_rate numeric(6,3) not null default 0,
  sales_tax_rate numeric(6,3) not null default 0,
  min_stock numeric(18,4) not null default 0,
  reorder_level numeric(18,4) not null default 0,
  track_batch boolean not null default false,
  track_expiry boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,sku), unique(id,tenant_id),
  foreign key(category_id,tenant_id) references public.product_categories(id,tenant_id),
  foreign key(base_unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);
create unique index products_barcode_unique on public.products(tenant_id,barcode) where barcode is not null;

create table public.product_units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null,
  unit_id uuid not null,
  conversion_to_base numeric(18,6) not null check(conversion_to_base > 0),
  is_purchase_unit boolean not null default true,
  is_sales_unit boolean not null default true,
  barcode text,
  created_at timestamptz not null default now(),
  unique(product_id,unit_id),
  foreign key(product_id,tenant_id) references public.products(id,tenant_id) on delete cascade,
  foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  party_code text not null,
  party_type text not null check(party_type in ('customer','supplier','both')),
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  city text,
  tax_number text,
  credit_limit numeric(18,2) not null default 0,
  opening_balance numeric(18,2) not null default 0,
  payment_terms_days integer not null default 0,
  status text not null default 'active' check(status in ('active','inactive','blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,party_code), unique(id,tenant_id)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  branch_id uuid,
  employee_code text not null,
  full_name text not null,
  phone text,
  job_title text,
  employment_status text not null default 'active',
  created_at timestamptz not null default now(),
  unique(tenant_id,employee_code), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id)
);

create table public.sales_routes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  route_code text not null,
  name text not null,
  area_description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id,route_code), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id)
);

create table public.route_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid not null,
  employee_id uuid not null,
  assigned_from date not null default current_date,
  assigned_to date,
  created_at timestamptz not null default now(),
  foreign key(route_id,tenant_id) references public.sales_routes(id,tenant_id),
  foreign key(employee_id,tenant_id) references public.employees(id,tenant_id),
  check(assigned_to is null or assigned_to >= assigned_from)
);

create table public.route_customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid not null,
  customer_id uuid not null,
  visit_order integer not null default 0,
  visit_day smallint check(visit_day between 0 and 6),
  foreign key(route_id,tenant_id) references public.sales_routes(id,tenant_id),
  foreign key(customer_id,tenant_id) references public.parties(id,tenant_id),
  unique(route_id,customer_id)
);

create table public.booker_visits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid,
  booker_employee_id uuid,
  customer_id uuid not null,
  visit_at timestamptz not null default now(),
  visit_status text not null check(visit_status in ('visited','not_available','closed','order_taken','payment_collected','no_order')),
  latitude numeric(10,7),
  longitude numeric(10,7),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key(route_id,tenant_id) references public.sales_routes(id,tenant_id),
  foreign key(booker_employee_id,tenant_id) references public.employees(id,tenant_id),
  foreign key(customer_id,tenant_id) references public.parties(id,tenant_id)
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  warehouse_id uuid,
  supplier_id uuid not null,
  po_number text not null,
  order_date date not null default current_date,
  expected_date date,
  status text not null default 'draft' check(status in ('draft','submitted','approved','part_received','received','cancelled')),
  subtotal numeric(18,2) not null default 0,
  tax_total numeric(18,2) not null default 0,
  discount_total numeric(18,2) not null default 0,
  grand_total numeric(18,2) not null default 0,
  notes text,
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,po_number), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id),
  foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id),
  foreign key(supplier_id,tenant_id) references public.parties(id,tenant_id)
);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,4) not null check(quantity > 0),
  conversion_to_base numeric(18,6) not null check(conversion_to_base > 0),
  unit_cost numeric(18,4) not null default 0,
  tax_rate numeric(6,3) not null default 0,
  discount_amount numeric(18,2) not null default 0,
  line_total numeric(18,2) not null default 0,
  received_base_quantity numeric(18,4) not null default 0,
  foreign key(purchase_order_id,tenant_id) references public.purchase_orders(id,tenant_id) on delete cascade,
  foreign key(product_id,tenant_id) references public.products(id,tenant_id),
  foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid,
  warehouse_id uuid not null,
  grn_number text not null,
  received_date date not null default current_date,
  supplier_invoice_no text,
  status text not null default 'draft' check(status in ('draft','posted','cancelled')),
  notes text,
  received_by uuid references auth.users(id),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(tenant_id,grn_number), unique(id,tenant_id),
  foreign key(purchase_order_id,tenant_id) references public.purchase_orders(id,tenant_id),
  foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id)
);

create table public.goods_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  goods_receipt_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,4) not null check(quantity > 0),
  conversion_to_base numeric(18,6) not null check(conversion_to_base > 0),
  accepted_quantity numeric(18,4) not null check(accepted_quantity >= 0),
  rejected_quantity numeric(18,4) not null default 0 check(rejected_quantity >= 0),
  unit_cost numeric(18,4) not null default 0,
  batch_number text,
  expiry_date date,
  foreign key(goods_receipt_id,tenant_id) references public.goods_receipts(id,tenant_id) on delete cascade,
  foreign key(product_id,tenant_id) references public.products(id,tenant_id),
  foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  warehouse_id uuid,
  customer_id uuid not null,
  route_id uuid,
  booker_employee_id uuid,
  order_number text not null,
  order_source text not null default 'backoffice' check(order_source in ('backoffice','order_booker','pos','online')),
  order_date timestamptz not null default now(),
  required_delivery_date date,
  status text not null default 'draft' check(status in ('draft','submitted','approved','allocated','dispatched','delivered','invoiced','cancelled')),
  subtotal numeric(18,2) not null default 0,
  tax_total numeric(18,2) not null default 0,
  discount_total numeric(18,2) not null default 0,
  grand_total numeric(18,2) not null default 0,
  notes text,
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,order_number), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id),
  foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id),
  foreign key(customer_id,tenant_id) references public.parties(id,tenant_id),
  foreign key(route_id,tenant_id) references public.sales_routes(id,tenant_id),
  foreign key(booker_employee_id,tenant_id) references public.employees(id,tenant_id)
);

create table public.sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  sales_order_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  quantity numeric(18,4) not null check(quantity > 0),
  conversion_to_base numeric(18,6) not null check(conversion_to_base > 0),
  unit_price numeric(18,4) not null default 0,
  tax_rate numeric(6,3) not null default 0,
  discount_amount numeric(18,2) not null default 0,
  line_total numeric(18,2) not null default 0,
  foreign key(sales_order_id,tenant_id) references public.sales_orders(id,tenant_id) on delete cascade,
  foreign key(product_id,tenant_id) references public.products(id,tenant_id),
  foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  sales_order_id uuid not null,
  warehouse_id uuid not null,
  delivery_number text not null,
  delivery_date date not null default current_date,
  driver_name text,
  vehicle_number text,
  status text not null default 'pending' check(status in ('pending','picked','dispatched','delivered','failed','returned')),
  delivered_at timestamptz,
  proof_of_delivery_url text,
  notes text,
  created_at timestamptz not null default now(),
  unique(tenant_id,delivery_number), unique(id,tenant_id),
  foreign key(sales_order_id,tenant_id) references public.sales_orders(id,tenant_id),
  foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id)
);

create table public.delivery_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  delivery_id uuid not null,
  product_id uuid not null,
  quantity_base numeric(18,4) not null check(quantity_base > 0),
  picked_quantity_base numeric(18,4) not null default 0,
  delivered_quantity_base numeric(18,4) not null default 0,
  foreign key(delivery_id,tenant_id) references public.deliveries(id,tenant_id) on delete cascade,
  foreign key(product_id,tenant_id) references public.products(id,tenant_id)
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  warehouse_id uuid not null,
  product_id uuid not null,
  movement_type text not null check(movement_type in ('opening','purchase_receipt','sale_dispatch','sales_return','purchase_return','transfer_in','transfer_out','adjustment','damage')),
  reference_type text,
  reference_id uuid,
  quantity_in numeric(18,4) not null default 0 check(quantity_in >= 0),
  quantity_out numeric(18,4) not null default 0 check(quantity_out >= 0),
  unit_cost numeric(18,4) not null default 0,
  batch_number text,
  expiry_date date,
  movement_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  notes text,
  created_at timestamptz not null default now(),
  check ((quantity_in > 0 and quantity_out = 0) or (quantity_out > 0 and quantity_in = 0)),
  foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id),
  foreign key(product_id,tenant_id) references public.products(id,tenant_id)
);
create index stock_movements_balance_idx on public.stock_movements(tenant_id,warehouse_id,product_id,movement_at);

create table public.price_lists (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  price_type text not null check(price_type in ('retail','wholesale','distributor','special')),
  is_default boolean not null default false,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  unique(tenant_id,name), unique(id,tenant_id)
);

create table public.product_prices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  price_list_id uuid not null,
  product_id uuid not null,
  unit_id uuid not null,
  price numeric(18,4) not null check(price >= 0),
  min_quantity numeric(18,4) not null default 1,
  foreign key(price_list_id,tenant_id) references public.price_lists(id,tenant_id) on delete cascade,
  foreign key(product_id,tenant_id) references public.products(id,tenant_id),
  foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id),
  unique(price_list_id,product_id,unit_id,min_quantity)
);

create table public.customer_price_lists (
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null,
  price_list_id uuid not null,
  primary key(customer_id,price_list_id),
  foreign key(customer_id,tenant_id) references public.parties(id,tenant_id),
  foreign key(price_list_id,tenant_id) references public.price_lists(id,tenant_id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  party_id uuid,
  payment_number text not null,
  payment_type text not null check(payment_type in ('receipt','payment')),
  payment_date date not null default current_date,
  method text not null check(method in ('cash','bank','cheque','online','other')),
  amount numeric(18,2) not null check(amount > 0),
  reference_no text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(tenant_id,payment_number), unique(id,tenant_id),
  foreign key(party_id,tenant_id) references public.parties(id,tenant_id)
);

create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  parent_id uuid,
  account_code text not null,
  account_name text not null,
  account_type text not null check(account_type in ('asset','liability','equity','income','expense')),
  is_control_account boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id,account_code), unique(id,tenant_id),
  foreign key(parent_id,tenant_id) references public.chart_of_accounts(id,tenant_id)
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  journal_number text not null,
  entry_date date not null default current_date,
  source_type text,
  source_id uuid,
  narration text not null,
  status text not null default 'draft' check(status in ('draft','posted','reversed')),
  created_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(tenant_id,journal_number), unique(id,tenant_id)
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  journal_entry_id uuid not null,
  account_id uuid not null,
  party_id uuid,
  debit numeric(18,2) not null default 0 check(debit >= 0),
  credit numeric(18,2) not null default 0 check(credit >= 0),
  memo text,
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0)),
  foreign key(journal_entry_id,tenant_id) references public.journal_entries(id,tenant_id) on delete cascade,
  foreign key(account_id,tenant_id) references public.chart_of_accounts(id,tenant_id),
  foreign key(party_id,tenant_id) references public.parties(id,tenant_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  expense_number text not null,
  expense_date date not null default current_date,
  expense_head_id uuid,
  description text not null,
  amount numeric(18,2) not null check(amount > 0),
  payment_method text not null default 'cash',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(tenant_id,expense_number), unique(id,tenant_id),
  foreign key(branch_id,tenant_id) references public.branches(id,tenant_id),
  foreign key(expense_head_id,tenant_id) references public.chart_of_accounts(id,tenant_id)
);

create table public.document_sequences (
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  document_type text not null,
  prefix text not null,
  next_number bigint not null default 1,
  padding smallint not null default 6,
  primary key(tenant_id,document_type,branch_id)
);

create table public.app_settings (
  tenant_id uuid primary key references public.organizations(id) on delete cascade,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  ip_address inet,
  created_at timestamptz not null default now()
);
create index audit_logs_tenant_created_idx on public.audit_logs(tenant_id,created_at desc);

-- RLS for all tenant-owned ERP tables. Access is granted only to active tenant members.
do $$
declare t text;
begin
  foreach t in array array[
    'branches','warehouses','product_categories','units_of_measure','products','product_units',
    'parties','employees','sales_routes','route_assignments','route_customers','booker_visits',
    'purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines',
    'sales_orders','sales_order_lines','deliveries','delivery_lines','stock_movements',
    'price_lists','product_prices','customer_price_lists','payments','chart_of_accounts',
    'journal_entries','journal_lines','expenses','document_sequences','app_settings','audit_logs'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('create policy tenant_member_select on public.%I for select to authenticated using (public.is_tenant_member(tenant_id))',t);
    execute format('create policy tenant_operator_write on public.%I for all to authenticated using (public.has_tenant_role(tenant_id, array[''owner'',''admin'',''manager'',''accounts'',''purchase'',''sales'',''order_booker'',''warehouse'',''cashier''])) with check (public.has_tenant_role(tenant_id, array[''owner'',''admin'',''manager'',''accounts'',''purchase'',''sales'',''order_booker'',''warehouse'',''cashier'']))',t);
  end loop;
end $$;

alter table public.organizations enable row level security;
create policy tenant_members_read_org on public.organizations for select to authenticated using (public.is_tenant_member(id));
create policy tenant_admin_update_org on public.organizations for update to authenticated using (public.has_tenant_role(id,array['owner','admin'])) with check (public.has_tenant_role(id,array['owner','admin']));

alter table public.tenant_memberships enable row level security;
create policy members_read_memberships on public.tenant_memberships for select to authenticated using (public.is_tenant_member(tenant_id));
create policy owners_manage_memberships on public.tenant_memberships for all to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin'])) with check (public.has_tenant_role(tenant_id,array['owner','admin']));

alter table public.user_profiles enable row level security;
create policy users_read_own_profile on public.user_profiles for select to authenticated using (id = (select auth.uid()));
create policy users_update_own_profile on public.user_profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy users_insert_own_profile on public.user_profiles for insert to authenticated with check (id = (select auth.uid()));

-- Create a profile on new auth sign-up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_profiles(id,full_name)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''))
  on conflict(id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Tenant bootstrap: one default warehouse is created with the main branch.
create or replace function public.bootstrap_tenant_warehouse()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.warehouses(tenant_id,branch_id,name,code,is_default)
  values(new.tenant_id,new.id,'Main Warehouse','MAIN-WH',true);
  return new;
end;
$$;
create trigger on_branch_created
after insert on public.branches
for each row execute procedure public.bootstrap_tenant_warehouse();

-- updated_at triggers
do $$
declare t text;
begin
  foreach t in array array['organizations','user_profiles','branches','warehouses','products','parties','purchase_orders','sales_orders','sales_routes','app_settings'] loop
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t);
  end loop;
end $$;

grant execute on function public.create_tenant(text,text,text,text) to authenticated;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid,text[]) to authenticated;
