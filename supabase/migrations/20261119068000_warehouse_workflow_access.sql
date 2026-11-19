-- Warehouse-facing read access is limited to active receiving/delivery work.
drop policy if exists sales_orders_warehouse_delivery_read on public.sales_orders;
create policy sales_orders_warehouse_delivery_read
on public.sales_orders for select to authenticated
using (
  status in ('approved','allocated','dispatched')
  and (
    private.has_tenant_role_internal(tenant_id,array['warehouse'])
    or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
  )
);

drop policy if exists sales_order_lines_warehouse_delivery_read on public.sales_order_lines;
create policy sales_order_lines_warehouse_delivery_read
on public.sales_order_lines for select to authenticated
using (
  (
    private.has_tenant_role_internal(tenant_id,array['warehouse'])
    or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
  )
  and exists(
    select 1 from public.sales_orders so
    where so.id=sales_order_lines.sales_order_id and so.tenant_id=sales_order_lines.tenant_id
      and so.status in ('approved','allocated','dispatched')
  )
);

drop policy if exists sales_order_lines_delivery_man_assigned_read on public.sales_order_lines;
create policy sales_order_lines_delivery_man_assigned_read
on public.sales_order_lines for select to authenticated
using (
  private.has_tenant_role_internal(tenant_id,array['delivery_man'])
  and exists(
    select 1 from public.deliveries d
    join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
    where d.tenant_id=sales_order_lines.tenant_id
      and d.sales_order_id=sales_order_lines.sales_order_id
      and e.user_id=auth.uid()
  )
);

drop policy if exists sales_routes_warehouse_delivery_read on public.sales_routes;
create policy sales_routes_warehouse_delivery_read
on public.sales_routes for select to authenticated
using (
  is_active and (
    private.has_tenant_role_internal(tenant_id,array['warehouse'])
    or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
  )
);

drop policy if exists sales_routes_delivery_man_assigned_read on public.sales_routes;
create policy sales_routes_delivery_man_assigned_read
on public.sales_routes for select to authenticated
using (
  private.has_tenant_role_internal(tenant_id,array['delivery_man'])
  and exists(
    select 1 from public.deliveries d
    join public.employees e on e.id=d.delivery_man_employee_id and e.tenant_id=d.tenant_id
    where d.tenant_id=sales_routes.tenant_id and d.route_id=sales_routes.id
      and e.user_id=auth.uid()
  )
);

drop policy if exists purchase_orders_warehouse_receiving_read on public.purchase_orders;
create policy purchase_orders_warehouse_receiving_read
on public.purchase_orders for select to authenticated
using (
  private.has_tenant_role_internal(tenant_id,array['warehouse'])
  and status in ('approved','part_received')
);

drop policy if exists purchase_order_lines_warehouse_receiving_read on public.purchase_order_lines;
create policy purchase_order_lines_warehouse_receiving_read
on public.purchase_order_lines for select to authenticated
using (
  private.has_tenant_role_internal(tenant_id,array['warehouse'])
  and exists(
    select 1 from public.purchase_orders po
    where po.id=purchase_order_lines.purchase_order_id and po.tenant_id=purchase_order_lines.tenant_id
      and po.status in ('approved','part_received')
  )
);

-- Delivery module visibility can independently authorize delivery staff to see
-- the operational order/route data without granting the broader sales module.
drop policy if exists module_override_guard_select on public.sales_orders;
create policy module_override_guard_select
on public.sales_orders as restrictive for select to authenticated
using (
  (
    not private.has_tenant_role_internal(tenant_id,array['warehouse'])
    and private.module_permission_guard_internal(tenant_id,'sales_customer','view')
  )
  or (
    private.has_tenant_role_internal(tenant_id,array['warehouse','delivery_man'])
    and private.module_permission_guard_internal(tenant_id,'distribution_delivery','view')
  )
  or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
);

drop policy if exists module_override_guard_select on public.sales_order_lines;
create policy module_override_guard_select
on public.sales_order_lines as restrictive for select to authenticated
using (
  (
    not private.has_tenant_role_internal(tenant_id,array['warehouse'])
    and private.module_permission_guard_internal(tenant_id,'sales_customer','view')
  )
  or (
    private.has_tenant_role_internal(tenant_id,array['warehouse','delivery_man'])
    and private.module_permission_guard_internal(tenant_id,'distribution_delivery','view')
  )
  or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
);

drop policy if exists module_override_guard_select on public.sales_routes;
create policy module_override_guard_select
on public.sales_routes as restrictive for select to authenticated
using (
  (
    not private.has_tenant_role_internal(tenant_id,array['warehouse'])
    and private.module_permission_guard_internal(tenant_id,'order_booking','view')
  )
  or (
    private.has_tenant_role_internal(tenant_id,array['warehouse','delivery_man'])
    and private.module_permission_guard_internal(tenant_id,'distribution_delivery','view')
  )
  or private.module_permission_grant_internal(tenant_id,'distribution_delivery','view')
);

