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
