-- Restore budget headers and lines before the indexes below. The hosted schema
-- contains these tables, but their original CREATE TABLE statements were absent
-- from the checked-in migration history.

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  budget_name text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','approved','closed')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint budgets_period_check check (period_end >= period_start)
);

create table if not exists public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  account_id uuid not null references public.chart_of_accounts(id),
  branch_id uuid references public.branches(id),
  budget_amount numeric(14,2) not null check (budget_amount >= 0),
  notes text,
  constraint budget_lines_budget_account_branch_key
    unique (tenant_id,budget_id,account_id,branch_id)
);

create index if not exists budgets_tenant_period_idx
  on public.budgets(tenant_id,period_start,period_end);

alter table public.budgets enable row level security;
drop policy if exists budgets_tenant_access on public.budgets;
create policy budgets_tenant_access on public.budgets
  for all to authenticated
  using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]))
  with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]));
grant select,insert,update,delete on public.budgets to authenticated;

alter table public.budget_lines enable row level security;
drop policy if exists budget_lines_tenant_access on public.budget_lines;
create policy budget_lines_tenant_access on public.budget_lines
  for all to authenticated
  using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]))
  with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[]));
grant select,insert,update,delete on public.budget_lines to authenticated;

-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create index if not exists asset_depreciation_entries_asset_idx on public.asset_depreciation_entries(asset_id);
create index if not exists asset_depreciation_entries_journal_idx on public.asset_depreciation_entries(journal_entry_id);
create index if not exists asset_depreciation_entries_created_by_idx on public.asset_depreciation_entries(created_by);
create index if not exists fixed_assets_created_by_idx on public.fixed_assets(created_by);
create index if not exists budgets_approved_by_idx on public.budgets(approved_by);
create index if not exists budgets_created_by_idx on public.budgets(created_by);
create index if not exists budget_lines_budget_idx on public.budget_lines(budget_id);
create index if not exists budget_lines_account_idx on public.budget_lines(account_id);
create index if not exists budget_lines_branch_idx on public.budget_lines(branch_id);
create index if not exists van_stock_movements_employee_idx on public.van_stock_movements(employee_id);
create index if not exists van_stock_movements_product_idx on public.van_stock_movements(product_id);
create index if not exists van_stock_movements_created_by_idx on public.van_stock_movements(created_by);
create index if not exists sales_incentive_accruals_target_idx on public.sales_incentive_accruals(sales_target_id);
create index if not exists sales_incentive_accruals_employee_idx on public.sales_incentive_accruals(employee_id);
create index if not exists sales_incentive_accruals_vendor_idx on public.sales_incentive_accruals(vendor_id);
create index if not exists sales_incentive_accruals_product_idx on public.sales_incentive_accruals(product_id);
create index if not exists sales_incentive_accruals_created_by_idx on public.sales_incentive_accruals(created_by);
