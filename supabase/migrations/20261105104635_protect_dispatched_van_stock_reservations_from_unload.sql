-- Serialize all vehicle/product movements and prevent warehouse unloads
-- from consuming stock reserved for dispatched deliveries.
do $$
declare d text;anchor text;pos integer;replacement text;
begin
 select pg_get_functiondef('public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text)'::regprocedure) into d;
 d:=replace(d,'v_available numeric := 0;','v_available numeric := 0;'||chr(10)||' v_total_available numeric := 0;'||chr(10)||' v_reserved numeric := 0;');
 anchor:='perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||''|''||p_warehouse_id::text||''|''||upper(btrim(p_vehicle_number))||''|''||p_product_id::text||''|''||coalesce(p_batch_number,'''')||''|''||coalesce(p_expiry_date::text,''''),0));';
 replacement:='perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||''|''||upper(btrim(p_vehicle_number))||''|''||p_product_id::text,0));'||chr(10)||' '||anchor;
 d:=replace(d,anchor,replacement);
 anchor:='if v_available<p_quantity then raise exception ''Insufficient van batch stock. Available: %'',v_available using errcode=''23514''; end if;';
 pos:=strpos(d,anchor);
 if pos=0 then raise exception 'Unload quantity guard was not found.'; end if;
 replacement:=anchor||chr(10)||
 '  select coalesce(sum(quantity_in-quantity_out),0) into v_total_available from public.van_stock_movements where tenant_id=p_tenant_id and vehicle_number=upper(btrim(p_vehicle_number)) and product_id=p_product_id;'||chr(10)||
 '  select coalesce(sum(reserved_quantity),0) into v_reserved from public.van_delivery_reservations where tenant_id=p_tenant_id and vehicle_number=upper(btrim(p_vehicle_number)) and product_id=p_product_id and status=''active'';'||chr(10)||
 '  if v_total_available-p_quantity<v_reserved then raise exception ''This quantity is reserved for dispatched deliveries. Available for unload: %'',greatest(0,v_total_available-v_reserved) using errcode=''23514''; end if;';
 d:=overlay(d placing replacement from pos for length(anchor));
 execute d;
end;
$$;
