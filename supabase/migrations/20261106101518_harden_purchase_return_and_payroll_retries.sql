-- Restore the immutable commission clawback ledger and payroll RPC before
-- the later action-permission migration hardens this RPC.
create table if not exists public.sales_incentive_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  sales_target_id uuid not null references public.sales_targets(id),
  employee_id uuid not null references public.employees(id),
  payroll_run_id uuid not null references public.payroll_runs(id),
  return_due numeric not null check (return_due > 0),
  applied_amount numeric not null check (applied_amount > 0),
  remaining_amount numeric not null default 0 check (remaining_amount >= 0),
  status text not null check (status in ('applied','partial')),
  created_by uuid references auth.users(id),
  applied_at timestamptz not null default now(),
  constraint sales_incentive_adjustments_tenant_target_payroll_key
    unique (tenant_id,sales_target_id,payroll_run_id)
);

create index if not exists sales_incentive_adjustments_employee_idx
  on public.sales_incentive_adjustments(employee_id);
create index if not exists sales_incentive_adjustments_payroll_run_idx
  on public.sales_incentive_adjustments(payroll_run_id);
create index if not exists sales_incentive_adjustments_sales_target_idx
  on public.sales_incentive_adjustments(sales_target_id);
create index if not exists sales_incentive_adjustments_created_by_idx
  on public.sales_incentive_adjustments(created_by);
create index if not exists sales_incentive_adjustments_tenant_payroll_idx
  on public.sales_incentive_adjustments(tenant_id,payroll_run_id);

alter table public.sales_incentive_adjustments enable row level security;
drop policy if exists sales_incentive_adjustments_select on public.sales_incentive_adjustments;
create policy sales_incentive_adjustments_select on public.sales_incentive_adjustments
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]));
drop policy if exists sales_incentive_adjustments_insert on public.sales_incentive_adjustments;
create policy sales_incentive_adjustments_insert on public.sales_incentive_adjustments
  for insert to authenticated
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','accounts']::text[]) and created_by=(select auth.uid()));

