-- Keep employee incentive import and payroll recalculation in one database transaction.
create or replace function public.import_employee_incentives_to_payroll(
  p_payroll_run_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_run public.payroll_runs%rowtype;
  v_item record;
  v_target public.sales_targets%rowtype;
  v_line public.payroll_lines%rowtype;
  v_manual jsonb := '{}'::jsonb;
  v_total numeric;
  v_count integer := 0;
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
  if not public.has_tenant_role(v_run.tenant_id, array['owner','admin','manager','accounts']) then
    raise exception 'Payroll incentive import permission required.' using errcode = '42501';
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
$$;

revoke all on function public.import_employee_incentives_to_payroll(uuid, jsonb) from public, anon;
grant execute on function public.import_employee_incentives_to_payroll(uuid, jsonb) to authenticated;
