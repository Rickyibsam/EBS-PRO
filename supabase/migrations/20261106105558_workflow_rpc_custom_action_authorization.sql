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

do $mapping_grants$
begin
  create policy module_override_grant_select on public.employee_advance_account_mappings
    as permissive for select to authenticated
    using (private.module_permission_grant_internal(tenant_id,'accounts_finance','view'));
  create policy module_override_grant_insert on public.employee_advance_account_mappings
    as permissive for insert to authenticated
    with check (private.module_permission_grant_internal(tenant_id,'accounts_finance','create'));
  create policy module_override_grant_update on public.employee_advance_account_mappings
    as permissive for update to authenticated
    using (private.module_permission_grant_internal(tenant_id,'accounts_finance','update'))
    with check (private.module_permission_grant_internal(tenant_id,'accounts_finance','update'));
  create policy module_override_grant_delete on public.employee_advance_account_mappings
    as permissive for delete to authenticated
    using (private.module_permission_grant_internal(tenant_id,'accounts_finance','delete'));
end
$mapping_grants$;

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

-- Restore the delivery charge rule, charge, collection and account-mapping tables
-- plus the internal settlement RPC before applying action-permission hardening.

create table if not exists public.delivery_charge_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  route_id uuid references public.sales_routes(id),
  customer_id uuid references public.parties(id),
  charge_type text not null check (charge_type in ('fixed','percentage')),
  amount numeric not null check (amount >= 0),
  min_order_amount numeric not null default 0 check (min_order_amount >= 0),
  free_delivery_above numeric check (free_delivery_above is null or free_delivery_above >= 0),
  priority integer not null default 0,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.delivery_charges (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  rule_id uuid references public.delivery_charge_rules(id),
  customer_id uuid references public.parties(id),
  route_id uuid references public.sales_routes(id),
  base_order_value numeric not null default 0,
  charge_amount numeric not null default 0 check (charge_amount >= 0),
  collected_amount numeric not null default 0,
  status text not null default 'pending' check (status in ('pending','partially_paid','paid','waived')),
  payment_method text,
  payment_reference text,
  collected_by uuid references auth.users(id),
  collected_at timestamptz,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  waived_amount numeric not null default 0 check (waived_amount >= 0),
  constraint delivery_charges_collected_le_charge_check check (collected_amount <= charge_amount),
  constraint delivery_charges_total_settlement_check check (collected_amount >= 0 and waived_amount >= 0 and collected_amount + waived_amount <= charge_amount),
  constraint delivery_charges_tenant_delivery_key unique (tenant_id,delivery_id)
);

create table if not exists public.delivery_charge_collections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  delivery_charge_id uuid not null references public.delivery_charges(id) on delete cascade,
  amount numeric not null check (amount > 0),
  payment_method text not null,
  payment_reference text,
  collected_by uuid references auth.users(id),
  collected_at timestamptz not null default now(),
  journal_entry_id uuid references public.journal_entries(id),
  created_at timestamptz not null default now(),
  idempotency_key text
);

create table if not exists public.delivery_charge_account_mappings (
  tenant_id uuid primary key references public.organizations(id) on delete cascade,
  revenue_account_id uuid not null references public.chart_of_accounts(id),
  cash_account_id uuid not null references public.chart_of_accounts(id),
  bank_account_id uuid not null references public.chart_of_accounts(id),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create index if not exists delivery_charge_rules_route_idx
  on public.delivery_charge_rules(tenant_id,route_id,is_active,priority desc);
create index if not exists delivery_charges_tenant_status_idx
  on public.delivery_charges(tenant_id,status,created_at desc);
create index if not exists delivery_charge_collections_ledger_idx
  on public.delivery_charge_collections(tenant_id,delivery_charge_id,collected_at desc);
create unique index if not exists delivery_charge_collections_tenant_idempotency_uidx
  on public.delivery_charge_collections(tenant_id,idempotency_key) where idempotency_key is not null;
create index if not exists delivery_charge_account_mappings_revenue_idx
  on public.delivery_charge_account_mappings(revenue_account_id);
create index if not exists delivery_charge_account_mappings_cash_idx
  on public.delivery_charge_account_mappings(cash_account_id);
create index if not exists delivery_charge_account_mappings_bank_idx
  on public.delivery_charge_account_mappings(bank_account_id);
create index if not exists delivery_charge_account_mappings_updated_by_idx
  on public.delivery_charge_account_mappings(updated_by);

alter table public.delivery_charge_rules enable row level security;
drop policy if exists delivery_charge_rules_select on public.delivery_charge_rules;
create policy delivery_charge_rules_select on public.delivery_charge_rules
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts','warehouse','delivery_man']::text[]));
drop policy if exists delivery_charge_rules_write on public.delivery_charge_rules;
create policy delivery_charge_rules_write on public.delivery_charge_rules
  for all to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager']::text[]));

alter table public.delivery_charges enable row level security;
drop policy if exists delivery_charges_select on public.delivery_charges;
create policy delivery_charges_select on public.delivery_charges
  for select to authenticated
  using (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[])
    or exists(select 1 from public.deliveries d join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
      where d.id=delivery_charges.delivery_id and d.tenant_id=delivery_charges.tenant_id and e.user_id=(select auth.uid()))
  );
