-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare v_definition text;
begin
 select pg_get_functiondef('public.record_van_delivery_visit(uuid,text,jsonb,text,text)'::regprocedure) into v_definition;
 v_definition:=replace(v_definition,'where idempotency_key=p_idempotency_key;','where idempotency_key=p_idempotency_key and delivery_id=p_delivery_id;');
 execute v_definition;
end;
$$;
