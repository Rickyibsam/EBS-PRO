-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.deliveries
 add column if not exists route_id uuid references public.sales_routes(id),
 add column if not exists delivery_man_employee_id uuid references public.employees(id);

create index if not exists deliveries_tenant_route_idx on public.deliveries(tenant_id,route_id,delivery_date);
create index if not exists deliveries_tenant_driver_idx on public.deliveries(tenant_id,delivery_man_employee_id,delivery_date);

create table if not exists public.sales_targets (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 target_name text not null,
 period_start date not null,
 period_end date not null,
 employee_id uuid references public.employees(id),
 target_role text not null check(target_role in ('order_booker','delivery_man')),
 vendor_id uuid references public.parties(id),
 brand text,
 product_id uuid references public.products(id),
 target_metric text not null check(target_metric in ('net_sales','delivered_qty','shops_visited','orders_booked','shops_delivered')),
 target_value numeric(18,3) not null check(target_value>0),
 incentive_amount numeric(18,2) not null default 0 check(incentive_amount>=0),
 incentive_rate numeric(9,4) not null default 0 check(incentive_rate>=0),
 is_active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(period_end>=period_start),
 check(vendor_id is null or target_role='order_booker')
);
create index if not exists sales_targets_tenant_period_idx on public.sales_targets(tenant_id,period_start,period_end,employee_id);
alter table public.sales_targets enable row level security;
drop policy if exists sales_targets_management_read on public.sales_targets;
create policy sales_targets_management_read on public.sales_targets for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
drop policy if exists sales_targets_management_insert on public.sales_targets;
create policy sales_targets_management_insert on public.sales_targets for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales']) and (created_by is null or created_by=(select auth.uid())));
drop policy if exists sales_targets_management_update on public.sales_targets;
create policy sales_targets_management_update on public.sales_targets for update to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales']));
drop policy if exists sales_targets_management_delete on public.sales_targets;
create policy sales_targets_management_delete on public.sales_targets for delete to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin']));

create or replace function public.create_delivery_for_approved_order(p_sales_order_id uuid,p_delivery_man_employee_id uuid default null)
returns jsonb language plpgsql set search_path='pg_catalog','public','auth'
as $$
declare v_order public.sales_orders%rowtype; v_delivery_id uuid; v_no text; v_count bigint; v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_order from public.sales_orders where id=p_sales_order_id for update;
 if not found then raise exception 'Sales order not found'; end if;
 if not public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) then raise exception 'Not allowed to allocate delivery'; end if;
 if v_order.status not in ('approved','allocated') then raise exception 'Only approved sales orders can be allocated'; end if;
 if exists(select 1 from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id and status not in ('cancelled')) then
  select id,delivery_number into v_delivery_id,v_no from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id order by created_at desc limit 1;
  return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',true);
 end if;
 if v_delivery_man_employee_id is not null and not exists(select 1 from public.employees e where e.id=v_delivery_man_employee_id and e.tenant_id=v_order.tenant_id and e.employment_status='active') then raise exception 'Delivery man must be an active employee of this company'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_order.tenant_id::text||':delivery-number',0));
 select coalesce(max(nullif(regexp_replace(delivery_number,'[^0-9]','','g'),'')::bigint),0)+1 into v_count from public.deliveries where tenant_id=v_order.tenant_id;
 v_no:='DLV-'||lpad(v_count::text,5,'0');
 insert into public.deliveries(tenant_id,sales_order_id,warehouse_id,delivery_number,delivery_date,driver_name,vehicle_number,status,notes,route_id,delivery_man_employee_id)
 values(v_order.tenant_id,v_order.id,v_order.warehouse_id,v_no,coalesce(v_order.required_delivery_date,current_date),null,null,'pending',v_order.notes,v_order.route_id,p_delivery_man_employee_id)
 returning id into v_delivery_id;
 insert into public.delivery_lines(tenant_id,delivery_id,product_id,quantity_base,picked_quantity_base,delivered_quantity_base,sales_order_line_id)
 select v_order.tenant_id,v_delivery_id,sol.product_id,sol.quantity*sol.conversion_to_base,0,0,sol.id
 from public.sales_order_lines sol where sol.tenant_id=v_order.tenant_id and sol.sales_order_id=v_order.id;
 if not exists(select 1 from public.delivery_lines where tenant_id=v_order.tenant_id and delivery_id=v_delivery_id) then raise exception 'Sales order has no lines'; end if;
 update public.sales_orders set status='allocated',updated_at=now() where id=v_order.id and tenant_id=v_order.tenant_id;
 return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',false);
end $$;
revoke all on function public.create_delivery_for_approved_order(uuid,uuid) from public,anon;
grant execute on function public.create_delivery_for_approved_order(uuid,uuid) to authenticated;
