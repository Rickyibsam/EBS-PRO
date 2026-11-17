-- Restore employee advance ledgers and their private RPC implementations before
-- this migration applies per-user action authorization to those RPCs.

create table if not exists public.employee_advances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  advance_number text not null,
  issue_date date not null default current_date,
  amount numeric not null check (amount > 0),
  balance numeric not null check (balance >= 0),
  status text not null default 'open' check (status in ('open','partially_repaid','repaid')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  issue_journal_entry_id uuid references public.journal_entries(id),
  constraint employee_advances_tenant_advance_number_key unique (tenant_id,advance_number)
);

create table if not exists public.employee_advance_repayments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  advance_id uuid not null references public.employee_advances(id) on delete cascade,
  amount numeric not null check (amount > 0),
  repayment_date date not null default current_date,
  payment_method text not null default 'cash',
  reference text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  journal_entry_id uuid references public.journal_entries(id)
);

create table if not exists public.employee_advance_account_mappings (
  tenant_id uuid primary key references public.organizations(id) on delete cascade,
  receivable_account_id uuid not null references public.chart_of_accounts(id),
  cash_account_id uuid not null references public.chart_of_accounts(id),
  bank_account_id uuid not null references public.chart_of_accounts(id),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create index if not exists employee_advances_tenant_status_idx
  on public.employee_advances(tenant_id,status,issue_date desc);
create index if not exists employee_advance_repayments_advance_idx
  on public.employee_advance_repayments(tenant_id,advance_id,repayment_date desc);
create index if not exists employee_advance_account_mappings_receivable_idx
  on public.employee_advance_account_mappings(receivable_account_id);
create index if not exists employee_advance_account_mappings_cash_idx
  on public.employee_advance_account_mappings(cash_account_id);
create index if not exists employee_advance_account_mappings_bank_idx
  on public.employee_advance_account_mappings(bank_account_id);
create index if not exists employee_advance_account_mappings_updated_by_idx
  on public.employee_advance_account_mappings(updated_by);

alter table public.employee_advances enable row level security;
drop policy if exists employee_advances_select on public.employee_advances;
create policy employee_advances_select on public.employee_advances
  for select to authenticated
  using (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[])
    or exists (
      select 1 from public.employees e
      where e.id=employee_advances.employee_id and e.tenant_id=employee_advances.tenant_id
        and e.user_id=(select auth.uid())
    )
  );
drop policy if exists employee_advances_insert on public.employee_advances;
create policy employee_advances_insert on public.employee_advances
  for insert to authenticated
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]));
drop policy if exists employee_advances_update on public.employee_advances;
create policy employee_advances_update on public.employee_advances
  for update to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]));

alter table public.employee_advance_repayments enable row level security;
drop policy if exists employee_advance_repayments_select on public.employee_advance_repayments;
create policy employee_advance_repayments_select on public.employee_advance_repayments
  for select to authenticated
  using (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[])
    or exists (
      select 1
      from public.employee_advances a
      join public.employees e on e.id=a.employee_id and e.tenant_id=a.tenant_id
      where a.id=employee_advance_repayments.advance_id
        and a.tenant_id=employee_advance_repayments.tenant_id
        and e.user_id=(select auth.uid())
    )
  );
drop policy if exists employee_advance_repayments_insert on public.employee_advance_repayments;
create policy employee_advance_repayments_insert on public.employee_advance_repayments
  for insert to authenticated
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]));

alter table public.employee_advance_account_mappings enable row level security;
drop policy if exists employee_advance_account_mappings_select on public.employee_advance_account_mappings;
create policy employee_advance_account_mappings_select on public.employee_advance_account_mappings
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]));
drop policy if exists employee_advance_account_mappings_write on public.employee_advance_account_mappings;
create policy employee_advance_account_mappings_write on public.employee_advance_account_mappings
  for all to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]));

grant all on table public.employee_advances,public.employee_advance_repayments,public.employee_advance_account_mappings to authenticated;
revoke all on table public.employee_advances,public.employee_advance_repayments,public.employee_advance_account_mappings from anon;

