-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists owners_update_memberships on public.tenant_memberships;
create policy owners_update_memberships on public.tenant_memberships
for update to authenticated
using (public.has_tenant_role(tenant_id, ARRAY['owner'::text,'admin'::text]) and role <> 'owner')
with check (
 public.has_tenant_role(tenant_id, ARRAY['owner'::text])
 or (public.has_tenant_role(tenant_id, ARRAY['admin'::text]) and role <> 'owner')
);
drop policy if exists owners_insert_memberships on public.tenant_memberships;
create policy owners_insert_memberships on public.tenant_memberships
for insert to authenticated
with check (
 public.has_tenant_role(tenant_id, ARRAY['owner'::text])
 or (public.has_tenant_role(tenant_id, ARRAY['admin'::text]) and role <> 'owner')
);
drop policy if exists owners_delete_memberships on public.tenant_memberships;
create policy owners_delete_memberships on public.tenant_memberships
for delete to authenticated
using (public.has_tenant_role(tenant_id, ARRAY['owner'::text,'admin'::text]) and role <> 'owner');
