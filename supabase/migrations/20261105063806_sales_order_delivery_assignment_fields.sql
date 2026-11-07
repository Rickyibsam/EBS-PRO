-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.sales_orders add column if not exists delivery_man_employee_id uuid references public.employees(id);
create index if not exists sales_orders_tenant_booker_idx on public.sales_orders(tenant_id,booker_employee_id,order_date);
create index if not exists sales_orders_tenant_route_idx on public.sales_orders(tenant_id,route_id,order_date);
create or replace function public.create_delivery_for_approved_order(p_sales_order_id uuid,p_delivery_man_employee_id uuid default null)
returns jsonb language plpgsql set search_path='pg_catalog','public','auth'
as $$
declare v_order public.sales_orders%rowtype; v_delivery_id uuid; v_no text; v_count bigint; v_user uuid:=auth.uid(); v_driver uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_order from public.sales_orders where id=p_sales_order_id for update;
 if not found then raise exception 'Sales order not found'; end if;
 if not public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) then raise exception 'Not allowed to allocate delivery'; end if;
 if v_order.status not in ('approved','allocated') then raise exception 'Only approved sales orders can be allocated'; end if;
 v_driver:=coalesce(p_delivery_man_employee_id,v_order.delivery_man_employee_id);
 if v_driver is not null and not exists(select 1 from public.employees e where e.id=v_driver and e.tenant_id=v_order.tenant_id and e.employment_status='active') then raise exception 'Delivery man must be an active employee of this company'; end if;
 if exists(select 1 from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id and status not in ('cancelled')) then
  select id,delivery_number into v_delivery_id,v_no from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id order by created_at desc limit 1;
  return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(v_order.tenant_id::text||':delivery-number',0));
 select coalesce(max(nullif(regexp_replace(delivery_number,'[^0-9]','','g'),'')::bigint),0)+1 into v_count from public.deliveries where tenant_id=v_order.tenant_id;
 v_no:='DLV-'||lpad(v_count::text,5,'0');
 insert into public.deliveries(tenant_id,sales_order_id,warehouse_id,delivery_number,delivery_date,driver_name,vehicle_number,status,notes,route_id,delivery_man_employee_id)
 values(v_order.tenant_id,v_order.id,v_order.warehouse_id,v_no,coalesce(v_order.required_delivery_date,current_date),null,null,'pending',v_order.notes,v_order.route_id,v_driver)
 returning id into v_delivery_id;
 insert into public.delivery_lines(tenant_id,delivery_id,product_id,quantity_base,picked_quantity_base,delivered_quantity_base,sales_order_line_id)
 select v_order.tenant_id,v_delivery_id,sol.product_id,sol.quantity*sol.conversion_to_base,0,0,sol.id
 from public.sales_order_lines sol where sol.tenant_id=v_order.tenant_id and sol.sales_order_id=v_order.id;
 if not exists(select 1 from public.delivery_lines where tenant_id=v_order.tenant_id and delivery_id=v_delivery_id) then raise exception 'Sales order has no lines'; end if;
 update public.sales_orders set status='allocated',delivery_man_employee_id=v_driver,updated_at=now() where id=v_order.id and tenant_id=v_order.tenant_id;
 return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',false);
end $$;
revoke all on function public.create_delivery_for_approved_order(uuid,uuid) from public,anon;
grant execute on function public.create_delivery_for_approved_order(uuid,uuid) to authenticated;
