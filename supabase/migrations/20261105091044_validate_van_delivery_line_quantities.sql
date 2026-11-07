-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.record_van_delivery_visit(
 p_delivery_id uuid,p_visit_status text,p_line_quantities jsonb,p_notes text,p_idempotency_key text
) returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_delivery public.deliveries%rowtype; v_line public.delivery_lines%rowtype; v_product public.products%rowtype;
 v_employee public.employees%rowtype; v_existing public.delivery_shop_visits%rowtype;
 x record; lot record; v_remaining numeric; v_net numeric; v_take numeric; v_sold numeric:=0; v_returned numeric:=0;
 v_count integer; v_visit_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if p_idempotency_key is null or length(btrim(p_idempotency_key))<12 then raise exception 'A unique sync key is required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_delivery_id::text||'|'||p_idempotency_key,0));
 select * into v_existing from public.delivery_shop_visits where idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('success',true,'replayed',true,'visit_id',v_existing.id); end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found.'; end if;
 if v_delivery.status<>'dispatched' then raise exception 'Only dispatched van deliveries can be completed.'; end if;
 if v_delivery.vehicle_number is null then raise exception 'Delivery is not linked to a vehicle.'; end if;
 select * into v_employee from public.employees where id=v_delivery.delivery_man_employee_id and tenant_id=v_delivery.tenant_id;
 if not found then raise exception 'Assigned deliveryman employee was not found.'; end if;
 if v_employee.user_id is distinct from auth.uid() and not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager']) then raise exception 'You can only record visits for your own assigned delivery.' using errcode='42501'; end if;
 if p_visit_status not in ('delivered','short_delivered','not_available','market_return','refused') or jsonb_typeof(p_line_quantities)<>'array' then raise exception 'Invalid visit result or line quantities.'; end if;
 select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if v_count=0 or jsonb_array_length(p_line_quantities)<>v_count or
    (select count(distinct z.delivery_line_id) from jsonb_to_recordset(p_line_quantities) as z(delivery_line_id uuid,delivered_quantity_base numeric,market_return_quantity_base numeric,return_batch_number text,return_expiry_date date))<>v_count
 then raise exception 'Submit exactly one quantity record for every delivery line.'; end if;
 for x in select * from jsonb_to_recordset(p_line_quantities) as z(delivery_line_id uuid,delivered_quantity_base numeric,market_return_quantity_base numeric,return_batch_number text,return_expiry_date date) loop
  select * into v_line from public.delivery_lines where id=x.delivery_line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
  if not found or x.delivered_quantity_base is null or x.market_return_quantity_base is null or x.delivered_quantity_base<0 or x.market_return_quantity_base<0 or x.delivered_quantity_base>v_line.picked_quantity_base or x.market_return_quantity_base>x.delivered_quantity_base then raise exception 'Invalid delivered or returned quantity.'; end if;
  select * into v_product from public.products where id=v_line.product_id and tenant_id=v_delivery.tenant_id;
  if x.market_return_quantity_base>0 then
   if v_product.track_batch and nullif(btrim(x.return_batch_number),'') is null then raise exception 'Returned batch number is required for product %.',v_product.name; end if;
   if v_product.track_expiry and x.return_expiry_date is null then raise exception 'Returned expiry date is required for product %.',v_product.name; end if;
   if x.return_expiry_date is not null and x.return_expiry_date<current_date then raise exception 'Expired returned stock cannot be put back on sale.'; end if;
  end if;
  v_net:=x.delivered_quantity_base-x.market_return_quantity_base;v_remaining:=v_net;
  v_sold:=v_sold+v_net;v_returned:=v_returned+x.market_return_quantity_base;
  perform pg_advisory_xact_lock(hashtextextended(v_delivery.tenant_id::text||'|'||upper(v_delivery.vehicle_number)||'|'||v_line.product_id::text,0));
  for lot in
   select batch_number,expiry_date,unit_cost,sum(quantity_in-quantity_out) qty from public.van_stock_movements
   where tenant_id=v_delivery.tenant_id and vehicle_number=upper(v_delivery.vehicle_number) and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date)
   group by batch_number,expiry_date,unit_cost having sum(quantity_in-quantity_out)>0 order by expiry_date nulls last
  loop
   exit when v_remaining<=0;v_take:=least(v_remaining,lot.qty);
   insert into public.van_stock_movements(tenant_id,vehicle_number,employee_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,notes,created_by,idempotency_key)
   values(v_delivery.tenant_id,upper(v_delivery.vehicle_number),v_delivery.delivery_man_employee_id,v_line.product_id,'sale','delivery',v_delivery.id,0,v_take,lot.unit_cost,lot.batch_number,lot.expiry_date,now(),'Van sale from delivery '||v_delivery.delivery_number,auth.uid(),p_idempotency_key||':'||v_line.id||':sale:'||replace(coalesce(lot.batch_number,'none'),':','_'));
   v_remaining:=v_remaining-v_take;
  end loop;
  if v_remaining>0.000001 then raise exception 'Insufficient van stock while completing delivery. Short by %',v_remaining; end if;
  if x.market_return_quantity_base>0 then
   insert into public.van_stock_movements(tenant_id,vehicle_number,employee_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,notes,created_by,idempotency_key)
   values(v_delivery.tenant_id,upper(v_delivery.vehicle_number),v_delivery.delivery_man_employee_id,v_line.product_id,'return','delivery_return',v_delivery.id,x.market_return_quantity_base,0,coalesce(v_product.cost_price,0),nullif(btrim(x.return_batch_number),''),x.return_expiry_date,now(),'Customer return received on van for delivery '||v_delivery.delivery_number,auth.uid(),p_idempotency_key||':'||v_line.id||':return');
  end if;
  update public.delivery_lines set delivered_quantity_base=x.delivered_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 insert into public.delivery_shop_visits(tenant_id,delivery_id,delivery_man_employee_id,customer_id,visit_status,shops_visited,line_quantities,notes,created_by,idempotency_key)
 select v_delivery.tenant_id,v_delivery.id,v_delivery.delivery_man_employee_id,o.customer_id,p_visit_status,1,p_line_quantities,p_notes,auth.uid(),p_idempotency_key
 from public.sales_orders o where o.id=v_delivery.sales_order_id and o.tenant_id=v_delivery.tenant_id
 on conflict(tenant_id,delivery_id) do update set visit_status=excluded.visit_status,line_quantities=excluded.line_quantities,notes=excluded.notes,created_by=excluded.created_by,idempotency_key=excluded.idempotency_key,visit_at=now()
 returning id into v_visit_id;
 update public.deliveries set status=case when v_sold>0 then 'delivered' when v_returned>0 then 'returned' else 'failed' end,delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 update public.sales_orders set status=case when v_sold>0 then 'delivered' else 'returned' end,updated_at=now() where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id;
 return jsonb_build_object('success',true,'replayed',false,'visit_id',v_visit_id,'sold_quantity',v_sold,'returned_quantity',v_returned,'status',case when v_sold>0 then 'delivered' when v_returned>0 then 'returned' else 'failed' end);
end;
$$;
