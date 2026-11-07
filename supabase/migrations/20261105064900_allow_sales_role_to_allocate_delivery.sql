-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists module_insert on public.deliveries;
create policy module_insert on public.deliveries for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse','sales']));
drop policy if exists module_insert on public.delivery_lines;
create policy module_insert on public.delivery_lines for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse','sales']));
