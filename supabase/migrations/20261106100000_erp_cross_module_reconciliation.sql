-- Read-only cross-module reconciliation summary for the tenant's operational and financial chains.
create or replace function public.get_erp_integration_reconciliation(p_tenant_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'ERP reconciliation report permission required.' using errcode='42501';
  end if;

  with checks as (
    select
      (select count(*) from public.purchase_debit_notes n
       where n.tenant_id=p_tenant_id and n.status='posted'
         and not exists(select 1 from public.journal_entries j where j.tenant_id=n.tenant_id and j.source_type='purchase_return' and j.source_id=n.id and j.status='posted')) as purchase_returns_without_journal,
      (select count(*) from public.purchase_debit_notes n
       where n.tenant_id=p_tenant_id and n.status='posted'
         and abs(coalesce(n.subtotal,0)-coalesce((select sum(l.line_total) from public.purchase_debit_note_lines l where l.tenant_id=n.tenant_id and l.debit_note_id=n.id),0))>0.01) as purchase_return_value_mismatch,
      (select count(*) from public.purchase_debit_notes n
       where n.tenant_id=p_tenant_id and n.status='posted'
         and abs(coalesce((select sum(sm.quantity_out) from public.stock_movements sm where sm.tenant_id=n.tenant_id and sm.reference_type='purchase_debit_note' and sm.reference_id=n.id and sm.movement_type='purchase_return'),0)
           -coalesce((select sum(l.quantity_base) from public.purchase_debit_note_lines l where l.tenant_id=n.tenant_id and l.debit_note_id=n.id),0))>0.000001) as purchase_return_stock_mismatch,
      (select count(*) from public.payroll_runs r
       where r.tenant_id=p_tenant_id and r.status='posted'
         and not exists(select 1 from public.journal_entries j where j.tenant_id=r.tenant_id and j.source_type='payroll' and j.source_id=r.id and j.status='posted')) as payroll_runs_without_journal,
      (select count(*) from public.payroll_lines l join public.payroll_runs r on r.id=l.payroll_run_id and r.tenant_id=l.tenant_id
       where l.tenant_id=p_tenant_id and r.status='posted'
         and l.payment_status='paid'
         and not exists(select 1 from public.journal_entries j where j.tenant_id=l.tenant_id and j.source_type='payroll_payment' and j.source_id=l.id and j.status='posted')) as paid_salary_without_payment_journal,
      (select count(*) from public.asset_depreciation_entries d
       where d.tenant_id=p_tenant_id and d.posted=true
         and (d.journal_entry_id is null or not exists(select 1 from public.journal_entries j where j.tenant_id=d.tenant_id and j.id=d.journal_entry_id and j.status='posted'))) as depreciation_without_journal,
      (select count(*) from public.deliveries d
       where d.tenant_id=p_tenant_id and d.status='delivered'
         and not exists(select 1 from public.sales_invoices i where i.tenant_id=d.tenant_id and i.delivery_id=d.id and i.status='posted')) as delivered_without_posted_invoice,
      (select count(*) from public.sales_orders o
       where o.tenant_id=p_tenant_id and o.order_source='order_booker' and o.client_request_id is null) as booker_orders_without_idempotency_key,
      (select count(*) from public.budgets b
       where b.tenant_id=p_tenant_id and b.status='approved'
         and not exists(select 1 from public.budget_lines l where l.tenant_id=b.tenant_id and l.budget_id=b.id)) as approved_budgets_without_lines,
      (select coalesce(sum(a.remaining_amount),0) from public.sales_incentive_adjustments a
       where a.tenant_id=p_tenant_id and a.status='partial') as commission_clawback_remaining
  )
  select jsonb_build_object(
    'success',true,
    'read_only',true,
    'tenant_id',p_tenant_id,
    'checked_at',now(),
    'purchase_returns',jsonb_build_object(
      'posted_without_journal',purchase_returns_without_journal,
      'value_mismatch',purchase_return_value_mismatch,
      'stock_movement_mismatch',purchase_return_stock_mismatch),
    'payroll',jsonb_build_object(
      'posted_runs_without_journal',payroll_runs_without_journal,
      'paid_lines_without_payment_journal',paid_salary_without_payment_journal),
    'fixed_assets',jsonb_build_object('posted_depreciation_without_journal',depreciation_without_journal),
    'delivery',jsonb_build_object('delivered_without_posted_invoice',delivered_without_posted_invoice),
    'booker',jsonb_build_object('orders_without_idempotency_key',booker_orders_without_idempotency_key),
    'budgets',jsonb_build_object('approved_without_lines',approved_budgets_without_lines),
    'commission',jsonb_build_object('partial_clawback_remaining',commission_clawback_remaining),
    'has_integrity_warnings',
      purchase_returns_without_journal+purchase_return_value_mismatch+purchase_return_stock_mismatch+
      payroll_runs_without_journal+paid_salary_without_payment_journal+depreciation_without_journal+
      delivered_without_posted_invoice+booker_orders_without_idempotency_key+approved_budgets_without_lines>0
  ) into v_result from checks;

  return v_result;
end;
$$;

revoke all on function public.get_erp_integration_reconciliation(uuid) from public, anon;
grant execute on function public.get_erp_integration_reconciliation(uuid) to authenticated;
