-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare v_definition text;
begin
 select pg_get_functiondef('public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid)'::regprocedure) into v_definition;
 v_definition:=replace(v_definition,
  'if not exists(select 1 from public.chart_of_accounts where id=p_asset_cost_account_id',
  'if p_asset_cost_account_id=p_accumulated_account_id or p_asset_cost_account_id=p_cash_account_id or p_accumulated_account_id=p_cash_account_id then raise exception ''Fixed asset cost, accumulated depreciation and proceeds accounts must be different.''; end if; if not exists(select 1 from public.chart_of_accounts where id=p_asset_cost_account_id');
 execute v_definition;
end;
$$;
