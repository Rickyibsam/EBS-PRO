alter table public.expenses
  add column if not exists expense_account_id uuid references public.chart_of_accounts(id) on delete restrict;

create index if not exists expenses_tenant_expense_account_idx
  on public.expenses(tenant_id,expense_account_id);

create or replace function public.record_expense(
  p_tenant_id uuid,
  p_description text,
  p_amount numeric,
  p_payment_method text,
  p_expense_date date,
  p_branch_id uuid,
  p_expense_account_id uuid
)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_expense_id uuid;
  v_journal_id uuid;
  v_number text;
  v_journal_number text;
  v_expense_account uuid;
  v_cash_account uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'Only owner, admin, manager or accounts can record expenses';
  end if;
  if p_description is null or length(trim(p_description))<2 then
    raise exception 'Enter an expense description';
  end if;
  if p_amount is null or p_amount<=0 then raise exception 'Expense amount must be greater than zero'; end if;
  if p_payment_method not in ('cash','bank','cheque','online') then raise exception 'Invalid expense payment method'; end if;
  if p_branch_id is not null and not exists(
    select 1 from public.branches b where b.id=p_branch_id and b.tenant_id=p_tenant_id
  ) then raise exception 'Branch does not belong to this company'; end if;

  select id into v_expense_account
  from public.chart_of_accounts
  where id=p_expense_account_id
    and tenant_id=p_tenant_id
    and is_active
    and account_type='expense';
  if v_expense_account is null then
    raise exception 'Select an active expense account belonging to this company';
  end if;

  select id into v_cash_account
  from public.chart_of_accounts
  where tenant_id=p_tenant_id
    and account_code=case when p_payment_method in ('bank','cheque','online') then '1010' else '1000' end
    and is_active;
  if v_cash_account is null then
    raise exception 'Required cash/bank account is missing';
  end if;

  v_number:='EBS-EXP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  insert into public.expenses(tenant_id,branch_id,expense_account_id,expense_number,expense_date,description,amount,payment_method,created_by)
  values(p_tenant_id,p_branch_id,v_expense_account,v_number,coalesce(p_expense_date,current_date),trim(p_description),p_amount,p_payment_method,v_user)
  returning id into v_expense_id;

  v_journal_number:='EBS-EXP-JV-'||upper(substr(replace(v_expense_id::text,'-',''),1,12));
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(p_tenant_id,v_journal_number,coalesce(p_expense_date,current_date),'expense',v_expense_id,'Expense: '||trim(p_description),'posted',v_user,v_user,now())
  returning id into v_journal_id;

  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values
    (p_tenant_id,v_journal_id,v_expense_account,p_amount,0,trim(p_description)),
    (p_tenant_id,v_journal_id,v_cash_account,0,p_amount,'Expense paid by '||p_payment_method);

  return jsonb_build_object('success',true,'expense_id',v_expense_id,'expense_number',v_number,'expense_account_id',v_expense_account,'journal_entry_id',v_journal_id);
end;
$function$;

revoke all on function public.record_expense(uuid,text,numeric,text,date,uuid,uuid) from public,anon;
grant execute on function public.record_expense(uuid,text,numeric,text,date,uuid,uuid) to authenticated;
