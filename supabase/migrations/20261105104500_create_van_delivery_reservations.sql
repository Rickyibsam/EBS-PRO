-- Restore the van delivery reservation table to the checked-in migration history.
-- This table already exists in production but was missing from clean database replay.

-- Ensure the composite tenant keys required by reservation foreign keys exist
-- in a clean migration replay as well as on the hosted schema.
create unique index if not exists tenant_fk_uq_41e5772da4560071d172
  on public.deliveries(tenant_id, id);
create unique index if not exists tenant_fk_uq_b78bca17f77dda47bf07
  on public.delivery_lines(tenant_id, id);
create unique index if not exists tenant_fk_uq_b51c904c7f7a587fa42b
  on public.products(tenant_id, id);

create table if not exists public.van_delivery_reservations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  delivery_id uuid not null,
  delivery_line_id uuid not null,
  vehicle_number text not null,
  product_id uuid not null,
  reserved_quantity numeric not null check (reserved_quantity > 0),
  status text not null default 'active'
    check (status in ('active','consumed','released')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, delivery_id)
    references public.deliveries(tenant_id, id) on delete cascade,
  foreign key (tenant_id, delivery_line_id)
    references public.delivery_lines(tenant_id, id) on delete cascade,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id),
  unique (tenant_id, delivery_line_id)
);

create index if not exists idx_fk_van_delivery_reservations_39532107f9
  on public.van_delivery_reservations(product_id);
create index if not exists idx_fk_van_delivery_reservations_796d313456
  on public.van_delivery_reservations(delivery_id);
create index if not exists idx_fk_van_delivery_reservations_d25dc06dc0
  on public.van_delivery_reservations(created_by);
create index if not exists idx_fk_van_delivery_reservations_d9ee69e6f3
  on public.van_delivery_reservations(delivery_line_id);
create index if not exists tenant_fk_idx_68ce02eef185a593eaa6
  on public.van_delivery_reservations(tenant_id, product_id);
create index if not exists tenant_fk_idx_f45072614c431973682f
  on public.van_delivery_reservations(tenant_id, delivery_id);
create index if not exists van_delivery_reservations_active_vehicle_product_idx
  on public.van_delivery_reservations(tenant_id, vehicle_number, product_id)
  where status='active';

alter table public.van_delivery_reservations enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='van_delivery_reservations'
       and policyname='van_delivery_reservations_select'
  ) then
    create policy van_delivery_reservations_select
      on public.van_delivery_reservations for select to authenticated
      using (public.has_tenant_role(
        tenant_id, array['owner','admin','manager','warehouse']::text[]
      ));
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='van_delivery_reservations'
       and policyname='van_delivery_reservations_insert'
  ) then
    create policy van_delivery_reservations_insert
      on public.van_delivery_reservations for insert to authenticated
      with check (public.has_tenant_role(
        tenant_id, array['owner','admin','manager','warehouse']::text[]
      ));
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='van_delivery_reservations'
       and policyname='van_delivery_reservations_update'
  ) then
    create policy van_delivery_reservations_update
      on public.van_delivery_reservations for update to authenticated
      using (public.has_tenant_role(
        tenant_id, array['owner','admin','manager','warehouse']::text[]
      ))
      with check (public.has_tenant_role(
        tenant_id, array['owner','admin','manager','warehouse']::text[]
      ));
  end if;
end;
$$;

revoke all on table public.van_delivery_reservations from public, anon;
grant select, insert, update on table public.van_delivery_reservations to authenticated;
