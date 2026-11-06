-- Catch up straight-line depreciation through the actual disposal date before calculating gain/loss.
create or replace function public.dispose_fixed_asset(
 p_asset_id uuid,p_disposal_date date,p_proceeds numeric,p_asset_cost_account_id uuid,
 p_accumulated_account_id uuid,p_cash_account_id uuid,p_gain_account_id uuid,p_loss_account_id uuid
) returns jsonb
language plpgsql
set search_path=pg_catalog,public,private,auth
as $function$
declare
 v_user uuid:=auth.uid(); v_asset public.fixed_assets%rowtype;
 v_mapping public.fixed_asset_account_mappings%rowtype;
 v_accum numeric; v_book numeric; v_gain numeric; v_loss numeric;
 v_journal uuid; v_no text; v_month date; v_month_end date; v_depreciation_end date;
 v_existing public.asset_depreciation_entries%rowtype;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.'; end if;
 if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot dispose this asset.' using errcode='42501'; end if;
 if v_asset.status not in ('active','fully_depreciated') then raise exception 'Asset is already disposed or inactive.'; end if;
 if p_disposal_date is null or p_disposal_date<v_asset.acquisition_date or p_proceeds is null or p_proceeds<0 then raise exception 'Invalid disposal date or proceeds.'; end if;
 select * into v_mapping from public.fixed_asset_account_mappings where tenant_id=v_asset.tenant_id;
 if not found or v_mapping.depreciation_expense_account_id is null or v_mapping.accumulated_depreciation_account_id is null then raise exception 'Save depreciation expense and accumulated depreciation mappings before disposal.'; end if;
 if p_accumulated_account_id is distinct from v_mapping.accumulated_depreciation_account_id then raise exception 'Disposal accumulated depreciation account must match the company mapping.'; end if;
 if v_mapping.asset_cost_account_id is not null and p_asset_cost_account_id is distinct from v_mapping.asset_cost_account_id then raise exception 'Disposal asset cost account must match the company mapping.'; end if;
 if v_mapping.cash_account_id is not null and p_cash_account_id is distinct from v_mapping.cash_account_id then raise exception 'Disposal cash/bank account must match the company mapping.'; end if;
 if exists(select 1 from public.asset_depreciation_entries d where d.tenant_id=v_asset.tenant_id and d.asset_id=v_asset.id and d.posted and d.period_end>p_disposal_date) then
  raise exception 'Posted depreciation extends beyond disposal date. Reverse/correct future-period depreciation first.';
 end if;
 v_depreciation_end:=least(p_disposal_date,(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months-1))::date);
 for v_month in select generate_series(date_trunc('month',v_asset.acquisition_date)::date,date_trunc('month',v_depreciation_end)::date,interval '1 month')::date loop
  v_month_end:=least((v_month+interval '1 month - 1 day')::date,v_depreciation_end);
  select * into v_existing from public.asset_depreciation_entries d
  where d.tenant_id=v_asset.tenant_id and d.asset_id=v_asset.id and d.period_start<=v_month_end and d.period_end>=v_month
  order by d.period_start desc limit 1;
  if found then
   if not v_existing.posted or v_existing.period_end<v_month_end then raise exception 'Existing depreciation for % is incomplete or unposted. Reconcile before disposal.',v_month; end if;
  else
   perform public.post_asset_monthly_depreciation(v_asset.id,v_month,v_month_end,v_mapping.depreciation_expense_account_id,v_mapping.accumulated_depreciation_account_id);
  end if;
 end loop;
 select coalesce(sum(depreciation_amount),0) into v_accum from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and posted;
 v_accum:=least(v_accum,v_asset.acquisition_cost-v_asset.salvage_value);
 v_book:=greatest(v_asset.salvage_value,v_asset.acquisition_cost-v_accum);
 v_gain:=greatest(0,p_proceeds-v_book); v_loss:=greatest(0,v_book-p_proceeds);
 if p_asset_cost_account_id=p_accumulated_account_id or p_asset_cost_account_id=p_cash_account_id or p_accumulated_account_id=p_cash_account_id then raise exception 'Asset cost, accumulated depreciation and proceeds accounts must differ.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_asset_cost_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select the fixed asset cost account.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_accumulated_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select accumulated depreciation account.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_cash_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select cash/bank proceeds account.'; end if;
 if v_gain>0 and not exists(select 1 from public.chart_of_accounts where id=p_gain_account_id and tenant_id=v_asset.tenant_id and account_type='income' and is_active) then raise exception 'Select an active disposal gain income account.'; end if;
 if v_loss>0 and not exists(select 1 from public.chart_of_accounts where id=p_loss_account_id and tenant_id=v_asset.tenant_id and account_type='expense' and is_active) then raise exception 'Select an active disposal loss expense account.'; end if;
 v_no:='EBS-DSP-'||right(replace(gen_random_uuid()::text,'-',''),12);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_asset.tenant_id,v_no,p_disposal_date,'asset_disposal',v_asset.id,'Disposal: '||v_asset.asset_code||' - '||v_asset.asset_name,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_asset.tenant_id,v_journal,p_cash_account_id,p_proceeds,0,'Disposal proceeds · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_accumulated_account_id,v_accum,0,'Remove accumulated depreciation · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_asset_cost_account_id,0,v_asset.acquisition_cost,'Remove asset historical cost · '||v_asset.asset_code);
 if v_gain>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_asset.tenant_id,v_journal,p_gain_account_id,0,v_gain,'Gain on disposal · '||v_asset.asset_code); end if;
 if v_loss>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_asset.tenant_id,v_journal,p_loss_account_id,v_loss,0,'Loss on disposal · '||v_asset.asset_code); end if;
 perform public.post_journal_entry(v_journal);
 update public.fixed_assets set status='disposed',disposal_date=p_disposal_date,disposal_amount=p_proceeds where id=v_asset.id and tenant_id=v_asset.tenant_id;
 return jsonb_build_object('success',true,'journal_entry_id',v_journal,'book_value',v_book,'accumulated_depreciation',v_accum,'gain',v_gain,'loss',v_loss,'depreciation_catch_up',true,'posted',true);
end;
$function$;
