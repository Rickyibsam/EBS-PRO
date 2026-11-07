-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.complete_delivery(uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,
  'and v_delivery.vehicle_number is null',
  'and not exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in (''delivery'',''delivery_return''))');
 execute d;
end;
$$;