do $policy$
declare v_table text;v_action text;v_module text;v_policy text;v_using text;v_check text;
begin
  foreach v_table in array array['employee_advances','employee_advance_repayments'] loop
    v_module:='hr_payroll';
    foreach v_action in array array['select','insert','update','delete'] loop
      v_policy:='module_override_guard_'||v_action;
      v_using:=null;v_check:=null;
      if v_action in ('select','update','delete') then
        v_using:=format('private.module_permission_guard_internal(tenant_id,%L,%L)',v_module,case when v_action='select' then 'view' else v_action end);
      end if;
      if v_action in ('insert','update') then
        v_check:=format('private.module_permission_guard_internal(tenant_id,%L,%L)',v_module,case when v_action='insert' then 'create' else 'update' end);
      end if;
      execute format('drop policy if exists %I on public.%I',v_policy,v_table);
      if v_action='insert' then
        execute format('create policy %I on public.%I as restrictive for insert to authenticated with check (%s)',v_policy,v_table,v_check);
      elsif v_action='update' then
        execute format('create policy %I on public.%I as restrictive for update to authenticated using (%s) with check (%s)',v_policy,v_table,v_using,v_check);
      else
        execute format('create policy %I on public.%I as restrictive for %s to authenticated using (%s)',v_policy,v_table,v_action,v_using);
      end if;
      v_policy:='module_override_grant_'||v_action;
      if v_action='insert' then
        execute format('create policy %I on public.%I as permissive for insert to authenticated with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,v_module,'create');
      elsif v_action='update' then
        execute format('create policy %I on public.%I as permissive for update to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L)) with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,v_module,'update',v_module,'update');
      elsif v_action='delete' then
        execute format('create policy %I on public.%I as permissive for delete to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,v_module,'delete');
      else
        execute format('create policy %I on public.%I as permissive for select to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,v_module,'view');
      end if;
    end loop;
  end loop;
end
$policy$;

create or replace function private.create_employee_advance_internal(
  p_tenant_id uuid,p_employee_id uuid,p_amount numeric,p_issue_date date,p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $function$
declare v_number text;v_id uuid;v_mapping public.employee_advance_account_mappings%rowtype;v_journal uuid;v_type text;
begin
 if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager']) then raise exception 'You cannot issue employee advances.' using errcode='42501';end if;
 if p_amount is null or p_amount<=0 then raise exception 'Advance amount must be greater than zero.';end if;
 if not exists(select 1 from public.employees where id=p_employee_id and tenant_id=p_tenant_id and employment_status='active') then raise exception 'Active employee was not found.';end if;
 select * into v_mapping from public.employee_advance_account_mappings where tenant_id=p_tenant_id;
 if not found then raise exception 'Configure employee advance, cash and bank accounts first.';end if;
 select account_type into v_type from public.chart_of_accounts where id=v_mapping.receivable_account_id and tenant_id=p_tenant_id and is_active;
 if v_type is distinct from 'asset' then raise exception 'Employee advance account mapping is invalid.';end if;
 v_number:='ADV-'||to_char(coalesce(p_issue_date,current_date),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.employee_advances(tenant_id,employee_id,advance_number,issue_date,amount,balance,status,notes,created_by)
 values(p_tenant_id,p_employee_id,v_number,coalesce(p_issue_date,current_date),p_amount,p_amount,'open',p_notes,auth.uid()) returning id into v_id;
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(p_tenant_id,'EBS-ADV-'||right(replace(gen_random_uuid()::text,'-',''),12),coalesce(p_issue_date,current_date),'employee_advance',v_id,'Employee advance issued · '||v_number,'draft',auth.uid()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(p_tenant_id,v_journal,v_mapping.receivable_account_id,p_amount,0,'Employee advance receivable'),
       (p_tenant_id,v_journal,v_mapping.cash_account_id,0,p_amount,'Cash advance disbursed');
 update public.journal_entries set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_journal and tenant_id=p_tenant_id;
 update public.employee_advances set issue_journal_entry_id=v_journal where id=v_id and tenant_id=p_tenant_id;
 return v_id;
end
$function$;

create or replace function private.record_employee_advance_repayment_internal(
  p_advance_id uuid,p_amount numeric,p_repayment_date date,p_payment_method text,p_reference text,p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $function$
declare v_advance public.employee_advances%rowtype;v_id uuid;v_balance numeric;v_mapping public.employee_advance_account_mappings%rowtype;v_cash uuid;v_journal uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required.';end if;
 select * into v_advance from public.employee_advances where id=p_advance_id for update;
 if not found or not public.has_tenant_role(v_advance.tenant_id,array['owner','admin','manager']) then raise exception 'You cannot record this advance repayment.' using errcode='42501';end if;
 if p_amount is null or p_amount<=0 or p_amount>v_advance.balance then raise exception 'Repayment must be positive and cannot exceed outstanding advance.';end if;
 select * into v_mapping from public.employee_advance_account_mappings where tenant_id=v_advance.tenant_id;
 if not found then raise exception 'Configure employee advance, cash and bank accounts first.';end if;
 v_cash:=case when lower(coalesce(p_payment_method,'cash'))='bank' then v_mapping.bank_account_id else v_mapping.cash_account_id end;
 v_balance:=v_advance.balance-p_amount;
 insert into public.employee_advance_repayments(tenant_id,advance_id,amount,repayment_date,payment_method,reference,notes,created_by)
 values(v_advance.tenant_id,p_advance_id,p_amount,coalesce(p_repayment_date,current_date),coalesce(p_payment_method,'cash'),p_reference,p_notes,auth.uid()) returning id into v_id;
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(v_advance.tenant_id,'EBS-ADV-RCPT-'||right(replace(gen_random_uuid()::text,'-',''),10),coalesce(p_repayment_date,current_date),'employee_advance_repayment',v_id,'Employee advance repayment · '||v_advance.advance_number,'draft',auth.uid()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_advance.tenant_id,v_journal,v_cash,p_amount,0,'Advance repayment received'),
       (v_advance.tenant_id,v_journal,v_mapping.receivable_account_id,0,p_amount,'Employee advance receivable reduced');
 update public.journal_entries set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_journal and tenant_id=v_advance.tenant_id;
 update public.employee_advance_repayments set journal_entry_id=v_journal where id=v_id and tenant_id=v_advance.tenant_id;
 update public.employee_advances set balance=v_balance,status=case when v_balance=0 then 'repaid' when v_balance<v_advance.amount then 'partially_repaid' else 'open' end where id=p_advance_id and tenant_id=v_advance.tenant_id;
 return jsonb_build_object('success',true,'repayment_id',v_id,'remaining_balance',v_balance,'journal_entry_id',v_journal);
end
$function$;

create or replace function public.create_employee_advance(
  p_tenant_id uuid,p_employee_id uuid,p_amount numeric,p_issue_date date,p_notes text default null
)
returns uuid language sql set search_path=pg_catalog,public,auth
as $function$ select private.create_employee_advance_internal(p_tenant_id,p_employee_id,p_amount,p_issue_date,p_notes); $function$;

create or replace function public.record_employee_advance_repayment(
  p_advance_id uuid,p_amount numeric,p_repayment_date date,p_payment_method text,p_reference text,p_notes text default null
)
returns jsonb language sql set search_path=pg_catalog,public,auth
as $function$ select private.record_employee_advance_repayment_internal(p_advance_id,p_amount,p_repayment_date,p_payment_method,p_reference,p_notes); $function$;

revoke all on function private.create_employee_advance_internal(uuid,uuid,numeric,date,text) from public,anon;
revoke all on function private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text) from public,anon;
grant execute on function private.create_employee_advance_internal(uuid,uuid,numeric,date,text) to authenticated;
grant execute on function private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text) to authenticated;
revoke all on function public.create_employee_advance(uuid,uuid,numeric,date,text) from public,anon;
revoke all on function public.record_employee_advance_repayment(uuid,numeric,date,text,text,text) from public,anon;
grant execute on function public.create_employee_advance(uuid,uuid,numeric,date,text) to authenticated;
grant execute on function public.record_employee_advance_repayment(uuid,numeric,date,text,text,text) to authenticated;

-- Align privileged workflow RPC checks with the same per-module action overrides enforced by RLS.
do $$
declare v_item record; v_oid oid; v_definition text;
begin
 for v_item in select * from (values
 ('public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text)',
  $old$if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
   raise exception 'You do not have permission to adjust stock';
 end if;$old$,
  $new$if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'inventory','create')) then
   raise exception 'You do not have permission to adjust stock';
 end if;$new$),
 ('public.post_goods_receipt(uuid)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can post goods receipts'; end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','update')) then raise exception 'Only an authorized purchase/warehouse user can post goods receipts'; end if;$new$),
 ('public.dispatch_delivery(uuid,jsonb)',
  $old$if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can confirm dispatch'; end if;$old$,
  $new$if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only an authorized distribution/warehouse user can confirm dispatch'; end if;$new$),
 ('public.complete_delivery(uuid,jsonb)',
  $old$if not (
  public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse'])
  OR (public.has_tenant_role(v_delivery.tenant_id,array['delivery_man']) AND EXISTS (
   SELECT 1 FROM public.employees e WHERE e.id=v_delivery.delivery_man_employee_id AND e.tenant_id=v_delivery.tenant_id AND e.user_id=v_user
  ))
 ) then raise exception 'Only an authorized warehouse user or the assigned delivery man can confirm delivery'; end if;$old$,
  $new$if not (
  public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse'])
  OR private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')
  OR (public.has_tenant_role(v_delivery.tenant_id,array['delivery_man']) AND EXISTS (
   SELECT 1 FROM public.employees e WHERE e.id=v_delivery.delivery_man_employee_id AND e.tenant_id=v_delivery.tenant_id AND e.user_id=v_user
  ))
 ) then raise exception 'Only an authorized distribution/warehouse user or assigned delivery man can confirm delivery'; end if;$new$),
 ('public.create_delivery_for_approved_order(uuid,uuid)',
  $old$if not public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) then raise exception 'Not allowed to allocate delivery';end if;$old$,
  $new$if not (public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) or (private.module_permission_grant_internal(v_order.tenant_id,'sales_customer','update') and private.module_permission_grant_internal(v_order.tenant_id,'distribution_delivery','create'))) then raise exception 'Not allowed to allocate delivery';end if;$new$),
 ('public.create_purchase_invoice(uuid,text,date,date,numeric,text)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase invoice creation permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create')) then raise exception 'Purchase invoice creation permission required';end if;$new$),
 ('public.create_purchase_debit_note(uuid,jsonb,text,date)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase return creation permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create')) then raise exception 'Purchase return creation permission required';end if;$new$),
 ('public.post_purchase_invoice(uuid)',
  $old$if not public.has_tenant_role(v_inv.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only accounts or management can post supplier invoices';end if;$old$,
  $new$if not (public.has_tenant_role(v_inv.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_inv.tenant_id,'purchase_supplier','update')) then raise exception 'Only authorized purchase/accounts users can post supplier invoices';end if;$new$),
 ('public.post_stock_transfer(uuid)',
  $old$if not public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You do not have permission to post stock transfers'; end if;$old$,
  $new$if not (public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_transfer.tenant_id,'inventory','update')) then raise exception 'You do not have permission to post stock transfers'; end if;$new$),
 ('public.create_sales_credit_note(uuid,jsonb,text,date)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) then raise exception 'You do not have permission to create a sales credit note';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) or private.module_permission_grant_internal(v_invoice.tenant_id,'sales_customer','create')) then raise exception 'You do not have permission to create a sales credit note';end if;$new$),
 ('private.post_sales_credit_note(uuid)',
  $old$if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post a sales credit note';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_note.tenant_id,'sales_customer','update')) then
  raise exception 'Only authorized sales/accounts users can post a sales credit note';
 end if;$new$),
 ('public.record_invoice_receipt(uuid,numeric,text,text,text)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can allocate invoice receipts';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','create')) then
  raise exception 'Invoice receipt create permission required';
 end if;$new$),
 ('public.record_invoice_receipt(uuid,numeric,text,text,text,date)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only owner, admin, manager or accounts can allocate invoice receipts';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','create')) then raise exception 'Invoice receipt create permission required';end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text)',
  $old$if not public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post party payments';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_party.tenant_id,'accounts_finance','create')) then
  raise exception 'Party payment create permission required';
 end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text,date)',
  $old$if not public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only owner, admin, manager or accounts can post party payments';end if;$old$,
  $new$if not (public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_party.tenant_id,'accounts_finance','create')) then raise exception 'Party payment create permission required';end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Supplier payment permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','update')) then raise exception 'Supplier payment allocation update permission required';end if;$new$),
 ('private.create_employee_advance_internal(uuid,uuid,numeric,date,text)',
  $old$if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager']) then raise exception 'You cannot issue employee advances.' using errcode='42501';end if;$old$,
  $new$if auth.uid() is null or not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager']) or private.module_permission_grant_internal(p_tenant_id,'hr_payroll','create')) then raise exception 'You cannot issue employee advances.' using errcode='42501';end if;$new$),
 ('private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text)',
  $old$if not found or not public.has_tenant_role(v_advance.tenant_id,array['owner','admin','manager']) then raise exception 'You cannot record this advance repayment.' using errcode='42501';end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_advance.tenant_id,array['owner','admin','manager']) or private.module_permission_grant_internal(v_advance.tenant_id,'hr_payroll','update')) then raise exception 'You cannot record this advance repayment.' using errcode='42501';end if;$new$),
 ('private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text)',
  $old$if not public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts','delivery_man']) then raise exception 'You cannot collect this delivery charge.' using errcode='42501';end if;$old$,
  $new$if not (public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts','delivery_man']) or private.module_permission_grant_internal(v_charge.tenant_id,'distribution_delivery','update')) then raise exception 'You cannot collect this delivery charge.' using errcode='42501';end if;$new$),
 ('public.post_journal_entry(uuid)',
  $old$if not public.has_tenant_role(v_entry.tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'You do not have permission to post journal entries';
  end if;$old$,
  $new$if not (
    public.has_tenant_role(v_entry.tenant_id,array['owner','admin','manager','accounts'])
    or case
      when v_entry.source_type in ('purchase_invoice','purchase_return','goods_receipt','purchase_debit_note') then private.module_permission_grant_internal(v_entry.tenant_id,'purchase_supplier','update')
      when v_entry.source_type in ('sales_credit_note') then private.module_permission_grant_internal(v_entry.tenant_id,'sales_customer','update')
      when v_entry.source_type in ('sales_invoice','delivery_cogs','delivery_return') then (private.module_permission_grant_internal(v_entry.tenant_id,'sales_customer','update') or private.module_permission_grant_internal(v_entry.tenant_id,'distribution_delivery','update'))
      when v_entry.source_type in ('payroll','payroll_payment','employee_advance','employee_advance_repayment') then private.module_permission_grant_internal(v_entry.tenant_id,'hr_payroll','update')
      when v_entry.source_type in ('asset_depreciation','asset_disposal') then private.module_permission_grant_internal(v_entry.tenant_id,'accounts_finance','update')
      when v_entry.source_type in ('stock_transfer','stock_adjustment','inventory_adjustment') then private.module_permission_grant_internal(v_entry.tenant_id,'inventory','update')
      when v_entry.source_type in ('delivery_charge','delivery_charge_collection','delivery_charge_waiver') then private.module_permission_grant_internal(v_entry.tenant_id,'distribution_delivery','update')
      else private.module_permission_grant_internal(v_entry.tenant_id,'accounts_finance','update')
    end
  ) then
    raise exception 'You do not have permission to post this journal entry';
  end if;$new$)
 ) as x(signature,old_text,new_text)
 loop
  v_oid:=to_regprocedure(v_item.signature);
  if v_oid is null then raise exception 'Required workflow RPC % was not found.',v_item.signature; end if;
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_item.old_text in v_definition)=0 then raise exception 'Expected role guard not found in %.',v_item.signature; end if;
  execute replace(v_definition,v_item.old_text,v_item.new_text);
 end loop;
end $$;
