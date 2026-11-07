-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop index if exists public.audit_logs_tenant_created_idx2;

revoke all on function public.create_tenant(text,text,text,text) from public, anon;
grant execute on function public.create_tenant(text,text,text,text) to authenticated;

revoke all on function public.has_tenant_role(uuid,text[]) from public, anon;
grant execute on function public.has_tenant_role(uuid,text[]) to authenticated;

revoke all on function public.is_tenant_member(uuid) from public, anon;
grant execute on function public.is_tenant_member(uuid) to authenticated;

revoke all on function public.bootstrap_tenant_warehouse() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
