-- Create the van stock movement ledger before migrations that add idempotency
-- and define transfer/delivery RPCs. The live schema was previously created
-- outside the checked-in migration history; keep this migration compatible
-- with that existing table shape.
create table if not exists public.van_stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  vehicle_number text not null,
  employee_id uuid,
  product_id uuid not null,
  movement_type text not null check (movement_type in ('load','sale','return','unload','adjustment')),
  reference_type text,
  reference_id uuid,
  quantity_in numeric not null default 0 check (quantity_in >= 0),
  quantity_out numeric not null default 0 check (quantity_out >= 0),
  unit_cost numeric not null default 0,
  batch_number text,
  expiry_date date,
  movement_at timestamptz not null default now(),
  notes text,
  created_by uuid references auth.users(id),
  idempotency_key text,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id),
  foreign key (tenant_id, employee_id)
    references public.employees(tenant_id, id)
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
