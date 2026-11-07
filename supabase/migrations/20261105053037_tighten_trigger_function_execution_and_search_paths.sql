-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

revoke all on function public.attach_party_to_control_journal_line() from public,anon,authenticated;
revoke all on function public.ensure_tenant_default_price_list() from public,anon,authenticated;
revoke all on function public.guard_payroll_line_mutation() from public,anon,authenticated;
revoke all on function public.sync_default_price_from_product() from public,anon,authenticated;
revoke all on function public.sync_default_price_from_product_unit() from public,anon,authenticated;
revoke all on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) from public,anon;
grant execute on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) to authenticated;
revoke all on function public.has_tenant_role(uuid,text[]) from anon;
revoke all on function public.is_tenant_member(uuid) from anon;
revoke all on function public.create_tenant(text,text,text,text) from anon;
create or replace function public.guard_posted_payroll_run()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status<>'draft' then raise exception 'Posted or void payroll runs cannot be modified';end if;
 return new;
end $$;
