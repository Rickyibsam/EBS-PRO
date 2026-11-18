-- Keep the clean-replay dispatch RPC aligned with the hardened production
-- implementation. Earlier text-replacement migrations could silently miss the
-- product lookup when formatting changed, causing tracked-product filters to
-- evaluate against an uninitialized row and report zero van stock.

CREATE OR REPLACE FUNCTION public.dispatch_van_delivery(p_delivery_id uuid, p_vehicle_number text, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare v_delivery public.deliveries%rowtype;v_line public.delivery_lines%rowtype;x record;v_available numeric;v_count integer;v_product public.products%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found.'; end if;
 if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only authorized distribution/warehouse users can dispatch a van delivery.' using errcode='42501'; end if;
 if v_delivery.delivery_man_employee_id is null or not exists(select 1 from public.employees where id=v_delivery.delivery_man_employee_id and tenant_id=v_delivery.tenant_id and employment_status='active') then raise exception 'Assign an active deliveryman before van dispatch.'; end if;
 if v_delivery.status not in ('pending','picked') then
  if v_delivery.status='dispatched' and upper(coalesce(v_delivery.vehicle_number,''))=upper(btrim(p_vehicle_number)) then return jsonb_build_object('success',true,'replayed',true,'delivery_id',v_delivery.id,'status',v_delivery.status); end if;
  raise exception 'Only pending or picked deliveries can be dispatched.';
 end if;
 if nullif(btrim(p_vehicle_number),'') is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Vehicle and picked line quantities are required.'; end if;
 select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if v_count=0 or jsonb_array_length(p_lines)<>v_count or
    (select count(distinct z.line_id) from jsonb_to_recordset(p_lines) as z(line_id uuid,picked_quantity_base numeric))<>v_count then
  raise exception 'Provide exactly one picked quantity for every delivery line.';
 end if;
 for x in select * from jsonb_to_recordset(p_lines) as z(line_id uuid,picked_quantity_base numeric) loop
  select * into v_line from public.delivery_lines where id=x.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
  if not found or x.picked_quantity_base is null or x.picked_quantity_base<0 or x.picked_quantity_base>v_line.quantity_base then raise exception 'Invalid picked quantity or delivery line.'; end if;
  if x.picked_quantity_base>0 then
   perform pg_advisory_xact_lock(hashtextextended(v_delivery.tenant_id::text||'|'||upper(btrim(p_vehicle_number))||'|'||v_line.product_id::text,0)); select * into v_product from public.products where id=v_line.product_id and tenant_id=v_delivery.tenant_id; if not found then raise exception 'Delivery product is not in this tenant.'; end if;
   select greatest(0,coalesce(sum(quantity_in-quantity_out),0)-coalesce((select sum(r.reserved_quantity) from public.van_delivery_reservations r where r.tenant_id=v_delivery.tenant_id and r.vehicle_number=upper(btrim(p_vehicle_number)) and r.product_id=v_line.product_id and r.status='active' and r.delivery_line_id<>v_line.id),0)) into v_available from public.van_stock_movements
    where tenant_id=v_delivery.tenant_id and vehicle_number=upper(btrim(p_vehicle_number)) and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date) and (not v_product.track_expiry or expiry_date is not null) and (not v_product.track_batch or batch_number is not null);
   if v_available<x.picked_quantity_base then raise exception 'Insufficient non-expired unreserved van stock for product %. Available %',v_line.product_id,v_available; end if; insert into public.van_delivery_reservations(tenant_id,delivery_id,delivery_line_id,vehicle_number,product_id,reserved_quantity,status,created_by) values(v_delivery.tenant_id,v_delivery.id,v_line.id,upper(btrim(p_vehicle_number)),v_line.product_id,x.picked_quantity_base,'active',auth.uid()) on conflict(tenant_id,delivery_line_id) do update set reserved_quantity=excluded.reserved_quantity,status='active',vehicle_number=excluded.vehicle_number,updated_at=now() where public.van_delivery_reservations.status='released';
  end if;
  update public.delivery_lines set picked_quantity_base=x.picked_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 update public.deliveries set status='dispatched',vehicle_number=upper(btrim(p_vehicle_number)) where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 update public.sales_orders set status='dispatched',updated_at=now() where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status in ('approved','allocated');
 return jsonb_build_object('success',true,'replayed',false,'delivery_id',v_delivery.id,'vehicle_number',upper(btrim(p_vehicle_number)),'status','dispatched');
end;
$function$