drop policy if exists delivery_charges_insert on public.delivery_charges;
create policy delivery_charges_insert on public.delivery_charges
  for insert to authenticated
  with check (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[])
    or exists(select 1 from public.deliveries d join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
      where d.id=delivery_charges.delivery_id and d.tenant_id=delivery_charges.tenant_id and e.user_id=(select auth.uid()))
  );
drop policy if exists delivery_charges_update on public.delivery_charges;
create policy delivery_charges_update on public.delivery_charges
  for update to authenticated
  using (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[])
    or exists(select 1 from public.deliveries d join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
      where d.id=delivery_charges.delivery_id and d.tenant_id=delivery_charges.tenant_id and e.user_id=(select auth.uid()))
  )
  with check (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[])
    or exists(select 1 from public.deliveries d join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
      where d.id=delivery_charges.delivery_id and d.tenant_id=delivery_charges.tenant_id and e.user_id=(select auth.uid()))
  );

alter table public.delivery_charge_collections enable row level security;
drop policy if exists delivery_charge_collections_select on public.delivery_charge_collections;
create policy delivery_charge_collections_select on public.delivery_charge_collections
  for select to authenticated
  using (
    private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts','warehouse']::text[])
    or exists(select 1 from public.delivery_charges c
      join public.deliveries d on d.id=c.delivery_id and d.tenant_id=c.tenant_id
      join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
      where c.id=delivery_charge_collections.delivery_charge_id and c.tenant_id=delivery_charge_collections.tenant_id
        and e.user_id=(select auth.uid()))
  );

alter table public.delivery_charge_account_mappings enable row level security;
drop policy if exists delivery_charge_account_mappings_select on public.delivery_charge_account_mappings;
create policy delivery_charge_account_mappings_select on public.delivery_charge_account_mappings
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]));
drop policy if exists delivery_charge_account_mappings_write on public.delivery_charge_account_mappings;
create policy delivery_charge_account_mappings_write on public.delivery_charge_account_mappings
  for all to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]));

grant all on table public.delivery_charge_rules,public.delivery_charges,public.delivery_charge_collections,public.delivery_charge_account_mappings to authenticated;
revoke all on table public.delivery_charge_rules,public.delivery_charges,public.delivery_charge_collections,public.delivery_charge_account_mappings from anon;

