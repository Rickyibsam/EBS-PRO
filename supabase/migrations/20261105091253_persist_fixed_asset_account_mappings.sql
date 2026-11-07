-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.fixed_asset_account_mappings(
 tenant_id uuid primary key references public.organizations(id) on delete cascade,
 asset_cost_account_id uuid references public.chart_of_accounts(id),
 accumulated_depreciation_account_id uuid references public.chart_of_accounts(id),
 depreciation_expense_account_id uuid references public.chart_of_accounts(id),
 cash_account_id uuid references public.chart_of_accounts(id),
 disposal_gain_account_id uuid references public.chart_of_accounts(id),
 disposal_loss_account_id uuid references public.chart_of_accounts(id),
 updated_by uuid,
 updated_at timestamptz not null default now()
);
alter table public.fixed_asset_account_mappings enable row level security;
drop policy if exists fixed_asset_account_mappings_select on public.fixed_asset_account_mappings;
create policy fixed_asset_account_mappings_select on public.fixed_asset_account_mappings for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
drop policy if exists fixed_asset_account_mappings_insert on public.fixed_asset_account_mappings;
create policy fixed_asset_account_mappings_insert on public.fixed_asset_account_mappings for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
drop policy if exists fixed_asset_account_mappings_update on public.fixed_asset_account_mappings;
create policy fixed_asset_account_mappings_update on public.fixed_asset_account_mappings for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
grant select,insert,update on public.fixed_asset_account_mappings to authenticated;
