CREATE OR REPLACE FUNCTION public.get_erp_report_summary(p_tenant_id uuid, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null
     or not (
       (
         public.has_tenant_role(p_tenant_id, array['owner','admin','manager','accounts','sales','purchase','viewer'])
         or private.module_permission_grant_internal(p_tenant_id, 'reports_analytics', 'view')
       )
       and private.module_permission_guard_internal(p_tenant_id, 'reports_analytics', 'view')
     ) then
    raise exception 'You do not have permission to view company reports.' using errcode='42501';
  end if;

  if p_from_date is not null and p_to_date is not null and p_from_date > p_to_date then
    raise exception 'Report start date cannot be later than end date.' using errcode='22007';
  end if;

  with
  period_sales_orders as (
    select so.* from public.sales_orders so
    where so.tenant_id=p_tenant_id
      and (p_from_date is null or so.order_date::date>=p_from_date)
      and (p_to_date is null or so.order_date::date<=p_to_date)
  ),
  period_purchase_orders as (
    select po.* from public.purchase_orders po
    where po.tenant_id=p_tenant_id
      and (p_from_date is null or po.order_date::date>=p_from_date)
      and (p_to_date is null or po.order_date::date<=p_to_date)
  ),
  period_sales_invoices as (
    select si.*,so.booker_employee_id,so.route_id
    from public.sales_invoices si
    left join public.sales_orders so
      on so.id=si.sales_order_id and so.tenant_id=si.tenant_id
    where si.tenant_id=p_tenant_id and si.status='posted'
      and (p_from_date is null or si.invoice_date>=p_from_date)
      and (p_to_date is null or si.invoice_date<=p_to_date)
  ),
  all_sales_invoices as (
    select si.* from public.sales_invoices si
    where si.tenant_id=p_tenant_id and si.status='posted'
      and (p_to_date is null or si.invoice_date<=p_to_date)
  ),
  period_sales_credits as (
    select cn.* from public.sales_credit_notes cn
    where cn.tenant_id=p_tenant_id and cn.status='posted'
      and (p_from_date is null or cn.credit_note_date>=p_from_date)
      and (p_to_date is null or cn.credit_note_date<=p_to_date)
  ),
  all_sales_credits as (
    select cn.sales_invoice_id,sum(cn.grand_total)::numeric as amount
    from public.sales_credit_notes cn
    where cn.tenant_id=p_tenant_id and cn.status='posted'
      and (p_to_date is null or cn.credit_note_date<=p_to_date)
    group by cn.sales_invoice_id
  ),
  period_purchase_invoices as (
    select pi.* from public.purchase_invoices pi
    where pi.tenant_id=p_tenant_id and pi.status='posted'
      and (p_from_date is null or pi.invoice_date>=p_from_date)
      and (p_to_date is null or pi.invoice_date<=p_to_date)
  ),
  all_purchase_invoices as (
    select pi.* from public.purchase_invoices pi
    where pi.tenant_id=p_tenant_id and pi.status='posted'
      and (p_to_date is null or pi.invoice_date<=p_to_date)
  ),
  period_purchase_returns as (
    select dn.* from public.purchase_debit_notes dn
    where dn.tenant_id=p_tenant_id and dn.status='posted'
      and (p_from_date is null or dn.note_date>=p_from_date)
      and (p_to_date is null or dn.note_date<=p_to_date)
  ),
  all_purchase_returns as (
    select dn.goods_receipt_id,sum(dn.subtotal)::numeric as amount
    from public.purchase_debit_notes dn
    where dn.tenant_id=p_tenant_id and dn.status='posted'
      and (p_to_date is null or dn.note_date<=p_to_date)
    group by dn.goods_receipt_id
  ),
  period_payments as (
    select pay.* from public.payments pay
    where pay.tenant_id=p_tenant_id
      and (p_from_date is null or pay.payment_date>=p_from_date)
      and (p_to_date is null or pay.payment_date<=p_to_date)
  ),
  allocated_sales_receipts as (
    select pay.sales_invoice_id,sum(pay.amount)::numeric as amount
    from public.payments pay
    where pay.tenant_id=p_tenant_id and pay.payment_type='receipt'
      and pay.sales_invoice_id is not null
      and (p_to_date is null or pay.payment_date<=p_to_date)
    group by pay.sales_invoice_id
  ),
  allocated_purchase_payments as (
    select pay.purchase_invoice_id,sum(pay.amount)::numeric as amount
    from public.payments pay
    where pay.tenant_id=p_tenant_id and pay.payment_type='payment'
      and pay.purchase_invoice_id is not null
      and (p_to_date is null or pay.payment_date<=p_to_date)
    group by pay.purchase_invoice_id
  ),
  sales_balances as (
    select si.id,greatest(si.grand_total-coalesce(r.amount,0)-coalesce(c.amount,0),0)::numeric as outstanding
    from all_sales_invoices si
    left join allocated_sales_receipts r on r.sales_invoice_id=si.id
    left join all_sales_credits c on c.sales_invoice_id=si.id
  ),
  purchase_balances as (
    select pi.id,
      greatest(pi.grand_total-coalesce(pay.amount,0)-coalesce(ret.amount,0),0)::numeric as outstanding
    from all_purchase_invoices pi
    left join allocated_purchase_payments pay on pay.purchase_invoice_id=pi.id
    left join all_purchase_returns ret on ret.goods_receipt_id=pi.goods_receipt_id
  ),
  period_expenses as (
    select ex.* from public.expenses ex
    where ex.tenant_id=p_tenant_id
      and (p_from_date is null or ex.expense_date>=p_from_date)
      and (p_to_date is null or ex.expense_date<=p_to_date)
  ),
  period_payroll as (
    select pr.* from public.payroll_runs pr
    where pr.tenant_id=p_tenant_id and pr.status='posted'
      and (p_from_date is null or pr.pay_date>=p_from_date)
      and (p_to_date is null or pr.pay_date<=p_to_date)
  ),
  period_stock_cost as (
    select
      coalesce(sum(case when sm.movement_type='sale_dispatch' then sm.quantity_out*sm.unit_cost
                        when sm.movement_type='sales_return' then -sm.quantity_in*sm.unit_cost
                        else 0 end),0)::numeric as cost
    from public.stock_movements sm
    where sm.tenant_id=p_tenant_id
      and (p_from_date is null or sm.movement_at::date>=p_from_date)
      and (p_to_date is null or sm.movement_at::date<=p_to_date)
  ),
  period_van_cost as (
    select
      coalesce(sum(case when vm.movement_type='sale' then vm.quantity_out*vm.unit_cost
                        when vm.movement_type='return' then -vm.quantity_in*vm.unit_cost
                        else 0 end),0)::numeric as cost
    from public.van_stock_movements vm
    where vm.tenant_id=p_tenant_id
      and (p_from_date is null or vm.movement_at::date>=p_from_date)
      and (p_to_date is null or vm.movement_at::date<=p_to_date)
  ),
  period_revenue as (
    select
      coalesce((select sum(si.subtotal-coalesce(si.discount_total,0)) from period_sales_invoices si),0)
      - coalesce((select sum(cn.subtotal-coalesce(cn.discount_total,0)) from period_sales_credits cn),0) as amount
  ),
  stock_as_of as (
    select sm.product_id,sum(sm.quantity_in-sm.quantity_out)::numeric as quantity
    from public.stock_movements sm
    where sm.tenant_id=p_tenant_id
      and (p_to_date is null or sm.movement_at < (p_to_date+1)::timestamp)
    group by sm.product_id
  ),
  sales_by_daily as (
    select si.invoice_date::text as label,sum(si.grand_total)::numeric as amount
    from period_sales_invoices si group by si.invoice_date
  ),
  sales_by_customer as (
    select coalesce(pa.name,'Unassigned customer') as label,sum(si.grand_total)::numeric as amount
    from period_sales_invoices si
    left join public.parties pa on pa.id=si.customer_id and pa.tenant_id=p_tenant_id
    group by coalesce(pa.name,'Unassigned customer')
  ),
  sales_by_product as (
    select coalesce(pr.name,'Unknown product') as label,sum(l.line_total)::numeric as amount
    from public.sales_invoice_lines l
    join period_sales_invoices si on si.id=l.sales_invoice_id
    left join public.products pr on pr.id=l.product_id and pr.tenant_id=p_tenant_id
    group by coalesce(pr.name,'Unknown product')
  ),
  sales_by_brand as (
    select coalesce(nullif(btrim(pr.brand),''),'Unbranded / not set') as label,sum(l.line_total)::numeric as amount
    from public.sales_invoice_lines l
    join period_sales_invoices si on si.id=l.sales_invoice_id
    left join public.products pr on pr.id=l.product_id and pr.tenant_id=p_tenant_id
    group by coalesce(nullif(btrim(pr.brand),''),'Unbranded / not set')
  ),
  sales_by_area as (
    select coalesce(rt.name,'Unassigned area / route') as label,sum(si.grand_total)::numeric as amount
    from period_sales_invoices si
    left join public.sales_routes rt on rt.id=si.route_id and rt.tenant_id=p_tenant_id
    group by coalesce(rt.name,'Unassigned area / route')
  ),
  sales_by_booker as (
    select coalesce(em.full_name,'Back office / unassigned') as label,sum(si.grand_total)::numeric as amount
    from period_sales_invoices si
    left join public.employees em on em.id=si.booker_employee_id and em.tenant_id=p_tenant_id
    group by coalesce(em.full_name,'Back office / unassigned')
  ),
  purchases_by_supplier as (
    select coalesce(pa.name,'Unassigned supplier') as label,sum(pi.grand_total)::numeric as amount
    from period_purchase_invoices pi
    left join public.parties pa on pa.id=pi.supplier_id and pa.tenant_id=p_tenant_id
    group by coalesce(pa.name,'Unassigned supplier')
  ),
  stock_by_product as (
    select coalesce(pr.name,'Unknown product') as label,sum(sa.quantity)::numeric as amount
    from stock_as_of sa
    left join public.products pr on pr.id=sa.product_id and pr.tenant_id=p_tenant_id
    group by coalesce(pr.name,'Unknown product')
    having sum(sa.quantity)<>0
  )
  select jsonb_build_object(
    'counts',jsonb_build_object(
      'sales_orders',(select count(*) from period_sales_orders),
      'purchase_orders',(select count(*) from period_purchase_orders),
      'products',(select count(*) from public.products where tenant_id=p_tenant_id),
      'parties',(select count(*) from public.parties where tenant_id=p_tenant_id),
      'payments',(select count(*) from period_payments),
      'stock_movements',(select count(*) from public.stock_movements sm where sm.tenant_id=p_tenant_id and (p_from_date is null or sm.movement_at::date>=p_from_date) and (p_to_date is null or sm.movement_at::date<=p_to_date)),
      'deliveries',(select count(*) from public.deliveries d where d.tenant_id=p_tenant_id and (p_from_date is null or d.delivery_date>=p_from_date) and (p_to_date is null or d.delivery_date<=p_to_date)),
      'expenses',(select count(*) from period_expenses),
      'sales_credit_notes',(select count(*) from period_sales_credits),
      'purchase_invoices',(select count(*) from period_purchase_invoices),
      'purchase_debit_notes',(select count(*) from period_purchase_returns),
      'payroll_runs',(select count(*) from period_payroll)
    ),
    'totals',jsonb_build_object(
      'Sales orders (non-draft)',coalesce((select sum(so.grand_total) from period_sales_orders so where so.status not in ('draft','cancelled')),0),
      'Purchase orders (non-draft)',coalesce((select sum(po.grand_total) from period_purchase_orders po where po.status not in ('draft','cancelled')),0),
      'Posted sales invoices',coalesce((select sum(si.grand_total) from period_sales_invoices si),0),
      'Accounts receivable',coalesce((select sum(sb.outstanding) from sales_balances sb),0),
      'Posted sales credit notes',coalesce((select sum(cn.grand_total) from period_sales_credits cn),0),
      'Customer receipts (period)',coalesce((select sum(pay.amount) from period_payments pay where pay.payment_type='receipt'),0),
      'Vendor invoices posted',coalesce((select sum(pi.grand_total) from period_purchase_invoices pi),0),
      'Vendor debit notes',coalesce((select sum(dn.subtotal) from period_purchase_returns dn),0),
      'Accounts payable',coalesce((select sum(pb.outstanding) from purchase_balances pb),0),
      'Vendor payments (period)',coalesce((select sum(pay.amount) from period_payments pay where pay.payment_type='payment'),0),
      'Payroll expense',coalesce((select sum(pr.gross_total) from period_payroll pr),0),
      'Cost of goods issued',(select cost from period_stock_cost)+(select cost from period_van_cost),
      'Gross profit (before expenses)',(select amount from period_revenue)-((select cost from period_stock_cost)+(select cost from period_van_cost)),
      'Expenses',coalesce((select sum(ex.amount) from period_expenses ex),0),
      'Net operating result (before other adjustments)',(select amount from period_revenue)-((select cost from period_stock_cost)+(select cost from period_van_cost))-coalesce((select sum(ex.amount) from period_expenses ex),0)
    ),
    'breakdowns',jsonb_build_object(
      'daily',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.label) from sales_by_daily x),'[]'::jsonb),
      'customers',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from sales_by_customer x),'[]'::jsonb),
      'products',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from sales_by_product x),'[]'::jsonb),
      'brands',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from sales_by_brand x),'[]'::jsonb),
      'areas',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from sales_by_area x),'[]'::jsonb),
      'bookers',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from sales_by_booker x),'[]'::jsonb),
      'vendors',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from purchases_by_supplier x),'[]'::jsonb),
      'stock',coalesce((select jsonb_agg(jsonb_build_object('label',x.label,'amount',x.amount) order by x.amount desc) from stock_by_product x),'[]'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$function$