do $policy$
declare v_table text;v_action text;v_policy text;v_using text;v_check text;
begin
  foreach v_table in array array['delivery_charge_rules','delivery_charges','delivery_charge_collections','delivery_charge_account_mappings'] loop
    foreach v_action in array array['select','insert','update','delete'] loop
      v_policy:='module_override_guard_'||v_action;v_using:=null;v_check:=null;
      if v_action in ('select','update','delete') then
        v_using:=format('private.module_permission_guard_internal(tenant_id,%L,%L)','distribution_delivery',case when v_action='select' then 'view' else v_action end);
      end if;
      if v_action in ('insert','update') then
        v_check:=format('private.module_permission_guard_internal(tenant_id,%L,%L)','distribution_delivery',case when v_action='insert' then 'create' else 'update' end);
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
        execute format('create policy %I on public.%I as permissive for insert to authenticated with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,'distribution_delivery','create');
      elsif v_action='update' then
        execute format('create policy %I on public.%I as permissive for update to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L)) with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,'distribution_delivery','update','distribution_delivery','update');
      elsif v_action='delete' then
        execute format('create policy %I on public.%I as permissive for delete to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,'distribution_delivery','delete');
      else
        execute format('create policy %I on public.%I as permissive for select to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,v_table,'distribution_delivery','view');
      end if;
    end loop;
  end loop;
end
$policy$;

create or replace function private.settle_delivery_charge_internal(
  p_charge_id uuid,p_amount numeric,p_payment_method text,p_payment_reference text,p_waive boolean,p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $function$
declare
 v_charge public.delivery_charges%rowtype;
 v_employee uuid;
 v_mapping public.delivery_charge_account_mappings%rowtype;
 v_cash_account uuid;
 v_cash_type text;
 v_revenue_type text;
 v_collected numeric;
 v_status text;
 v_collection_id uuid;
 v_journal_id uuid;
 v_journal_no text;
 v_existing public.delivery_charge_collections%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required.';end if;
 select * into v_charge from public.delivery_charges where id=p_charge_id for update;
 if not found then raise exception 'Delivery charge was not found.';end if;
 if not public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts','delivery_man']) then raise exception 'You cannot collect this delivery charge.' using errcode='42501';end if;
 if public.has_tenant_role(v_charge.tenant_id,array['delivery_man']) and not public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts']) then
  select e.id into v_employee from public.employees e join public.deliveries d on d.delivery_man_employee_id=e.id and d.tenant_id=e.tenant_id
  where d.id=v_charge.delivery_id and d.tenant_id=v_charge.tenant_id and e.user_id=auth.uid() and e.employment_status='active';
  if v_employee is null then raise exception 'You can only collect your own assigned delivery charge.' using errcode='42501';end if;
 end if;
 if p_waive then
  if not public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager']) then raise exception 'Only managers can waive delivery charges.' using errcode='42501';end if;
  update public.delivery_charges set status='waived',waived_amount=charge_amount-collected_amount,updated_at=now(),notes=concat_ws(E'\n',notes,'Remaining balance waived by manager')
  where id=p_charge_id and tenant_id=v_charge.tenant_id;
  return jsonb_build_object('success',true,'status','waived');
 end if;
 if p_idempotency_key is null or length(btrim(p_idempotency_key))<12 then raise exception 'A unique collection key is required.';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_charge.tenant_id::text||'|'||p_idempotency_key,0));
 select * into v_existing from public.delivery_charge_collections where tenant_id=v_charge.tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_existing.delivery_charge_id<>v_charge.id or abs(v_existing.amount-p_amount)>0.000001 then raise exception 'Collection key was already used for a different charge or amount.';end if;
  return jsonb_build_object('success',true,'replayed',true,'status',v_charge.status,'collection_id',v_existing.id,'journal_entry_id',v_existing.journal_entry_id);
 end if;
 if v_charge.status in ('paid','waived') then raise exception 'This delivery charge is already closed.';end if;
 if p_amount is null or p_amount<=0 or p_amount>v_charge.charge_amount-v_charge.collected_amount-v_charge.waived_amount then raise exception 'Collection amount must be positive and cannot exceed the remaining charge.';end if;
 select * into v_mapping from public.delivery_charge_account_mappings where tenant_id=v_charge.tenant_id;
 if not found then raise exception 'Configure delivery charge revenue, cash and bank accounts before collection.';end if;
 v_cash_account:=case when lower(coalesce(p_payment_method,'cash'))='bank' then v_mapping.bank_account_id else v_mapping.cash_account_id end;
 select account_type into v_cash_type from public.chart_of_accounts where id=v_cash_account and tenant_id=v_charge.tenant_id and is_active;
 select account_type into v_revenue_type from public.chart_of_accounts where id=v_mapping.revenue_account_id and tenant_id=v_charge.tenant_id and is_active;
 if v_cash_account is null or v_cash_account=v_mapping.revenue_account_id or v_cash_type is distinct from 'asset' or v_revenue_type is distinct from 'income' then raise exception 'Mapped cash/bank must be an active same-company asset account and delivery revenue must be an active same-company income account.';end if;
 insert into public.delivery_charge_collections(tenant_id,delivery_charge_id,amount,payment_method,payment_reference,collected_by,idempotency_key)
 values(v_charge.tenant_id,v_charge.id,p_amount,coalesce(p_payment_method,'cash'),p_payment_reference,auth.uid(),p_idempotency_key) returning id into v_collection_id;
 v_journal_no:='EBS-DCHG-'||right(replace(gen_random_uuid()::text,'-',''),12);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by)
 values(v_charge.tenant_id,v_journal_no,current_date,'delivery_charge',v_collection_id,'Delivery charge collection for delivery '||v_charge.delivery_id,'draft',auth.uid())
 returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_charge.tenant_id,v_journal_id,v_cash_account,p_amount,0,'Delivery charge received'),
       (v_charge.tenant_id,v_journal_id,v_mapping.revenue_account_id,0,p_amount,'Delivery charge revenue');
 update public.journal_entries set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_journal_id and tenant_id=v_charge.tenant_id;
 update public.delivery_charge_collections set journal_entry_id=v_journal_id where id=v_collection_id and tenant_id=v_charge.tenant_id;
 v_collected:=v_charge.collected_amount+p_amount;
 v_status:=case when v_collected>=v_charge.charge_amount then 'paid' else 'partially_paid' end;
 update public.delivery_charges set collected_amount=v_collected,status=v_status,payment_method=p_payment_method,payment_reference=p_payment_reference,collected_by=auth.uid(),collected_at=now(),updated_at=now()
 where id=p_charge_id and tenant_id=v_charge.tenant_id;
 return jsonb_build_object('success',true,'status',v_status,'collected_amount',v_collected,'remaining_amount',v_charge.charge_amount-v_collected,'journal_entry_id',v_journal_id,'collection_id',v_collection_id);
end
$function$;

create or replace function public.settle_delivery_charge(
  p_charge_id uuid,p_amount numeric,p_payment_method text,p_payment_reference text,p_waive boolean,p_idempotency_key text
)
returns jsonb language sql set search_path=pg_catalog,public,auth
as $function$ select private.settle_delivery_charge_internal(p_charge_id,p_amount,p_payment_method,p_payment_reference,p_waive,p_idempotency_key); $function$;

revoke all on function private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text) from public,anon;
grant execute on function private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text) to authenticated;
revoke all on function public.settle_delivery_charge(uuid,numeric,text,text,boolean,text) from public,anon;
grant execute on function public.settle_delivery_charge(uuid,numeric,text,text,boolean,text) to authenticated;

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
