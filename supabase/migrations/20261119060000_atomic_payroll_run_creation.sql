-- Create a payroll run and all employee lines in one database transaction.
-- If any employee is invalid or any insert fails, the run number, header and lines roll back together.

create or replace function public.create_payroll_run(
  p_tenant_id uuid,
  p_period_start date,
  p_period_end date,
  p_pay_date date,
  p_employee_ids uuid[]
)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_run_id uuid;
  v_run_number text;
  v_inserted integer;
  v_requested integer;
  v_role_allowed boolean;
  v_is_owner_admin boolean;
  v_has_override boolean;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']);
  v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
  select exists(select 1 from public.tenant_user_module_permissions p
    where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='hr_payroll')
    into v_has_override;
  if not v_role_allowed then
    if not private.module_permission_grant_internal(p_tenant_id,'hr_payroll','create') then
      raise exception 'Payroll creation permission required' using errcode='42501';
    end if;
  elsif not v_is_owner_admin and v_has_override
        and not private.module_permission_grant_internal(p_tenant_id,'hr_payroll','create') then
    raise exception 'Payroll creation is disabled for this user' using errcode='42501';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start or p_pay_date is null then
    raise exception 'Enter a valid payroll period and pay date';
  end if;
  if coalesce(cardinality(p_employee_ids),0)=0 then
    raise exception 'Select at least one active employee with a positive basic salary';
  end if;
  select count(distinct employee_id) into v_requested
  from unnest(p_employee_ids) as selected(employee_id);
  if v_requested<>cardinality(p_employee_ids) then
    raise exception 'Duplicate employees are not allowed in a payroll run';
  end if;

  -- This allocator is tenant-role guarded and participates in the same transaction.
  v_run_number:=public.next_document_number(p_tenant_id,'payroll_run');
  insert into public.payroll_runs(
    tenant_id,run_number,period_start,period_end,pay_date,status,created_by
  ) values (
    p_tenant_id,v_run_number,p_period_start,p_period_end,p_pay_date,'draft',v_user
  ) returning id into v_run_id;

  insert into public.payroll_lines(
    tenant_id,payroll_run_id,employee_id,basic_salary,allowances,overtime,
    sales_incentive,deductions,net_salary
  )
  select p_tenant_id,v_run_id,e.id,e.basic_salary,0,0,0,0,e.basic_salary
  from public.employees e
  where e.tenant_id=p_tenant_id
    and e.id=any(p_employee_ids)
    and e.employment_status='active'
    and e.basic_salary>0;

  get diagnostics v_inserted=row_count;
  if v_inserted<>v_requested then
    raise exception 'One or more selected employees are inactive, missing, or have no positive basic salary';
  end if;

  return jsonb_build_object(
    'success',true,
    'run_id',v_run_id,
    'run_number',v_run_number,
    'line_count',v_inserted,
    'status','draft'
  );
end
$function$;

revoke all on function public.create_payroll_run(uuid,date,date,date,uuid[]) from public,anon;
grant execute on function public.create_payroll_run(uuid,date,date,date,uuid[]) to authenticated;
