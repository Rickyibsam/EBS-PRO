-- EBS-PRO | Phase 2: HR, returns and warehouse transfers
-- Target: Supabase project vastupafhvlarlllvkao
-- This migration EXTENDS the existing 35-table schema. It does not drop or
-- truncate existing tables. Run only after reviewing the project backup.

create table if not exists public.employee_attendance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  attendance_date date not null default current_date,
  check_in_at timestamptz,
  check_out_at timestamptz,
  status text not null default 'present'
    check (status in ('present','absent','late','half_day','leave','holiday')),
  check_in_latitude numeric(10,7),
  check_in_longitude numeric(10,7),
  check_out_latitude numeric(10,7),
  check_out_longitude numeric(10,7),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, employee_id, attendance_date)
);

create table if not exists public.employee_leaves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  leave_type text not null,
  start_date date not null,
  end_date date not null,
  reason text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled')),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  payroll_number text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft'
    check (status in ('draft','approved','paid','cancelled')),
  total_gross numeric(14,2) not null default 0,
  total_deductions numeric(14,2) not null default 0,
  total_net numeric(14,2) not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, payroll_number),
  check (period_end >= period_start)
);

create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete restrict,
  basic_salary numeric(14,2) not null default 0,
  allowances numeric(14,2) not null default 0,
  overtime_amount numeric(14,2) not null default 0,
  deductions numeric(14,2) not null default 0,
  net_salary numeric(14,2) not null default 0,
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','paid')),
  paid_at timestamptz,
  unique (tenant_id, payroll_run_id, employee_id)
);

create table if not exists public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  customer_id uuid not null references public.parties(id) on delete restrict,
  original_sales_order_id uuid references public.sales_orders(id) on delete set null,
  return_number text not null,
  return_date date not null default current_date,
  reason text,
  status text not null default 'draft'
    check (status in ('draft','approved','posted','rejected')),
  total_amount numeric(14,2) not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, return_number)
);

create table if not exists public.sales_return_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  sales_return_id uuid not null references public.sales_returns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_base numeric(14,3) not null check (quantity_base > 0),
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  line_total numeric(14,2) not null default 0,
  condition text not null default 'resalable'
    check (condition in ('resalable','damaged','expired'))
);

create table if not exists public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  supplier_id uuid not null references public.parties(id) on delete restrict,
  original_purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  return_number text not null,
  return_date date not null default current_date,
  reason text,
  status text not null default 'draft'
    check (status in ('draft','approved','posted','rejected')),
  total_amount numeric(14,2) not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, return_number)
);

create table if not exists public.purchase_return_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  purchase_return_id uuid not null references public.purchase_returns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_base numeric(14,3) not null check (quantity_base > 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  line_total numeric(14,2) not null default 0,
  batch_number text,
  expiry_date date
);

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  transfer_number text not null,
  from_warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  to_warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  transfer_date date not null default current_date,
  status text not null default 'draft'
    check (status in ('draft','approved','in_transit','received','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  received_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, transfer_number),
  check (from_warehouse_id <> to_warehouse_id)
);

create table if not exists public.stock_transfer_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  stock_transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_base numeric(14,3) not null check (quantity_base > 0),
  batch_number text,
  expiry_date date
);

create index if not exists employee_attendance_tenant_date_idx
  on public.employee_attendance(tenant_id, attendance_date desc);
create index if not exists employee_leaves_tenant_dates_idx
  on public.employee_leaves(tenant_id, start_date, end_date);
create index if not exists payroll_runs_tenant_period_idx
  on public.payroll_runs(tenant_id, period_start desc);
create index if not exists sales_returns_tenant_date_idx
  on public.sales_returns(tenant_id, return_date desc);
create index if not exists purchase_returns_tenant_date_idx
  on public.purchase_returns(tenant_id, return_date desc);
create index if not exists stock_transfers_tenant_date_idx
  on public.stock_transfers(tenant_id, transfer_date desc);

-- Tenant and role-based access. The existing project already provides
-- public.has_tenant_role(uuid,text[]) and role names in tenant_memberships.
do $$
declare
  t text;
  write_roles text[];
  read_roles text[];
begin
  foreach t in array array['employee_attendance','employee_leaves','payroll_runs','payroll_items'] loop
    execute format('alter table public.%I enable row level security', t);
    read_roles := array['owner','admin','manager','accounts','hr'];
    write_roles := array['owner','admin','manager','hr'];
    execute format('create policy %I on public.%I for select to authenticated using (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_read', t, read_roles);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_insert', t, write_roles);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_tenant_role(tenant_id, %L::text[])) with check (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_update', t, write_roles, write_roles);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_delete', t, array['owner','admin']);
  end loop;

  foreach t in array array['sales_returns','sales_return_lines','purchase_returns','purchase_return_lines','stock_transfers','stock_transfer_lines'] loop
    execute format('alter table public.%I enable row level security', t);
    read_roles := array['owner','admin','manager','accounts','purchase','sales','warehouse'];
    write_roles := array['owner','admin','manager','accounts','purchase','sales','warehouse'];
    execute format('create policy %I on public.%I for select to authenticated using (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_read', t, read_roles);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_insert', t, write_roles);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_tenant_role(tenant_id, %L::text[])) with check (public.has_tenant_role(tenant_id, %L::text[]))',
      t || '_tenant_update', t, write_roles, write_roles);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_tenant_role(tenant_id, ARRAY[''owner'',''admin'']::text[]))',
      t || '_tenant_delete', t);
  end loop;
end $$;
