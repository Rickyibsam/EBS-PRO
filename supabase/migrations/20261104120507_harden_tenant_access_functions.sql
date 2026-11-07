-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter function public.create_tenant(text,text,text,text) set search_path = pg_catalog, public, auth;
alter function public.has_tenant_role(uuid,text[]) set search_path = pg_catalog, public, auth;
alter function public.is_tenant_member(uuid) set search_path = pg_catalog, public, auth;

revoke all on function public.create_tenant(text,text,text,text) from public, anon;
revoke all on function public.has_tenant_role(uuid,text[]) from public, anon;
revoke all on function public.is_tenant_member(uuid) from public, anon;

grant execute on function public.create_tenant(text,text,text,text) to authenticated;
grant execute on function public.has_tenant_role(uuid,text[]) to authenticated;
grant execute on function public.is_tenant_member(uuid) to authenticated;
