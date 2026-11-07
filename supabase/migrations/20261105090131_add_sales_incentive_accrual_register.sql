-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.sales_incentive_accruals(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 sales_target_id uuid not null references public.sales_targets(id) on delete cascade,
 period_start date not null,
 period_end date not null,
 scope_type text not null check(scope_type in ('employee','vendor','brand','product')),
 employee_id uuid,
 vendor_id uuid,
 brand text,
 product_id uuid,
 actual_value numeric not null default 0,
 target_value numeric not null,
 earned_amount numeric not null default 0,
 status text not null default 'accrued' check(status in ('accrued','settled','reversed')),
 calculated_at timestamptz not null default now(),
 created_by uuid,
 unique(tenant_id,sales_target_id)
);
alter table public.sales_incentive_accruals enable row level security;
drop policy if exists sales_incentive_accruals_select on public.sales_incentive_accruals;
create policy sales_incentive_accruals_select on public.sales_incentive_accruals for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
drop policy if exists sales_incentive_accruals_insert on public.sales_incentive_accruals;
create policy sales_incentive_accruals_insert on public.sales_incentive_accruals for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales']));
drop policy if exists sales_incentive_accruals_update on public.sales_incentive_accruals;
create policy sales_incentive_accruals_update on public.sales_incentive_accruals for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
grant select,insert,update on public.sales_incentive_accruals to authenticated;
create index if not exists sales_incentive_accruals_period_idx on public.sales_incentive_accruals(tenant_id,period_start,period_end,status);
