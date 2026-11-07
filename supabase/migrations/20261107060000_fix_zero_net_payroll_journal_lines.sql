-- Omit zero-value payroll journal lines so a fully clawed-back net salary can still post.
create or replace function public.post_payroll_run(p_payroll_run_id uuid)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, auth
as $function$
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
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_run from public.payroll_runs where id=p_payroll_run_id for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if not (public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update')) then
    raise exception 'Payroll posting permission required';
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
$function$;
revoke all on function public.post_payroll_run(uuid) from public,anon;
grant execute on function public.post_payroll_run(uuid) to authenticated;
