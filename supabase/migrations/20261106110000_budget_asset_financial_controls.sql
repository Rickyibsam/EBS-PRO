-- Database-enforced budget and fixed-asset controls.
create or replace function private.enforce_budget_header_integrity()
returns trigger language plpgsql set search_path=pg_catalog,public,private,auth as $$
begin
 if new.period_start is null or new.period_end is null or new.period_start>new.period_end then raise exception 'Invalid budget period.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text||':approved-budget-periods',0));
 if tg_op='UPDATE' then
  if old.status='closed' and new.status<>'closed' then raise exception 'Closed budgets cannot be reopened.'; end if;
  if old.status='approved' and new.status not in ('approved','closed') then raise exception 'Approved budgets can only be closed.'; end if;
  if old.status in ('approved','closed') and (new.period_start is distinct from old.period_start or new.period_end is distinct from old.period_end) then raise exception 'Approved/closed budget dates are locked.'; end if;
 end if;
 if new.status='approved' then
  if not exists(select 1 from public.budget_lines l where l.tenant_id=new.tenant_id and l.budget_id=new.id) then raise exception 'A budget needs at least one line before approval.'; end if;
  if exists(select 1 from public.budgets b where b.tenant_id=new.tenant_id and b.id is distinct from new.id and b.status='approved' and daterange(b.period_start,b.period_end,'[]') && daterange(new.period_start,new.period_end,'[]')) then raise exception 'Another approved budget overlaps this period.'; end if;
 end if;
 return new;
end $$;
drop trigger if exists budgets_integrity_guard on public.budgets;
create trigger budgets_integrity_guard before insert or update on public.budgets for each row execute function private.enforce_budget_header_integrity();

create or replace function private.enforce_budget_line_integrity()
returns trigger language plpgsql set search_path=pg_catalog,public,private,auth as $$
declare v_budget public.budgets%rowtype; v_account public.chart_of_accounts%rowtype;
begin
 if tg_op in ('UPDATE','DELETE') then
  select * into v_budget from public.budgets where id=old.budget_id and tenant_id=old.tenant_id for update;
  if not found or v_budget.status<>'draft' then raise exception 'Budget lines are locked after approval.'; end if;
 end if;
 if tg_op<>'DELETE' then
  select * into v_budget from public.budgets where id=new.budget_id and tenant_id=new.tenant_id for update;
  if not found or v_budget.status<>'draft' then raise exception 'Budget lines can only be changed in a draft budget.'; end if;
  if new.budget_amount is null or new.budget_amount<=0 then raise exception 'Budget amount must be positive.'; end if;
  select * into v_account from public.chart_of_accounts where id=new.account_id and tenant_id=new.tenant_id;
  if not found or not v_account.is_active or v_account.account_type not in ('income','expense') then raise exception 'Budget line needs an active income/expense account from the same company.'; end if;
  if new.branch_id is not null and not exists(select 1 from public.branches br where br.id=new.branch_id and br.tenant_id=new.tenant_id) then raise exception 'Budget branch must belong to the same company.'; end if;
  if exists(select 1 from public.budget_lines l where l.tenant_id=new.tenant_id and l.budget_id=new.budget_id and l.account_id=new.account_id and l.branch_id is not distinct from new.branch_id and l.id is distinct from new.id) then raise exception 'Duplicate budget account/branch line.'; end if;
  return new;
 end if;
 return old;
end $$;
drop trigger if exists budget_lines_integrity_guard on public.budget_lines;
create trigger budget_lines_integrity_guard before insert or update or delete on public.budget_lines for each row execute function private.enforce_budget_line_integrity();

