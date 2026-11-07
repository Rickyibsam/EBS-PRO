-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists payments_purchase_supplier_read on public.payments;
create policy payments_purchase_supplier_read on public.payments for select to authenticated using(payment_type='payment' and public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
