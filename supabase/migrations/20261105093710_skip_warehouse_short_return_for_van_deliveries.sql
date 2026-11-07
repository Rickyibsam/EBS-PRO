-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.complete_delivery(uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,
  'from public.delivery_lines dl where dl.tenant_id=v_delivery.tenant_id and dl.delivery_id=v_delivery.id',
  'from public.delivery_lines dl where dl.tenant_id=v_delivery.tenant_id and dl.delivery_id=v_delivery.id and v_delivery.vehicle_number is null');
 execute d;
end;
$$;