do $policy$
declare v_action text;v_policy text;v_using text;v_check text;
begin
  foreach v_action in array array['select','insert','update','delete'] loop
    v_policy:='module_override_guard_'||v_action;
    v_using:=null;v_check:=null;
    if v_action in ('select','update','delete') then
      v_using:=format('private.module_permission_guard_internal(tenant_id,%L,%L)','hr_payroll',case when v_action='select' then 'view' else v_action end);
    end if;
    if v_action in ('insert','update') then
      v_check:=format('private.module_permission_guard_internal(tenant_id,%L,%L)','hr_payroll',case when v_action='insert' then 'create' else 'update' end);
    end if;
    execute format('drop policy if exists %I on public.sales_incentive_adjustments',v_policy);
    if v_action='insert' then
      execute format('create policy %I on public.sales_incentive_adjustments as restrictive for insert to authenticated with check (%s)',v_policy,v_check);
    elsif v_action='update' then
      execute format('create policy %I on public.sales_incentive_adjustments as restrictive for update to authenticated using (%s) with check (%s)',v_policy,v_using,v_check);
    else
      execute format('create policy %I on public.sales_incentive_adjustments as restrictive for %s to authenticated using (%s)',v_policy,v_action,v_using);
    end if;
    v_policy:='module_override_grant_'||v_action;
    if v_action='insert' then
      execute format('create policy %I on public.sales_incentive_adjustments as permissive for insert to authenticated with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,'hr_payroll','create');
    elsif v_action='update' then
      execute format('create policy %I on public.sales_incentive_adjustments as permissive for update to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L)) with check (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,'hr_payroll','update','hr_payroll','update');
    elsif v_action='delete' then
      execute format('create policy %I on public.sales_incentive_adjustments as permissive for delete to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,'hr_payroll','delete');
    else
      execute format('create policy %I on public.sales_incentive_adjustments as permissive for select to authenticated using (private.module_permission_grant_internal(tenant_id,%L,%L))',v_policy,'hr_payroll','view');
    end if;
  end loop;
end
$policy$;

grant all on table public.sales_incentive_adjustments to authenticated;
revoke all on table public.sales_incentive_adjustments from anon;

create or replace function public.apply_commission_return_adjustments(p_payroll_run_id uuid)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
 v_run public.payroll_runs%rowtype;
 v_accrual public.sales_incentive_accruals%rowtype;
 v_line public.payroll_lines%rowtype;
 v_applied numeric;
 v_remaining numeric;
 v_total numeric:=0;
 v_count integer:=0;
 v_pending numeric:=0;
begin
 if auth.uid() is null then raise exception 'Authentication required.';end if;
 select * into v_run from public.payroll_runs where id=p_payroll_run_id for update;
 if not found or not public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot adjust this payroll run.' using errcode='42501';end if;
 if v_run.status<>'draft' then raise exception 'Commission adjustments can only be applied to a draft payroll run.';end if;
 for v_accrual in
  select * from public.sales_incentive_accruals a
  where a.tenant_id=v_run.tenant_id and a.status='settled' and a.employee_id is not null and a.return_adjustment_due>0
   and not exists(select 1 from public.sales_incentive_adjustments x where x.tenant_id=a.tenant_id and x.sales_target_id=a.sales_target_id and x.payroll_run_id=v_run.id)
  order by a.calculated_at for update
 loop
  select * into v_line from public.payroll_lines
  where tenant_id=v_run.tenant_id and payroll_run_id=v_run.id and employee_id=v_accrual.employee_id for update;
  if not found then continue;end if;
  v_applied:=least(v_accrual.return_adjustment_due,greatest(coalesce(v_line.net_salary,0),0));
  if v_applied<=0 then continue;end if;
  v_remaining:=v_accrual.return_adjustment_due-v_applied;
  update public.payroll_lines
   set deductions=coalesce(deductions,0)+v_applied,net_salary=greatest(coalesce(net_salary,0)-v_applied,0)
   where id=v_line.id and tenant_id=v_run.tenant_id and payroll_run_id=v_run.id;
  insert into public.sales_incentive_adjustments(tenant_id,sales_target_id,employee_id,payroll_run_id,return_due,applied_amount,remaining_amount,status,created_by)
  values(v_run.tenant_id,v_accrual.sales_target_id,v_accrual.employee_id,v_run.id,v_accrual.return_adjustment_due,v_applied,v_remaining,case when v_remaining>0 then 'partial' else 'applied' end,auth.uid());
  update public.sales_incentive_accruals
   set return_adjustment_due=v_remaining,return_adjustment_applied=coalesce(return_adjustment_applied,0)+v_applied
   where id=v_accrual.id and tenant_id=v_run.tenant_id;
  v_total:=v_total+v_applied;v_count:=v_count+1;
 end loop;
 select coalesce(sum(return_adjustment_due),0) into v_pending
 from public.sales_incentive_accruals
 where tenant_id=v_run.tenant_id and status='settled' and employee_id is not null;
 return jsonb_build_object('success',true,'adjusted_targets',v_count,'applied_amount',v_total,'remaining_amount',v_pending,'payroll_run_id',v_run.id);
end
$function$;

revoke all on function public.apply_commission_return_adjustments(uuid) from public,anon;
grant execute on function public.apply_commission_return_adjustments(uuid) to authenticated;

-- Harden purchase-return source reconciliation and make salary payment retries idempotent.
-- These are function-only changes; no business rows are modified.
do $$
declare
  v_definition text;
  v_old_decl text := 'v_no text;';
  v_new_decl text := 'v_no text;v_receipt_line public.goods_receipt_lines%rowtype;v_prior_returned numeric;v_received_base numeric;';
  v_old_invoice text := $old$if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and status='posted') then raise exception 'Post the matched supplier invoice before posting its purchase return';end if;$old$;
  v_new_invoice text := $new$if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and supplier_id=v_note.supplier_id and status='posted') then raise exception 'Post the matched supplier invoice for this supplier and goods receipt before posting its purchase return';end if;
 if not exists(select 1 from public.goods_receipts where tenant_id=v_note.tenant_id and id=v_note.goods_receipt_id and warehouse_id=v_note.warehouse_id) then raise exception 'Purchase return warehouse must match its source goods receipt';end if;$new$;
  v_old_lines text := $old$if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id loop
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));$old$;
  v_new_lines text := $new$if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 if exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id and (quantity_base<=0 or line_total<0)) then raise exception 'Purchase return lines must have positive quantities and non-negative values';end if;
 if abs(coalesce((select sum(line_total) from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id),0)-coalesce(v_note.subtotal,0))>0.01 then raise exception 'Purchase return header subtotal must equal the sum of its line totals';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id loop
  select * into v_receipt_line from public.goods_receipt_lines where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and id=v_line.goods_receipt_line_id for update;
  if not found then raise exception 'Every purchase return line must reference a line from its source goods receipt';end if;
  if v_receipt_line.product_id is distinct from v_line.product_id or v_receipt_line.batch_number is distinct from v_line.batch_number or v_receipt_line.expiry_date is distinct from v_line.expiry_date then raise exception 'Purchase return product, batch and expiry must match the source goods receipt line';end if;
  v_received_base:=coalesce(v_receipt_line.accepted_quantity,0)*coalesce(v_receipt_line.conversion_to_base,1);
  select coalesce(sum(l.quantity_base),0) into v_prior_returned
  from public.purchase_debit_note_lines l join public.purchase_debit_notes n on n.id=l.debit_note_id and n.tenant_id=l.tenant_id
  where l.tenant_id=v_note.tenant_id and l.goods_receipt_line_id=v_receipt_line.id and n.status='posted';
  if v_prior_returned+v_line.quantity_base>v_received_base+0.000001 then raise exception 'Return quantity exceeds accepted source receipt quantity. Received %, previously returned %, requested %',v_received_base,v_prior_returned,v_line.quantity_base;end if;
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));$new$;
begin
  select pg_get_functiondef('public.post_purchase_debit_note(uuid)'::regprocedure) into v_definition;
  if position(v_old_decl in v_definition)=0 or position(v_old_invoice in v_definition)=0 or position(v_old_lines in v_definition)=0 then
    raise exception 'Expected purchase-return function blocks were not found; no function was changed.';
  end if;
  v_definition:=replace(v_definition,v_old_decl,v_new_decl);
  v_definition:=replace(v_definition,v_old_invoice,v_new_invoice);
  v_definition:=replace(v_definition,v_old_lines,v_new_lines);
  execute v_definition;
end $$;

do $$
declare
  v_definition text;
  v_old text := $old$if v_line.payment_status='paid' then raise exception 'This salary has already been paid';end if;$old$;
  v_new text := $new$if v_line.payment_status='paid' then
  select id into v_journal from public.journal_entries
   where tenant_id=v_line.tenant_id and source_type='payroll_payment' and source_id=v_line.id and status='posted'
   order by created_at desc limit 1;
  if v_journal is null then raise exception 'Salary is marked paid but its posted payment journal is missing. Run reconciliation before retrying.' using errcode='23514';end if;
  return jsonb_build_object('success',true,'status','paid','already_paid',true,'journal_entry_id',v_journal);
 end if;$new$;
begin
  select pg_get_functiondef('public.pay_payroll_line(uuid,text,text)'::regprocedure) into v_definition;
  if position(v_old in v_definition)=0 then
    raise exception 'Expected payroll payment retry guard was not found; no function was changed.';
  end if;
  v_definition:=replace(v_definition,v_old,v_new);
  execute v_definition;
end $$;
