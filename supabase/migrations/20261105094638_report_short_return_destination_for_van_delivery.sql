-- Keep delivery short returns on the van ledger when the delivery was dispatched from a vehicle.
do $$
declare d text;
begin
 select pg_get_functiondef('public.complete_delivery(uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,
  '''short_returned_to_warehouse'',true',
  '''short_returned_to_warehouse'',not exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in (''delivery'',''delivery_return'')),''short_remaining_on_van'',exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in (''delivery'',''delivery_return''))');
 execute d;
end;
$$;