create or replace function private.validate_fixed_asset_account_mappings()
returns trigger language plpgsql set search_path=pg_catalog,public,private,auth as $$
begin
 if new.asset_cost_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.asset_cost_account_id and tenant_id=new.tenant_id and is_active and account_type='asset') then raise exception 'Asset cost mapping must be an active company asset account.'; end if;
 if new.accumulated_depreciation_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.accumulated_depreciation_account_id and tenant_id=new.tenant_id and is_active and account_type='asset') then raise exception 'Accumulated depreciation mapping must be an active company asset account.'; end if;
 if new.depreciation_expense_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.depreciation_expense_account_id and tenant_id=new.tenant_id and is_active and account_type='expense') then raise exception 'Depreciation mapping must be an active company expense account.'; end if;
 if new.cash_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.cash_account_id and tenant_id=new.tenant_id and is_active and account_type='asset') then raise exception 'Disposal proceeds mapping must be an active company cash/bank asset account.'; end if;
 if new.disposal_gain_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.disposal_gain_account_id and tenant_id=new.tenant_id and is_active and account_type='income') then raise exception 'Disposal gain mapping must be an active company income account.'; end if;
 if new.disposal_loss_account_id is not null and not exists(select 1 from public.chart_of_accounts where id=new.disposal_loss_account_id and tenant_id=new.tenant_id and is_active and account_type='expense') then raise exception 'Disposal loss mapping must be an active company expense account.'; end if;
 if new.asset_cost_account_id is not null and new.asset_cost_account_id=new.accumulated_depreciation_account_id then raise exception 'Asset cost and accumulated depreciation accounts must differ.'; end if;
 if new.cash_account_id is not null and new.cash_account_id in (new.asset_cost_account_id,new.accumulated_depreciation_account_id) then raise exception 'Cash/bank and asset accounts must differ.'; end if;
 return new;
end $$;
drop trigger if exists fixed_asset_account_mappings_integrity_guard on public.fixed_asset_account_mappings;
create trigger fixed_asset_account_mappings_integrity_guard before insert or update on public.fixed_asset_account_mappings for each row execute function private.validate_fixed_asset_account_mappings();

create or replace function private.validate_fixed_asset_values()
returns trigger language plpgsql set search_path=pg_catalog,public,private,auth as $$
begin
 if new.acquisition_date is null or new.acquisition_cost is null or new.acquisition_cost<=0 or new.salvage_value is null or new.salvage_value<0 or new.salvage_value>new.acquisition_cost or new.useful_life_months is null or new.useful_life_months<1 then raise exception 'Fixed asset needs valid acquisition date, cost, salvage value and useful life.'; end if;
 if new.depreciation_method<>'straight_line' then raise exception 'Only straight-line depreciation is supported.'; end if;
 if new.status='disposed' and (new.disposal_date is null or new.disposal_date<new.acquisition_date or new.disposal_amount is null or new.disposal_amount<0) then raise exception 'Disposed assets need a valid disposal date and non-negative proceeds.'; end if;
 return new;
end $$;
drop trigger if exists fixed_assets_value_guard on public.fixed_assets;
create trigger fixed_assets_value_guard before insert or update on public.fixed_assets for each row execute function private.validate_fixed_asset_values();

create or replace function public.get_budget_actuals(p_tenant_id uuid)
returns table(budget_line_id uuid,budget_id uuid,account_id uuid,branch_id uuid,budget_amount numeric,actual_amount numeric,variance numeric,period_start date,period_end date,actual_scope_supported boolean)
language plpgsql security invoker set search_path=pg_catalog,public,private,auth as $$
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(p_tenant_id,'accounts_finance','view')) then raise exception 'Accounts/budget view permission required.' using errcode='42501'; end if;
 return query
 select bl.id,bl.budget_id,bl.account_id,bl.branch_id,bl.budget_amount,
  case when bl.branch_id is null then coalesce(sum(case when je.id is not null then case when coa.account_type='income' then jl.credit-jl.debit else jl.debit-jl.credit end else 0 end),0) else null end,
  case when bl.branch_id is null then bl.budget_amount-coalesce(sum(case when je.id is not null then case when coa.account_type='income' then jl.credit-jl.debit else jl.debit-jl.credit end else 0 end),0) else null end,
  b.period_start,b.period_end,(bl.branch_id is null)
 from public.budget_lines bl join public.budgets b on b.id=bl.budget_id and b.tenant_id=bl.tenant_id
 join public.chart_of_accounts coa on coa.id=bl.account_id and coa.tenant_id=bl.tenant_id
 left join public.journal_lines jl on jl.tenant_id=bl.tenant_id and jl.account_id=bl.account_id
 left join public.journal_entries je on je.id=jl.journal_entry_id and je.tenant_id=jl.tenant_id and je.status='posted' and je.entry_date between b.period_start and b.period_end
 where bl.tenant_id=p_tenant_id
 group by bl.id,bl.budget_id,bl.account_id,bl.branch_id,bl.budget_amount,b.period_start,b.period_end,coa.account_type
 order by b.period_start desc,coa.account_type,bl.account_id;
end $$;
revoke all on function public.get_budget_actuals(uuid) from public,anon;
grant execute on function public.get_budget_actuals(uuid) to authenticated;
