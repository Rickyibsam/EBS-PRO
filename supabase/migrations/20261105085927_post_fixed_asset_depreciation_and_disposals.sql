-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create unique index if not exists asset_depreciation_period_uidx
on public.asset_depreciation_entries(tenant_id,asset_id,period_start,period_end);

create or replace function public.post_asset_monthly_depreciation(
 p_asset_id uuid,p_period_start date,p_period_end date,
 p_expense_account_id uuid,p_accumulated_account_id uuid
) returns jsonb
language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid(); v_asset public.fixed_assets%rowtype;
 v_existing public.asset_depreciation_entries%rowtype;
 v_month_days integer; v_overlap_days integer; v_monthly numeric;
 v_prior numeric; v_amount numeric; v_journal uuid; v_no text;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.'; end if;
 if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot post asset depreciation.' using errcode='42501'; end if;
 if p_period_start is null or p_period_end is null or p_period_start>p_period_end or date_trunc('month',p_period_start)::date<>date_trunc('month',p_period_end)::date then raise exception 'Select one valid calendar month.'; end if;
 if v_asset.status<>'active' then raise exception 'Only active assets can be depreciated.'; end if;
 select * into v_existing from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and period_start=p_period_start and period_end=p_period_end;
 if found then return jsonb_build_object('success',true,'already_posted',v_existing.posted,'journal_entry_id',v_existing.journal_entry_id,'amount',v_existing.depreciation_amount); end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_expense_account_id and tenant_id=v_asset.tenant_id and account_type='expense' and is_active) then raise exception 'Select an active expense account for depreciation.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_accumulated_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select an active asset/contra-asset account for accumulated depreciation.'; end if;
 select coalesce(sum(depreciation_amount),0) into v_prior from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and posted;
 v_month_days:=extract(day from (date_trunc('month',p_period_start)+interval '1 month - 1 day'))::integer;
 v_overlap_days:=greatest(0,(least(p_period_end,(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months-1))) - greatest(p_period_start,v_asset.acquisition_date) + 1));
 v_monthly:=(v_asset.acquisition_cost-v_asset.salvage_value)/v_asset.useful_life_months;
 v_amount:=round(least(greatest(0,v_asset.acquisition_cost-v_asset.salvage_value-v_prior),v_monthly*v_overlap_days/v_month_days),2);
 if v_amount<=0 then raise exception 'No depreciation is due for the selected period.'; end if;
 v_no:='EBS-DEP-'||right(replace(gen_random_uuid()::text,'-',''),12);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(v_asset.tenant_id,v_no,p_period_end,'asset_depreciation',v_asset.id,'Monthly depreciation: '||v_asset.asset_code||' - '||v_asset.asset_name,'draft',v_user) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_asset.tenant_id,v_journal,p_expense_account_id,v_amount,0,'Depreciation expense · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_accumulated_account_id,0,v_amount,'Accumulated depreciation · '||v_asset.asset_code);
 perform public.post_journal_entry(v_journal);
 insert into public.asset_depreciation_entries(tenant_id,asset_id,period_start,period_end,depreciation_amount,journal_entry_id,posted,created_by)
 values(v_asset.tenant_id,v_asset.id,p_period_start,p_period_end,v_amount,v_journal,true,v_user);
 if v_prior+v_amount>=v_asset.acquisition_cost-v_asset.salvage_value-0.005 then
  update public.fixed_assets set status='fully_depreciated' where id=v_asset.id and tenant_id=v_asset.tenant_id;
 end if;
 return jsonb_build_object('success',true,'journal_entry_id',v_journal,'amount',v_amount,'posted',true);
end;
$$;

create or replace function public.dispose_fixed_asset(
 p_asset_id uuid,p_disposal_date date,p_proceeds numeric,
 p_asset_cost_account_id uuid,p_accumulated_account_id uuid,
 p_cash_account_id uuid,p_gain_account_id uuid,p_loss_account_id uuid
) returns jsonb
language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid(); v_asset public.fixed_assets%rowtype;
 v_accum numeric; v_book numeric; v_gain numeric; v_loss numeric;
 v_journal uuid; v_no text;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.'; end if;
 if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot dispose this asset.' using errcode='42501'; end if;
 if v_asset.status not in ('active','fully_depreciated') then raise exception 'Asset is already disposed or inactive.'; end if;
 if p_disposal_date is null or p_disposal_date<v_asset.acquisition_date or p_proceeds<0 then raise exception 'Invalid disposal date or proceeds.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_asset_cost_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select the fixed asset cost account.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_accumulated_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select accumulated depreciation account.'; end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_cash_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select cash/bank proceeds account.'; end if;
 select coalesce(sum(depreciation_amount),0) into v_accum from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and posted;
 v_accum:=least(v_accum,v_asset.acquisition_cost-v_asset.salvage_value);
 v_book:=greatest(0,v_asset.acquisition_cost-v_accum);
 v_gain:=greatest(0,p_proceeds-v_book); v_loss:=greatest(0,v_book-p_proceeds);
 if v_gain>0 and not exists(select 1 from public.chart_of_accounts where id=p_gain_account_id and tenant_id=v_asset.tenant_id and account_type='income' and is_active) then raise exception 'Select an active disposal gain income account.'; end if;
 if v_loss>0 and not exists(select 1 from public.chart_of_accounts where id=p_loss_account_id and tenant_id=v_asset.tenant_id and account_type='expense' and is_active) then raise exception 'Select an active disposal loss expense account.'; end if;
 v_no:='EBS-DSP-'||right(replace(gen_random_uuid()::text,'-',''),12);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(v_asset.tenant_id,v_no,p_disposal_date,'asset_disposal',v_asset.id,'Disposal: '||v_asset.asset_code||' - '||v_asset.asset_name,'draft',v_user) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_asset.tenant_id,v_journal,p_cash_account_id,p_proceeds,0,'Disposal proceeds · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_accumulated_account_id,v_accum,0,'Remove accumulated depreciation · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_asset_cost_account_id,0,v_asset.acquisition_cost,'Remove asset historical cost · '||v_asset.asset_code);
 if v_gain>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_asset.tenant_id,v_journal,p_gain_account_id,0,v_gain,'Gain on disposal · '||v_asset.asset_code); end if;
 if v_loss>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_asset.tenant_id,v_journal,p_loss_account_id,v_loss,0,'Loss on disposal · '||v_asset.asset_code); end if;
 perform public.post_journal_entry(v_journal);
 update public.fixed_assets set status='disposed',disposal_date=p_disposal_date,disposal_amount=p_proceeds where id=v_asset.id and tenant_id=v_asset.tenant_id;
 return jsonb_build_object('success',true,'journal_entry_id',v_journal,'book_value',v_book,'gain',v_gain,'loss',v_loss,'posted',true);
end;
$$;
revoke all on function public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid) from public,anon;
revoke all on function public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid) to authenticated;
grant execute on function public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid) to authenticated;
