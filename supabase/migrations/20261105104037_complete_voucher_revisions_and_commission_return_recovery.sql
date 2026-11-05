 -- EBS PRO: complete draft voucher revision coverage and commission return recovery.
-- Safe to re-run: additive column, replace functions, and idempotent trigger recreation.

alter table public.sales_incentive_accruals
 add column if not exists return_adjustment_applied numeric(14,2) not null default 0
 check(return_adjustment_applied>=0);

create or replace function public.apply_sales_commission_return_adjustment(p_accrual_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid();v_accrual public.sales_incentive_accruals%rowtype;
 v_run public.payroll_runs%rowtype;v_line public.payroll_lines%rowtype;
 v_due numeric;v_available numeric;v_apply numeric;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_accrual from public.sales_incentive_accruals where id=p_accrual_id for update;
 if not found then raise exception 'Commission accrual not found.'; end if;
 if not public.has_tenant_role(v_accrual.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot apply commission adjustments.' using errcode='42501'; end if;
 if v_accrual.status<>'settled' then raise exception 'Only a settled commission can create a recovery adjustment.'; end if;
 if v_accrual.employee_id is null then raise exception 'This commission has no employee recipient. Reconcile the vendor/brand/product settlement manually.'; end if;
 v_due:=greatest(0,coalesce(v_accrual.return_adjustment_due,0));
 if v_due<=0 then raise exception 'There is no outstanding return adjustment.'; end if;
 select * into v_run from public.payroll_runs where tenant_id=v_accrual.tenant_id and status='draft' and period_start>v_accrual.period_end order by period_start,created_at limit 1 for update;
 if not found then raise exception 'Create the next draft payroll run before applying this commission recovery.'; end if;
 select * into v_line from public.payroll_lines where tenant_id=v_accrual.tenant_id and payroll_run_id=v_run.id and employee_id=v_accrual.employee_id for update;
 if not found then raise exception 'The employee is not included in the next draft payroll run.'; end if;
 v_available:=greatest(0,coalesce(v_line.basic_salary,0)+coalesce(v_line.allowances,0)+coalesce(v_line.overtime,0)+coalesce(v_line.sales_incentive,0)-coalesce(v_line.deductions,0));
 v_apply:=least(v_due,v_available);
 if v_apply<=0 then raise exception 'No positive net payroll amount is available for this recovery.'; end if;
 update public.payroll_lines set deductions=coalesce(deductions,0)+v_apply,net_salary=greatest(0,coalesce(net_salary,v_available)-v_apply) where id=v_line.id and tenant_id=v_accrual.tenant_id and payroll_run_id=v_run.id;
 update public.payroll_runs set deductions_total=coalesce(deductions_total,0)+v_apply,net_total=greatest(0,coalesce(net_total,0)-v_apply) where id=v_run.id and tenant_id=v_accrual.tenant_id and status='draft';
 update public.sales_incentive_accruals set return_adjustment_applied=coalesce(return_adjustment_applied,0)+v_apply,return_adjustment_due=greatest(0,v_due-v_apply) where id=v_accrual.id and tenant_id=v_accrual.tenant_id;
 return jsonb_build_object('success',true,'applied_amount',v_apply,'remaining_amount',greatest(0,v_due-v_apply),'payroll_run_id',v_run.id,'run_number',v_run.run_number);
end;
$$;
revoke all on function public.apply_sales_commission_return_adjustment(uuid) from public,anon;
grant execute on function public.apply_sales_commission_return_adjustment(uuid) to authenticated;

create or replace function public.prevent_posted_voucher_mutation()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public,pg_temp
as $$
declare v_parent_id uuid;v_status text;v_parent_table text;v_fk text;v_record jsonb;v_parent_created timestamptz;v_parent_creator uuid;
begin
 if tg_table_name in ('sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes') then
  if tg_op='DELETE' then
   if lower(coalesce(to_jsonb(old)->>'status','')) in ('posted','approved') then raise exception 'Approved or posted vouchers cannot be deleted.' using errcode='55000'; end if;
   return old;
  end if;
  if tg_op='UPDATE' then
   if lower(coalesce(to_jsonb(old)->>'status',''))='posted' then
    if tg_table_name='sales_invoices' and coalesce((to_jsonb(old)->>'grand_total')::numeric,0)=0 and coalesce((to_jsonb(new)->>'grand_total')::numeric,0)>0 and lower(coalesce(to_jsonb(new)->>'status',''))='posted' and (to_jsonb(new)-array['subtotal','tax_total','discount_total','grand_total','updated_at'])=(to_jsonb(old)-array['subtotal','tax_total','discount_total','grand_total','updated_at']) then return new; end if;
    raise exception 'Posted vouchers are immutable. Use a reversal or adjustment voucher.' using errcode='55000';
   end if;
   if lower(coalesce(to_jsonb(old)->>'status',''))='approved' then
    if lower(coalesce(to_jsonb(new)->>'status','')) not in ('approved','posted') then raise exception 'Approved vouchers cannot return to draft or another status.' using errcode='55000'; end if;
    if (to_jsonb(new)-array['status','approved_by','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at']) then raise exception 'Approved vouchers are locked. Only posting is permitted.' using errcode='55000'; end if;
   end if;
   return new;
  end if;
  return new;
 end if;
 case tg_table_name
  when 'sales_order_lines' then v_parent_table:='sales_orders';v_fk:='sales_order_id';
  when 'purchase_order_lines' then v_parent_table:='purchase_orders';v_fk:='purchase_order_id';
  when 'journal_lines' then v_parent_table:='journal_entries';v_fk:='journal_entry_id';
  when 'goods_receipt_lines' then v_parent_table:='goods_receipts';v_fk:='goods_receipt_id';
  when 'purchase_invoice_lines' then v_parent_table:='purchase_invoices';v_fk:='purchase_invoice_id';
  when 'sales_invoice_lines' then v_parent_table:='sales_invoices';v_fk:='sales_invoice_id';
  when 'sales_credit_note_lines' then v_parent_table:='sales_credit_notes';v_fk:='credit_note_id';
  when 'purchase_debit_note_lines' then v_parent_table:='purchase_debit_notes';v_fk:='debit_note_id';
  else if tg_op='DELETE' then return old; else return new; end if;
 end case;
 if tg_op<>'INSERT' then
  v_record:=to_jsonb(old);v_parent_id:=nullif(v_record->>v_fk,'')::uuid;
  if v_parent_id is not null then
   execute format('select status from public.%I where id=$1',v_parent_table) into v_status using v_parent_id;
   if lower(coalesce(v_status,'')) in ('posted','approved') then raise exception 'Lines belonging to an approved or posted voucher cannot be changed.' using errcode='55000'; end if;
  end if;
 end if;
 if tg_op<>'DELETE' then
  v_record:=to_jsonb(new);v_parent_id:=nullif(v_record->>v_fk,'')::uuid;
  if v_parent_id is not null then
   execute format('select status,created_at,created_by from public.%I where id=$1',v_parent_table) into v_status,v_parent_created,v_parent_creator using v_parent_id;
   if lower(coalesce(v_status,''))='approved' then raise exception 'Lines cannot be inserted into or moved to an approved voucher.' using errcode='55000'; end if;
   if lower(coalesce(v_status,''))='posted' then
    if current_setting('app.ebs_backup_restore',true)='on' and tg_op='INSERT' and public.has_tenant_role((to_jsonb(new)->>'tenant_id')::uuid,array['owner','admin']) then return new; end if;
    if tg_op='INSERT' and v_parent_creator=auth.uid() and v_parent_created>=transaction_timestamp() then return new; end if;
    raise exception 'Lines belonging to a posted voucher are immutable.' using errcode='55000';
   end if;
  end if;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.prevent_posted_voucher_mutation() from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array['sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes'] loop
  execute format('drop trigger if exists trg_capture_draft_voucher_revision on public.%I',t);
  execute format('create trigger trg_capture_draft_voucher_revision before update or delete on public.%I for each row execute function public.capture_draft_voucher_revision()',t);
 end loop;
end;
$$;
