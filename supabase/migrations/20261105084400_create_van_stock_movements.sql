-- Create the van stock movement ledger before migrations that add idempotency
-- and define transfer/delivery RPCs. This table was referenced by those
-- migrations but was missing from the checked-in migration history.
create table if not exists public.van_stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  vehicle_number text not null,
  employee_id uuid,
  product_id uuid not null,
  movement_type text not null check (movement_type in ('load','unload','sale','return')),
  reference_type text not null,
  reference_id uuid,
  quantity_in numeric(18,4) not null default 0 check (quantity_in >= 0),
  quantity_out numeric(18,4) not null default 0 check (quantity_out >= 0),
  unit_cost numeric(18,4) not null default 0 check (unit_cost >= 0),
  batch_number text,
  expiry_date date,
  idempotency_key text,
  notes text,
  created_by uuid references auth.users(id),
  movement_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (product_id, tenant_id)
    references public.products(id, tenant_id),
  foreign key (employee_id, tenant_id)
    references public.employees(id, tenant_id),
  check ((quantity_in > 0 and quantity_out = 0) or
         (quantity_out > 0 and quantity_in = 0))
);

create index if not exists van_stock_movements_tenant_vehicle_product_idx
  on public.van_stock_movements(tenant_id, vehicle_number, product_id, movement_at);
create index if not exists van_stock_movements_reference_idx
  on public.van_stock_movements(tenant_id, reference_type, reference_id);

alter table public.van_stock_movements enable row level security;

drop policy if exists van_stock_movements_read on public.van_stock_movements;
create policy van_stock_movements_read
  on public.van_stock_movements for select to authenticated
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager','warehouse']));

drop policy if exists van_stock_movements_insert on public.van_stock_movements;
create policy van_stock_movements_insert
  on public.van_stock_movements for insert to authenticated
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager','warehouse'])
    and (created_by is null or created_by = (select auth.uid())));

grant select, insert on public.van_stock_movements to authenticated;
