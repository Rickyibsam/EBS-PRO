-- Cash-flow activity classification by chart-of-accounts mapping.
create table if not exists public.cash_flow_account_mappings(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 account_id uuid not null references public.chart_of_accounts(id) on delete cascade,
 classification text not null check(classification in ('operating','investing','financing')),
 updated_by uuid,
 updated_at timestamptz not null default now(),
 unique(tenant_id,account_id)
);
alter table public.cash_flow_account_mappings enable row level security;
drop policy if exists cash_flow_account_mappings_select on public.cash_flow_account_mappings;
create policy cash_flow_account_mappings_select on public.cash_flow_account_mappings for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
drop policy if exists cash_flow_account_mappings_insert on public.cash_flow_account_mappings;
create policy cash_flow_account_mappings_insert on public.cash_flow_account_mappings for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
drop policy if exists cash_flow_account_mappings_update on public.cash_flow_account_mappings;
create policy cash_flow_account_mappings_update on public.cash_flow_account_mappings for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
grant select,insert,update on public.cash_flow_account_mappings to authenticated;
create index if not exists cash_flow_account_mappings_account_idx on public.cash_flow_account_mappings(account_id);
create index if not exists cash_flow_account_mappings_updated_by_idx on public.cash_flow_account_mappings(updated_by);
