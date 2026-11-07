-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create index if not exists fixed_asset_account_mappings_asset_cost_idx on public.fixed_asset_account_mappings(asset_cost_account_id);
create index if not exists fixed_asset_account_mappings_accum_idx on public.fixed_asset_account_mappings(accumulated_depreciation_account_id);
create index if not exists fixed_asset_account_mappings_expense_idx on public.fixed_asset_account_mappings(depreciation_expense_account_id);
create index if not exists fixed_asset_account_mappings_cash_idx on public.fixed_asset_account_mappings(cash_account_id);
create index if not exists fixed_asset_account_mappings_gain_idx on public.fixed_asset_account_mappings(disposal_gain_account_id);
create index if not exists fixed_asset_account_mappings_loss_idx on public.fixed_asset_account_mappings(disposal_loss_account_id);
create index if not exists fixed_asset_account_mappings_updated_by_idx on public.fixed_asset_account_mappings(updated_by);
do $$
begin
 if not exists(select 1 from pg_constraint where conname='fixed_asset_account_mappings_distinct_accounts_check') then
  alter table public.fixed_asset_account_mappings add constraint fixed_asset_account_mappings_distinct_accounts_check
  check (
   asset_cost_account_id is null or accumulated_depreciation_account_id is null or cash_account_id is null
   or (asset_cost_account_id<>accumulated_depreciation_account_id and asset_cost_account_id<>cash_account_id and accumulated_depreciation_account_id<>cash_account_id)
  );
 end if;
end;
$$;
