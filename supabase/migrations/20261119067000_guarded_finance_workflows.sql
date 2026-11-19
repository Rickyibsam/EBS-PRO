CREATE OR REPLACE FUNCTION public.dispose_fixed_asset(p_asset_id uuid, p_disposal_date date, p_proceeds numeric, p_asset_cost_account_id uuid, p_accumulated_account_id uuid, p_cash_account_id uuid, p_gain_account_id uuid, p_loss_account_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
 v_user uuid:=auth.uid(); v_asset public.fixed_assets%rowtype;
 v_mapping public.fixed_asset_account_mappings%rowtype;
 v_accum numeric; v_book numeric; v_gain numeric; v_loss numeric;
 v_journal uuid; v_no text; v_month date; v_month_end date; v_depreciation_end date;
 v_existing public.asset_depreciation_entries%rowtype;
 v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.'; end if;
 v_role_allowed:=public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']);
 v_is_owner_admin:=public.has_tenant_role(v_asset.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_asset.tenant_id and p.user_id=v_user and p.module_key='fixed_assets') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_asset.tenant_id,'fixed_assets','update') then raise exception 'You cannot dispose this asset.' using errcode='42501'; end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_asset.tenant_id,'fixed_assets','update') then
  raise exception 'Asset disposal is disabled for this user' using errcode='42501';
 end if;
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
 v_depreciation_end:=least(p_disposal_date,((v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months))::date-1)::date);
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
 return jsonb_build_object('success',true,'journal_entry_id',v_journal,'book_value',v_book,'accumulated_depreciation',v_accum,'gain',v_gain,'loss',v_loss,'depreciation_catch_up',true,'posted',true);
end;
$function$


