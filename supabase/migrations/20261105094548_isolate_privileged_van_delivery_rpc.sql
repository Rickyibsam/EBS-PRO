-- Keep privileged van delivery completion internals outside the exposed public API schema.
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
alter function public.record_van_delivery_visit(uuid,text,jsonb,text,text) set schema private;
alter function private.record_van_delivery_visit(uuid,text,jsonb,text,text) rename to record_van_delivery_visit_internal;
grant execute on function private.record_van_delivery_visit_internal(uuid,text,jsonb,text,text) to authenticated;
create or replace function public.record_van_delivery_visit(p_delivery_id uuid,p_visit_status text,p_line_quantities jsonb,p_notes text,p_idempotency_key text)
returns jsonb language sql security invoker
set search_path=pg_catalog,public,auth
as $$ select private.record_van_delivery_visit_internal(p_delivery_id,p_visit_status,p_line_quantities,p_notes,p_idempotency_key); $$;
revoke all on function public.record_van_delivery_visit(uuid,text,jsonb,text,text) from public,anon;
grant execute on function public.record_van_delivery_visit(uuid,text,jsonb,text,text) to authenticated;
