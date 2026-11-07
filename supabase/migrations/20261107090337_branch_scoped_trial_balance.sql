create or replace function public.get_branch_trial_balance(
  p_tenant_id uuid,
  p_as_of date default current_date,
  p_branch_id uuid default null
)
returns table(
  account_id uuid,
  account_code text,
  account_name text,
  account_type text,
  total_debit numeric,
  total_credit numeric,
  balance numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'You do not have permission to view financial statements';
  end if;
  if p_branch_id is not null and not exists(
    select 1 from public.branches b where b.id=p_branch_id and b.tenant_id=p_tenant_id
  ) then
    raise exception 'Branch does not belong to this company';
  end if;

  return query
  select
    coa.id,
    coa.account_code,
    coa.account_name,
    coa.account_type,
    coalesce(b.debit_total,0)::numeric,
    coalesce(b.credit_total,0)::numeric,
    (case when coa.account_type in ('asset','expense')
      then coalesce(b.debit_total,0)-coalesce(b.credit_total,0)
      else coalesce(b.credit_total,0)-coalesce(b.debit_total,0)
    end)::numeric
  from public.chart_of_accounts coa
  left join (
    select jl.account_id,sum(jl.debit) as debit_total,sum(jl.credit) as credit_total
    from public.journal_lines jl
    join public.journal_entries je
      on je.id=jl.journal_entry_id and je.tenant_id=jl.tenant_id
    where jl.tenant_id=p_tenant_id
      and je.status='posted'
      and je.entry_date<=coalesce(p_as_of,current_date)
      and (p_branch_id is null or je.branch_id=p_branch_id)
    group by jl.account_id
  ) b on b.account_id=coa.id
  where coa.tenant_id=p_tenant_id
  order by coa.account_code;
end;
$function$;

revoke all on function public.get_branch_trial_balance(uuid,date,uuid) from public,anon;
grant execute on function public.get_branch_trial_balance(uuid,date,uuid) to authenticated;