CREATE OR REPLACE FUNCTION public.import_employee_incentives_to_payroll(p_payroll_run_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_user uuid := auth.uid();
  v_run public.payroll_runs%rowtype;
  v_item record;
  v_target public.sales_targets%rowtype;
  v_line public.payroll_lines%rowtype;
  v_manual jsonb := '{}'::jsonb;
  v_total numeric;
  v_count integer := 0;
  v_role_allowed boolean; v_is_owner_admin boolean; v_has_override boolean;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;

  select * into v_run
  from public.payroll_runs
  where id = p_payroll_run_id
  for update;

  if not found then
    raise exception 'Payroll run not found.';
  end if;
  v_role_allowed:=public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']);
  v_is_owner_admin:=public.has_tenant_role(v_run.tenant_id,array['owner','admin']);
  select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_run.tenant_id and p.user_id=v_user and p.module_key='hr_payroll') into v_has_override;
  if not v_role_allowed then
    if not private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update') then raise exception 'Payroll incentive import permission required' using errcode='42501'; end if;
  elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update') then
    raise exception 'Payroll incentive import is disabled for this user' using errcode='42501';
  end if;
  if v_run.status <> 'draft' then
    raise exception 'Incentives can only be imported into a draft payroll run.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one earned employee incentive is required.';
  end if;

  -- Preserve any manually entered incentive amount separately from previously imported target accruals.
  select coalesce(jsonb_object_agg(x.employee_id::text, greatest(0, x.sales_incentive - x.imported_total)), '{}'::jsonb)
    into v_manual
  from (
    select pl.employee_id, pl.sales_incentive,
           coalesce(sum(pia.earned_amount), 0) as imported_total
    from public.payroll_lines pl
    left join public.payroll_incentive_accruals pia
      on pia.tenant_id = pl.tenant_id
     and pia.payroll_run_id = pl.payroll_run_id
     and pia.employee_id = pl.employee_id
    where pl.tenant_id = v_run.tenant_id
      and pl.payroll_run_id = v_run.id
    group by pl.employee_id, pl.sales_incentive
  ) x;

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(sales_target_id uuid, earned_amount numeric)
  loop
    if v_item.sales_target_id is null or v_item.earned_amount is null or v_item.earned_amount <= 0 then
      raise exception 'Each incentive must have a target and a positive earned amount.';
    end if;

    select * into v_target
    from public.sales_targets
    where id = v_item.sales_target_id
      and tenant_id = v_run.tenant_id
    for share;

    if not found
       or v_target.employee_id is null
       or v_target.period_start <> v_run.period_start
       or v_target.period_end <> v_run.period_end then
      raise exception 'An incentive target does not match this company, employee payroll period or employee scope.';
    end if;

    if exists (
      select 1 from public.sales_incentive_accruals
      where tenant_id = v_run.tenant_id
        and sales_target_id = v_target.id
        and status = 'settled'
    ) then
      raise exception 'A settled incentive target cannot be imported into payroll again.';
    end if;

    select * into v_line
    from public.payroll_lines
    where tenant_id = v_run.tenant_id
      and payroll_run_id = v_run.id
      and employee_id = v_target.employee_id
    for update;

    if not found then
      raise exception 'An incentive employee is missing from the draft payroll.';
    end if;

    insert into public.payroll_incentive_accruals(
      tenant_id, payroll_run_id, payroll_line_id, employee_id,
      sales_target_id, earned_amount, calculated_at
    )
    values(
      v_run.tenant_id, v_run.id, v_line.id, v_target.employee_id,
      v_target.id, round(v_item.earned_amount, 2), now()
    )
    on conflict (tenant_id, payroll_run_id, sales_target_id)
    do update set
      payroll_line_id = excluded.payroll_line_id,
      employee_id = excluded.employee_id,
      earned_amount = excluded.earned_amount,
      calculated_at = excluded.calculated_at;

    v_count := v_count + 1;
  end loop;

  -- Recalculate each payroll line from manual incentive + all imported target accruals.
  for v_line in
    select * from public.payroll_lines
    where tenant_id = v_run.tenant_id and payroll_run_id = v_run.id
    for update
  loop
    select coalesce(sum(earned_amount), 0) into v_total
    from public.payroll_incentive_accruals
    where tenant_id = v_run.tenant_id
      and payroll_run_id = v_run.id
      and employee_id = v_line.employee_id;

    update public.payroll_lines
    set sales_incentive = coalesce((v_manual ->> v_line.employee_id::text)::numeric, 0) + v_total,
        net_salary = basic_salary + allowances + overtime
          + coalesce((v_manual ->> v_line.employee_id::text)::numeric, 0)
          + v_total - deductions
    where id = v_line.id and tenant_id = v_run.tenant_id;
  end loop;

  return jsonb_build_object(
    'success', true,
    'imported_targets', v_count,
    'payroll_run_id', v_run.id,
    'status', 'draft'
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.pay_payroll_line(p_payroll_line_id uuid, p_method text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_line public.payroll_lines%rowtype;v_run public.payroll_runs%rowtype;v_user uuid:=auth.uid();v_payable uuid;v_cash uuid;v_journal uuid;v_no text;v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_line from public.payroll_lines where id=p_payroll_line_id for update;
 if not found then raise exception 'Payroll line not found';end if;
 select * into v_run from public.payroll_runs where id=v_line.payroll_run_id and tenant_id=v_line.tenant_id;
 if v_run.status<>'posted' then raise exception 'Post payroll run before paying salaries';end if;
 v_role_allowed:=public.has_tenant_role(v_line.tenant_id,array['owner','admin','manager','accounts']);
 v_is_owner_admin:=public.has_tenant_role(v_line.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_line.tenant_id and p.user_id=v_user and p.module_key='hr_payroll') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_line.tenant_id,'hr_payroll','update') then raise exception 'Payroll payment permission required' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_line.tenant_id,'hr_payroll','update') then
  raise exception 'Payroll payment is disabled for this user' using errcode='42501';
 end if;
 if v_line.payment_status='paid' then
  select id into v_journal from public.journal_entries
   where tenant_id=v_line.tenant_id and source_type='payroll_payment' and source_id=v_line.id and status='posted'
   order by created_at desc limit 1;
  if v_journal is null then raise exception 'Salary is marked paid but its posted payment journal is missing. Run reconciliation before retrying.' using errcode='23514';end if;
  return jsonb_build_object('success',true,'status','paid','already_paid',true,'journal_entry_id',v_journal);
 end if;
 if v_line.net_salary<=0 then raise exception 'No net salary is payable for this employee';end if;
 if p_method not in ('cash','bank','cheque','online') then raise exception 'Invalid payment method';end if;
 select id into v_payable from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code='2150' and is_active;
 select id into v_cash from public.chart_of_accounts where tenant_id=v_line.tenant_id and account_code=case when p_method in ('bank','cheque','online') then '1010' else '1000' end and is_active;
 if v_payable is null or v_cash is null then raise exception 'Payroll payable and cash/bank accounts are required';end if;
 v_no:='EBS-SALARY-PAY-'||right(replace(v_line.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_line.tenant_id,v_no,current_date,'payroll_payment',v_line.id,'Salary payment for employee '||v_line.employee_id,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_line.tenant_id,v_journal,v_payable,v_line.net_salary,0,'Payroll payable settlement'),
 (v_line.tenant_id,v_journal,v_cash,0,v_line.net_salary,'Salary disbursement');
 update public.payroll_lines set payment_status='paid',payment_method=p_method,payment_reference=nullif(trim(p_reference),''),paid_at=now() where id=v_line.id and tenant_id=v_line.tenant_id;
 return jsonb_build_object('success',true,'status','paid','journal_entry_id',v_journal);
end $function$


CREATE OR REPLACE FUNCTION public.post_asset_monthly_depreciation(p_asset_id uuid, p_period_start date, p_period_end date, p_expense_account_id uuid, p_accumulated_account_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
 v_user uuid:=auth.uid();v_asset public.fixed_assets%rowtype;v_existing public.asset_depreciation_entries%rowtype;
 v_month_days integer;v_overlap_days integer;v_monthly numeric;v_prior numeric;v_amount numeric;v_journal uuid;v_no text;
begin
 if v_user is null then raise exception 'Authentication required.';end if;
 select * into v_asset from public.fixed_assets where id=p_asset_id for update;
 if not found then raise exception 'Asset not found.';end if;
 v_role_allowed:=public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']);
 v_is_owner_admin:=public.has_tenant_role(v_asset.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_asset.tenant_id and p.user_id=v_user and p.module_key='fixed_assets') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_asset.tenant_id,'fixed_assets','update') then raise exception 'You cannot post asset depreciation.' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_asset.tenant_id,'fixed_assets','update') then
  raise exception 'Asset depreciation posting is disabled for this user' using errcode='42501';
 end if;
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
 v_overlap_days:=greatest(0,(least(p_period_end,(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months))::date-1)-greatest(p_period_start,v_asset.acquisition_date)+1));
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
end;$function$


