-- Add a branch dimension to the general ledger and infer it from source documents.
-- Existing journal/business rows are not rewritten; historical unassigned entries remain explicitly unassigned.
alter table public.journal_entries add column if not exists branch_id uuid references public.branches(id) on delete set null;
alter table public.fixed_assets add column if not exists branch_id uuid references public.branches(id) on delete set null;
create index if not exists journal_entries_tenant_branch_date_idx on public.journal_entries(tenant_id,branch_id,entry_date,status);
create index if not exists fixed_assets_tenant_branch_idx on public.fixed_assets(tenant_id,branch_id);

create or replace function private.assign_journal_entry_branch()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,private,auth
as $function$
declare v_branch uuid; v_other_branch uuid;
begin
 if new.branch_id is not null then
  if not exists(select 1 from public.branches b where b.id=new.branch_id and b.tenant_id=new.tenant_id) then
   raise exception 'Journal branch must belong to the same company.';
  end if;
  return new;
 end if;

 case new.source_type
  when 'sales_invoice' then
   select so.branch_id into v_branch from public.sales_invoices i join public.sales_orders so on so.id=i.sales_order_id and so.tenant_id=i.tenant_id where i.id=new.source_id and i.tenant_id=new.tenant_id;
  when 'sales_credit_note' then
   select so.branch_id into v_branch from public.sales_credit_notes n join public.sales_invoices i on i.id=n.sales_invoice_id and i.tenant_id=n.tenant_id join public.sales_orders so on so.id=i.sales_order_id and so.tenant_id=i.tenant_id where n.id=new.source_id and n.tenant_id=new.tenant_id;
  when 'goods_receipt' then
   select w.branch_id into v_branch from public.goods_receipts g join public.warehouses w on w.id=g.warehouse_id and w.tenant_id=g.tenant_id where g.id=new.source_id and g.tenant_id=new.tenant_id;
  when 'purchase_invoice' then
   select w.branch_id into v_branch from public.purchase_invoices i join public.goods_receipts g on g.id=i.goods_receipt_id and g.tenant_id=i.tenant_id join public.warehouses w on w.id=g.warehouse_id and w.tenant_id=g.tenant_id where i.id=new.source_id and i.tenant_id=new.tenant_id;
  when 'purchase_debit_note' then
   select w.branch_id into v_branch from public.purchase_debit_notes n join public.warehouses w on w.id=n.warehouse_id and w.tenant_id=n.tenant_id where n.id=new.source_id and n.tenant_id=new.tenant_id;
  when 'purchase_return' then
   select w.branch_id into v_branch from public.purchase_debit_notes n join public.warehouses w on w.id=n.warehouse_id and w.tenant_id=n.tenant_id where n.id=new.source_id and n.tenant_id=new.tenant_id;
  when 'delivery_cogs' then
   select w.branch_id into v_branch from public.deliveries d join public.warehouses w on w.id=d.warehouse_id and w.tenant_id=d.tenant_id where d.id=new.source_id and d.tenant_id=new.tenant_id;
  when 'delivery_charge' then
   select w.branch_id into v_branch from public.delivery_charge_collections c join public.delivery_charges ch on ch.id=c.delivery_charge_id and ch.tenant_id=c.tenant_id join public.deliveries d on d.id=ch.delivery_id and d.tenant_id=ch.tenant_id join public.warehouses w on w.id=d.warehouse_id and w.tenant_id=d.tenant_id where c.id=new.source_id and c.tenant_id=new.tenant_id;
  when 'asset_depreciation' then
   select a.branch_id into v_branch from public.fixed_assets a where a.id=new.source_id and a.tenant_id=new.tenant_id;
  when 'asset_disposal' then
   select a.branch_id into v_branch from public.fixed_assets a where a.id=new.source_id and a.tenant_id=new.tenant_id;
  when 'payroll_payment' then
   select e.branch_id into v_branch from public.payroll_lines l join public.employees e on e.id=l.employee_id and e.tenant_id=l.tenant_id where l.id=new.source_id and l.tenant_id=new.tenant_id;
  when 'payroll' then
   select case when count(distinct e.branch_id)=1 then (array_agg(distinct e.branch_id) filter(where e.branch_id is not null))[1] else null end
    into v_branch from public.payroll_lines l join public.employees e on e.id=l.employee_id and e.tenant_id=l.tenant_id
    where l.tenant_id=new.tenant_id and l.payroll_run_id=new.source_id;
  when 'payment' then
   select case
     when p.sales_invoice_id is not null then (select so.branch_id from public.sales_invoices i join public.sales_orders so on so.id=i.sales_order_id and so.tenant_id=i.tenant_id where i.id=p.sales_invoice_id and i.tenant_id=p.tenant_id)
     when p.purchase_invoice_id is not null then (select w.branch_id from public.purchase_invoices i join public.goods_receipts g on g.id=i.goods_receipt_id and g.tenant_id=i.tenant_id join public.warehouses w on w.id=g.warehouse_id and w.tenant_id=g.tenant_id where i.id=p.purchase_invoice_id and i.tenant_id=p.tenant_id)
     else null end into v_branch from public.payments p where p.id=new.source_id and p.tenant_id=new.tenant_id;
  when 'expense' then
   select e.branch_id into v_branch from public.expenses e where e.id=new.source_id and e.tenant_id=new.tenant_id;
  when 'stock_transfer' then
   select wf.branch_id,wt.branch_id into v_branch,v_other_branch from public.stock_transfers t
   join public.warehouses wf on wf.id=t.from_warehouse_id and wf.tenant_id=t.tenant_id
   join public.warehouses wt on wt.id=t.to_warehouse_id and wt.tenant_id=t.tenant_id
   where t.id=new.source_id and t.tenant_id=new.tenant_id;
   if v_branch is distinct from v_other_branch then v_branch:=null; end if;
  else
   v_branch:=null;
 end case;

 if v_branch is not null and not exists(select 1 from public.branches b where b.id=v_branch and b.tenant_id=new.tenant_id) then
  raise exception 'Source document resolved to a branch outside the journal company.';
 end if;
 new.branch_id:=v_branch;
 return new;
