-- Reconstruct the original van stock ledger table before adding its idempotency key.
-- The hosted project contains this table, but its original CREATE TABLE statement was
-- missing from the checked-in migration history. Keep the definition idempotent so a
-- clean database replay can build the same table before later delivery migrations use it.

create table if not exists public.van_stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  vehicle_number text not null,
  employee_id uuid references public.employees(id),
  product_id uuid not null references public.products(id),
  movement_type text not null check (
    movement_type in ('load','sale','return','unload','adjustment')
  ),
  reference_type text,
  reference_id uuid,
  quantity_in numeric(14,3) not null default 0 check (quantity_in >= 0),
  quantity_out numeric(14,3) not null default 0 check (quantity_out >= 0),
  unit_cost numeric(14,4) not null default 0,
  batch_number text,
  expiry_date date,
  movement_at timestamptz not null default now(),
  notes text,
  created_by uuid references auth.users(id),
  idempotency_key text,
  constraint van_stock_movements_check
    check ((quantity_in = 0) <> (quantity_out = 0))
);

create index if not exists van_stock_movements_employee_idx
  on public.van_stock_movements(employee_id);
create index if not exists van_stock_movements_product_idx
  on public.van_stock_movements(product_id);
create index if not exists van_stock_tenant_vehicle_time_idx
  on public.van_stock_movements(tenant_id,vehicle_number,movement_at);

alter table public.van_stock_movements enable row level security;
drop policy if exists van_stock_movements_tenant_access on public.van_stock_movements;
create policy van_stock_movements_tenant_access
  on public.van_stock_movements
  for all to authenticated
  using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]))
  with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]));

grant select,insert,update,delete on public.van_stock_movements to authenticated;

alter table public.van_stock_movements
  add column if not exists idempotency_key text;

create unique index if not exists van_stock_movements_tenant_idempotency_uidx
  on public.van_stock_movements(tenant_id,idempotency_key)
  where idempotency_key is not null;