create or replace function public.get_delivery_staff(p_tenant_id uuid)
returns table(id uuid,full_name text,employee_code text,job_title text,branch_id uuid)
language plpgsql
security definer
set search_path=pg_catalog,public,private,auth
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not (
    public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
    or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','view')
  ) then
    raise exception 'Distribution delivery view permission required' using errcode='42501';
  end if;
  return query
  select e.id,e.full_name::text,e.employee_code::text,e.job_title::text,e.branch_id
  from public.employees e
  where e.tenant_id=p_tenant_id and e.employment_status='active'
  order by e.full_name,e.id;
end
$function$;

revoke all on function public.get_delivery_staff(uuid) from public,anon;
grant execute on function public.get_delivery_staff(uuid) to authenticated;


CREATE OR REPLACE FUNCTION public.post_goods_receipt(p_goods_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
 v_grn public.goods_receipts%rowtype; v_line record; v_user uuid:=auth.uid(); v_all_received boolean;
 v_total numeric:=0; v_inventory_account uuid; v_grni_account uuid; v_journal_id uuid; v_journal_no text;
 v_role_allowed boolean; v_is_owner_admin boolean; v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found then raise exception 'Goods receipt not found'; end if;
 v_role_allowed:=public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(v_grn.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p
   where p.tenant_id=v_grn.tenant_id and p.user_id=v_user and p.module_key='purchase_supplier')
 into v_has_override;
 if not v_role_allowed then
   if not private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','update') then
     raise exception 'Goods receipt posting permission required' using errcode='42501';
   end if;
 elsif not v_is_owner_admin and v_has_override
       and not private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','update') then
   raise exception 'Goods receipt posting is disabled for this user' using errcode='42501';
 end if;
 if v_grn.status<>'draft' then raise exception 'Only draft goods receipts can be posted'; end if;
 if not exists(select 1 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0) then raise exception 'At least one accepted quantity is required'; end if;
 select id into v_inventory_account from public.chart_of_accounts where tenant_id=v_grn.tenant_id and account_code='1200' and is_active;
 select id into v_grni_account from public.chart_of_accounts where tenant_id=v_grn.tenant_id and account_code='2100' and is_active;
 for v_line in select * from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id for update loop
  if v_line.accepted_quantity+v_line.rejected_quantity>v_line.quantity then raise exception 'Accepted plus rejected quantity exceeds received quantity'; end if;
  if v_line.purchase_order_line_id is null then raise exception 'A goods receipt line is not linked to its purchase order line'; end if;
  if not exists(select 1 from public.purchase_order_lines pol where pol.id=v_line.purchase_order_line_id and pol.tenant_id=v_grn.tenant_id and pol.purchase_order_id=v_grn.purchase_order_id and pol.product_id=v_line.product_id and pol.unit_id=v_line.unit_id) then raise exception 'A goods receipt line does not match its purchase order line'; end if;
  if v_line.accepted_quantity>0 then
   perform pg_advisory_xact_lock(hashtextextended(v_grn.tenant_id::text||':'||v_grn.warehouse_id::text||':'||v_line.product_id::text,0));
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_grn.tenant_id,v_grn.warehouse_id,v_line.product_id,'purchase_receipt','goods_receipt',v_grn.id,v_line.accepted_quantity*v_line.conversion_to_base,0,v_line.unit_cost/v_line.conversion_to_base,v_line.batch_number,v_line.expiry_date,now(),v_user,'Posted from GRN '||v_grn.grn_number);
   v_total:=v_total+(v_line.accepted_quantity*v_line.unit_cost);
  end if;
  update public.purchase_order_lines set received_base_quantity=coalesce(received_base_quantity,0)+(v_line.accepted_quantity*v_line.conversion_to_base) where id=v_line.purchase_order_line_id and tenant_id=v_grn.tenant_id;
 end loop;
 select coalesce(bool_and(coalesce(received_base_quantity,0)>=quantity*conversion_to_base),false) into v_all_received from public.purchase_order_lines where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;
 update public.purchase_orders set status=case when v_all_received then 'received' else 'part_received' end,updated_at=now() where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id and status in ('approved','part_received');
 if v_total>0 then
  if v_inventory_account is null or v_grni_account is null then raise exception 'Default Inventory and GRNI accounts are missing'; end if;
  v_journal_no:='EBS-GRN-JV-'||right(replace(v_grn.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_grn.tenant_id,v_journal_no,v_grn.received_date,'goods_receipt',v_grn.id,'Inventory received against GRN '||v_grn.grn_number,'posted',v_user,v_user,now()) returning id into v_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_grn.tenant_id,v_journal_id,v_inventory_account,v_total,0,'Accepted goods received'),(v_grn.tenant_id,v_journal_id,v_grni_account,0,v_total,'Goods received not invoiced');
 end if;
 update public.goods_receipts set status='posted',posted_at=now() where id=v_grn.id and tenant_id=v_grn.tenant_id;
 return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted','inventory_value',v_total);
end;
$function$;

revoke all on function public.post_goods_receipt(uuid) from public,anon;
grant execute on function public.post_goods_receipt(uuid) to authenticated;


