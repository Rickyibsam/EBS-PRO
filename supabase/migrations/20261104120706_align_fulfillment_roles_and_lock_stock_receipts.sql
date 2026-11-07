-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_grn public.goods_receipts%rowtype;
  v_line record;
  v_user uuid := auth.uid();
  v_all_received boolean;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
  if not found then raise exception 'Goods receipt not found'; end if;
  if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then
    raise exception 'You do not have permission to post goods receipts';
  end if;
  if v_grn.status <> 'draft' then raise exception 'Only draft goods receipts can be posted'; end if;
  if not exists(select 1 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0) then
    raise exception 'At least one accepted quantity is required';
  end if;
  for v_line in
    select * from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id for update
  loop
    if v_line.accepted_quantity+v_line.rejected_quantity>v_line.quantity then raise exception 'Accepted plus rejected quantity exceeds received quantity'; end if;
    if v_line.purchase_order_line_id is null then raise exception 'A goods receipt line is not linked to its purchase order line'; end if;
    if not exists(select 1 from public.purchase_order_lines pol where pol.id=v_line.purchase_order_line_id and pol.tenant_id=v_grn.tenant_id and pol.purchase_order_id=v_grn.purchase_order_id and pol.product_id=v_line.product_id and pol.unit_id=v_line.unit_id) then
      raise exception 'A goods receipt line does not match its purchase order line';
    end if;
    if v_line.accepted_quantity>0 then
      perform pg_advisory_xact_lock(hashtextextended(v_grn.tenant_id::text||':'||v_grn.warehouse_id::text||':'||v_line.product_id::text,0));
      insert into public.stock_movements
       (tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
      values
       (v_grn.tenant_id,v_grn.warehouse_id,v_line.product_id,'purchase_receipt','goods_receipt',v_grn.id,
        v_line.accepted_quantity*v_line.conversion_to_base,0,v_line.unit_cost,v_line.batch_number,v_line.expiry_date,now(),v_user,'Posted from GRN '||v_grn.grn_number);
    end if;
    update public.purchase_order_lines
      set received_base_quantity=coalesce(received_base_quantity,0)+(v_line.accepted_quantity*v_line.conversion_to_base)
      where id=v_line.purchase_order_line_id and tenant_id=v_grn.tenant_id;
  end loop;
  select coalesce(bool_and(coalesce(received_base_quantity,0)>=quantity*conversion_to_base),false)
   into v_all_received from public.purchase_order_lines
   where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;
  update public.purchase_orders set status=case when v_all_received then 'received' else 'part_received' end,updated_at=now()
   where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id and status in ('approved','part_received');
  update public.goods_receipts set status='posted',posted_at=now() where id=v_grn.id and tenant_id=v_grn.tenant_id;
  return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted');
end;
$$;
create or replace function public.complete_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_delivery public.deliveries%rowtype;
  v_line public.delivery_lines%rowtype;
  v_input record;
  v_count integer;
  v_all_delivered boolean;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_delivery from public.deliveries where id=p_delivery_id for update;
  if not found then raise exception 'Delivery not found'; end if;
  if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager']) then
    raise exception 'Only an owner, admin or manager can confirm delivery';
  end if;
  if v_delivery.status <> 'dispatched' then raise exception 'Only dispatched deliveries can be completed'; end if;
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Delivery confirmation lines must be an array'; end if;
  select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a delivered quantity for every delivery line'; end if;
  if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric)) <> v_count then raise exception 'Duplicate or missing delivery line IDs'; end if;
  for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric)
  loop
    select * into v_line from public.delivery_lines where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
    if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
    if v_input.delivered_quantity_base is null or v_input.delivered_quantity_base<0 or v_input.delivered_quantity_base>v_line.picked_quantity_base then raise exception 'Delivered quantity must be between zero and picked quantity'; end if;
    update public.delivery_lines set delivered_quantity_base=v_input.delivered_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
  end loop;
  select coalesce(bool_and(delivered_quantity_base=picked_quantity_base),false) into v_all_delivered
    from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
  if v_all_delivered then
    update public.deliveries set status='delivered',delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
    update public.sales_orders set status='delivered',updated_at=now() where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status='dispatched';
  end if;
  return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status',case when v_all_delivered then 'delivered' else 'dispatched' end);
end;
$$;
