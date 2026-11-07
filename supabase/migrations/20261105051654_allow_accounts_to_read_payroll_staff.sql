-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists employees_select_accounts_payroll on public.employees;
create policy employees_select_accounts_payroll on public.employees for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