CREATE OR REPLACE FUNCTION public.post_payroll_run(p_payroll_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_run public.payroll_runs%rowtype;
  v_user uuid:=auth.uid();
  v_gross numeric;
  v_ded numeric;
  v_net numeric;
  v_count integer;
  v_salary uuid;
  v_payable uuid;
  v_deductions uuid;
  v_journal uuid;
  v_no text;
  v_role_allowed boolean; v_is_owner_admin boolean; v_has_override boolean;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_run from public.payroll_runs where id=p_payroll_run_id for update;
  if not found then raise exception 'Payroll run not found'; end if;
  v_role_allowed:=public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']);
  v_is_owner_admin:=public.has_tenant_role(v_run.tenant_id,array['owner','admin']);
  select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_run.tenant_id and p.user_id=v_user and p.module_key='hr_payroll') into v_has_override;
  if not v_role_allowed then
    if not private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update') then raise exception 'Payroll posting permission required' using errcode='42501'; end if;
  elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update') then
    raise exception 'Payroll posting is disabled for this user' using errcode='42501';
  end if;
  if v_run.status<>'draft' then raise exception 'Only draft payroll runs can be posted'; end if;
  if exists(
    select 1 from public.payroll_lines
    where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id
      and (deductions>basic_salary+allowances+overtime+sales_incentive
       or abs(net_salary-(basic_salary+allowances+overtime+sales_incentive-deductions))>0.01)
  ) then raise exception 'One or more payroll lines have invalid net salary calculations'; end if;
  select coalesce(sum(basic_salary+allowances+overtime+sales_incentive),0),
         coalesce(sum(deductions),0),count(*)
  into v_gross,v_ded,v_count
  from public.payroll_lines where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id;
  if v_count=0 then raise exception 'Add at least one employee to the payroll run'; end if;
  if v_gross<=0 then raise exception 'Payroll gross salary must be greater than zero'; end if;
  v_net:=v_gross-v_ded;
  if v_net<0 then raise exception 'Payroll deductions cannot exceed gross salary'; end if;
  select id into v_salary from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='5200' and is_active;
  select id into v_payable from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2150' and is_active;
  select id into v_deductions from public.chart_of_accounts where tenant_id=v_run.tenant_id and account_code='2160' and is_active;
  if v_salary is null or v_payable is null or v_deductions is null then raise exception 'Payroll accounts are not configured'; end if;
  v_no:='EBS-PAYROLL-JV-'||right(replace(v_run.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_run.tenant_id,v_no,v_run.pay_date,'payroll',v_run.id,'Payroll accrual for '||v_run.period_start||' to '||v_run.period_end,'posted',v_user,v_user,now())
  returning id into v_journal;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_run.tenant_id,v_journal,v_salary,v_gross,0,'Gross payroll expense including sales and delivery incentives');
  if v_net>0 then
    insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
    values(v_run.tenant_id,v_journal,v_payable,0,v_net,'Net salaries payable');
  end if;
  if v_ded>0 then
    insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
    values(v_run.tenant_id,v_journal,v_deductions,0,v_ded,'Employee deductions payable');
  end if;
  update public.payroll_runs set status='posted',gross_total=v_gross,deductions_total=v_ded,net_total=v_net,posted_by=v_user,posted_at=now()
  where id=v_run.id and tenant_id=v_run.tenant_id;
  return jsonb_build_object('success',true,'status','posted','gross_total',v_gross,'deductions_total',v_ded,'net_total',v_net,'journal_entry_id',v_journal);
end
$function$



revoke all on function public.post_payroll_run(uuid) from public,anon;
grant execute on function public.post_payroll_run(uuid) to authenticated;
revoke all on function public.pay_payroll_line(uuid,text,text) from public,anon;
grant execute on function public.pay_payroll_line(uuid,text,text) to authenticated;
revoke all on function public.import_employee_incentives_to_payroll(uuid,jsonb) from public,anon;
grant execute on function public.import_employee_incentives_to_payroll(uuid,jsonb) to authenticated;
revoke all on function public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid) from public,anon;
grant execute on function public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid) to authenticated;
revoke all on function public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid) to authenticated;