end;
$function$;
revoke all on function private.assign_journal_entry_branch() from public,anon,authenticated;
drop trigger if exists journal_entries_branch_inference on public.journal_entries;
create trigger journal_entries_branch_inference
before insert or update
on public.journal_entries
for each row execute function private.assign_journal_entry_branch();

create or replace function private.validate_fixed_asset_branch()
returns trigger
language plpgsql
set search_path=pg_catalog,public,private,auth
as $function$
begin
 if new.branch_id is not null and not exists(select 1 from public.branches b where b.id=new.branch_id and b.tenant_id=new.tenant_id) then
  raise exception 'Fixed asset branch must belong to the same company.';
 end if;
 return new;
end;
$function$;
drop trigger if exists fixed_assets_branch_guard on public.fixed_assets;
create trigger fixed_assets_branch_guard before insert or update on public.fixed_assets for each row execute function private.validate_fixed_asset_branch();

create or replace function public.get_budget_actuals(p_tenant_id uuid)
returns table(budget_line_id uuid,budget_id uuid,account_id uuid,branch_id uuid,budget_amount numeric,actual_amount numeric,variance numeric,period_start date,period_end date,actual_scope_supported boolean)
language plpgsql security invoker set search_path=pg_catalog,public,private,auth as $function$
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(p_tenant_id,'accounts_finance','view')) then raise exception 'Accounts/budget view permission required.' using errcode='42501'; end if;
 return query
 select bl.id,bl.budget_id,bl.account_id,bl.branch_id,bl.budget_amount,
  case
   when bl.branch_id is not null and exists(
    select 1 from public.journal_lines jl2 join public.journal_entries je2 on je2.id=jl2.journal_entry_id and je2.tenant_id=jl2.tenant_id
    where jl2.tenant_id=bl.tenant_id and jl2.account_id=bl.account_id and je2.status='posted'
      and je2.entry_date between b.period_start and b.period_end and je2.branch_id is null
   ) then null
   else coalesce(sum(case when je.id is not null then case when coa.account_type='income' then jl.credit-jl.debit else jl.debit-jl.credit end else 0 end),0)
  end as actual_amount,
  case
   when bl.branch_id is not null and exists(
    select 1 from public.journal_lines jl2 join public.journal_entries je2 on je2.id=jl2.journal_entry_id and je2.tenant_id=jl2.tenant_id
    where jl2.tenant_id=bl.tenant_id and jl2.account_id=bl.account_id and je2.status='posted'
      and je2.entry_date between b.period_start and b.period_end and je2.branch_id is null
   ) then null
   else bl.budget_amount-coalesce(sum(case when je.id is not null then case when coa.account_type='income' then jl.credit-jl.debit else jl.debit-jl.credit end else 0 end),0)
  end as variance,
  b.period_start,b.period_end,
  (bl.branch_id is null or not exists(
    select 1 from public.journal_lines jl2 join public.journal_entries je2 on je2.id=jl2.journal_entry_id and je2.tenant_id=jl2.tenant_id
    where jl2.tenant_id=bl.tenant_id and jl2.account_id=bl.account_id and je2.status='posted'
      and je2.entry_date between b.period_start and b.period_end and je2.branch_id is null
  ))
 from public.budget_lines bl join public.budgets b on b.id=bl.budget_id and b.tenant_id=bl.tenant_id
 join public.chart_of_accounts coa on coa.id=bl.account_id and coa.tenant_id=bl.tenant_id
 left join public.journal_lines jl on jl.tenant_id=bl.tenant_id and jl.account_id=bl.account_id
 left join public.journal_entries je on je.id=jl.journal_entry_id and je.tenant_id=jl.tenant_id and je.status='posted'
   and je.entry_date between b.period_start and b.period_end
   and (bl.branch_id is null or je.branch_id=bl.branch_id)
 where bl.tenant_id=p_tenant_id
 group by bl.id,bl.budget_id,bl.account_id,bl.branch_id,bl.budget_amount,b.period_start,b.period_end,coa.account_type
 order by b.period_start desc,coa.account_type,bl.account_id;
end;
$function$;
revoke all on function public.get_budget_actuals(uuid) from public,anon;
grant execute on function public.get_budget_actuals(uuid) to authenticated;
