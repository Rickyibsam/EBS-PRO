create or replace function public.post_asset_monthly_depreciation(
 p_asset_id uuid,p_period_start date,p_period_end date,p_expense_account_id uuid,p_accumulated_account_id uuid
) returns jsonb language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
 v_user uuid:=auth.uid();v_asset public.fixed_assets%rowtype;v_existing public.asset_depreciation_entries%rowtype;
 v_month_days integer;v_overlap_days integer;v_monthly numeric;v_prior numeric;v_amount numeric;v_journal uuid;v_no text;
begin
 if v_user is null then raise exception 'Authentication required.';end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.';end if;
 if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot post asset depreciation.' using errcode='42501';end if;
 if p_period_start is null or p_period_end is null or p_period_start>p_period_end or date_trunc('month',p_period_start)::date<>date_trunc('month',p_period_end)::date then raise exception 'Select one valid calendar month.';end if;
 if v_asset.status<>'active' then raise exception 'Only active assets can be depreciated.';end if;
 select * into v_existing from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and period_start=p_period_start and period_end=p_period_end;
 if found then return jsonb_build_object('success',true,'already_posted',v_existing.posted,'journal_entry_id',v_existing.journal_entry_id,'amount',v_existing.depreciation_amount);end if;
 if exists(select 1 from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and posted and period_start<=p_period_end and period_end>=p_period_start) then
  raise exception 'This asset already has a posted depreciation entry overlapping the selected period. A second journal for the same month is blocked.';
 end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_expense_account_id and tenant_id=v_asset.tenant_id and account_type='expense' and is_active) then raise exception 'Select an active expense account for depreciation.';end if;
 if not exists(select 1 from public.chart_of_accounts where id=p_accumulated_account_id and tenant_id=v_asset.tenant_id and account_type='asset' and is_active) then raise exception 'Select an active asset/contra-asset account for accumulated depreciation.';end if;
 select coalesce(sum(depreciation_amount),0) into v_prior from public.asset_depreciation_entries where tenant_id=v_asset.tenant_id and asset_id=v_asset.id and posted;
 v_month_days:=extract(day from (date_trunc('month',p_period_start)+interval '1 month - 1 day'))::integer;
 v_overlap_days:=greatest(0,(least(p_period_end,(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months-1))-greatest(p_period_start,v_asset.acquisition_date)+1));
 v_monthly:=(v_asset.acquisition_cost-v_asset.salvage_value)/v_asset.useful_life_months;
 v_amount:=round(least(greatest(0,v_asset.acquisition_cost-v_asset.salvage_value-v_prior),v_monthly*v_overlap_days/v_month_days),2);
 if v_amount<=0 then raise exception 'No depreciation is due for the selected period.';end if;
 v_no:='EBS-DEP-'||right(replace(gen_random_uuid()::text,'-',''),12);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(v_asset.tenant_id,v_no,p_period_end,'asset_depreciation',v_asset.id,'Monthly depreciation: '||v_asset.asset_code||' - '||v_asset.asset_name,'draft',v_user) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_asset.tenant_id,v_journal,p_expense_account_id,v_amount,0,'Depreciation expense · '||v_asset.asset_code),
       (v_asset.tenant_id,v_journal,p_accumulated_account_id,0,v_amount,'Accumulated depreciation · '||v_asset.asset_code);
 perform public.post_journal_entry(v_journal);
 insert into public.asset_depreciation_entries(tenant_id,asset_id,period_start,period_end,depreciation_amount,journal_entry_id,posted,created_by)
 values(v_asset.tenant_id,v_asset.id,p_period_start,p_period_end,v_amount,v_journal,true,v_user);
 if v_prior+v_amount>=v_asset.acquisition_cost-v_asset.salvage_value-0.005 then update public.fixed_assets set status='fully_depreciated' where id=v_asset.id and tenant_id=v_asset.tenant_id;end if;
 return jsonb_build_object('success',true,'journal_entry_id',v_journal,'amount',v_amount,'posted',true);
end;$function$;