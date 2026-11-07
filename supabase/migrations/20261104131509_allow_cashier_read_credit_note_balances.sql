-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists sales_credit_notes_read on public.sales_credit_notes;
create policy sales_credit_notes_read on public.sales_credit_notes
for select to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','cashier']));
