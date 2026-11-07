-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists owners_update_memberships on public.tenant_memberships;
create policy owners_update_memberships on public.tenant_memberships
for update to authenticated
using (
 public.has_tenant_role(tenant_id,array['owner','admin'])
 and role<>'owner'
 and (public.has_tenant_role(tenant_id,array['owner']) or role<>'admin')
)
with check (
 public.has_tenant_role(tenant_id,array['owner'])
 or (
  public.has_tenant_role(tenant_id,array['admin'])
  and role not in ('owner','admin')
 )
);
drop policy if exists owners_insert_memberships on public.tenant_memberships;
create policy owners_insert_memberships on public.tenant_memberships
for insert to authenticated
with check (
 public.has_tenant_role(tenant_id,array['owner'])
 or (
  public.has_tenant_role(tenant_id,array['admin'])
  and role not in ('owner','admin')
 )
);
