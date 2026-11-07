-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

grant delete on public.payroll_runs to authenticated;
drop policy if exists payroll_runs_delete_draft on public.payroll_runs;
create policy payroll_runs_delete_draft on public.payroll_runs for delete to authenticated using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
