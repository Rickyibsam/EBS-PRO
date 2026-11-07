-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
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
  if not public.has_tenant_role(v_grn.tenant_id, array['owner','admin','manager','purchase','warehouse']) then
    raise exception 'You do not have permission to post goods receipts';
  end if;
  if v_grn.status <> 'draft' then raise exception 'Only draft goods receipts can be posted'; end if;

  if not exists (select 1 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity > 0) then
    raise exception 'At least one accepted quantity is required';
  end if;

  for v_line in
    select * from public.goods_receipt_lines
    where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id
    for update
  loop
    if v_line.accepted_quantity + v_line.rejected_quantity > v_line.quantity then
      raise exception 'Accepted plus rejected quantity exceeds received quantity';
    end if;
    if v_line.accepted_quantity > 0 then
      insert into public.stock_movements
        (tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,
         quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
      values
        (v_grn.tenant_id,v_grn.warehouse_id,v_line.product_id,'purchase_receipt',
         'goods_receipt',v_grn.id,
         v_line.accepted_quantity*v_line.conversion_to_base,0,v_line.unit_cost,
         v_line.batch_number,v_line.expiry_date,now(),v_user,'Posted from GRN '||v_grn.grn_number);
    end if;
    update public.purchase_order_lines
       set received_base_quantity = coalesce(received_base_quantity,0) + (v_line.accepted_quantity*v_line.conversion_to_base)
     where tenant_id=v_grn.tenant_id
       and purchase_order_id=v_grn.purchase_order_id
       and product_id=v_line.product_id
       and unit_id=v_line.unit_id;
  end loop;

  select coalesce(bool_and(coalesce(received_base_quantity,0) >= quantity*conversion_to_base),false)
    into v_all_received
    from public.purchase_order_lines
   where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;

  update public.purchase_orders
     set status = case when v_all_received then 'received' else 'part_received' end,
         updated_at=now()
   where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id
     and status in ('approved','part_received');

  update public.goods_receipts set status='posted',posted_at=now()
   where id=v_grn.id and tenant_id=v_grn.tenant_id;
  return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted');
end;
$$;

create or replace function public.dispatch_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_delivery public.deliveries%rowtype;
  v_line public.delivery_lines%rowtype;
  v_input record;
  v_balance numeric;
  v_value numeric;
  v_cost numeric;
  v_count integer;
  v_positive integer := 0;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_delivery from public.deliveries where id=p_delivery_id for update;
  if not found then raise exception 'Delivery not found'; end if;
  if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager']) then
    raise exception 'Only an owner, admin or manager can confirm dispatch';
  end if;
  if v_delivery.status not in ('pending','picked') then raise exception 'Only pending or picked deliveries can be dispatched'; end if;
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Dispatch lines must be an array'; end if;
  select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a picked quantity for every delivery line'; end if;
  if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,picked_quantity_base numeric)) <> v_count then
    raise exception 'Duplicate or missing delivery line IDs';
  end if;

  for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,picked_quantity_base numeric)
  loop
    select * into v_line from public.delivery_lines
     where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id
     for update;
    if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
    if v_input.picked_quantity_base is null or v_input.picked_quantity_base < 0 or v_input.picked_quantity_base > v_line.quantity_base then
      raise exception 'Picked quantity must be between zero and ordered quantity';
    end if;
    if v_input.picked_quantity_base > 0 then
      v_positive := v_positive + 1;
      perform pg_advisory_xact_lock(hashtextextended(v_delivery.tenant_id::text||':'||v_delivery.warehouse_id::text||':'||v_line.product_id::text,0));
      select coalesce(sum(quantity_in-quantity_out),0),
             coalesce(sum(quantity_in*unit_cost)-sum(quantity_out*unit_cost),0)
        into v_balance,v_value
        from public.stock_movements
       where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id;
      if v_balance < v_input.picked_quantity_base then
        raise exception 'Insufficient stock for product %. Available %, requested %',v_line.product_id,v_balance,v_input.picked_quantity_base;
      end if;
      v_cost := case when v_balance>0 then greatest(v_value/v_balance,0) else 0 end;
      insert into public.stock_movements
        (tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,
         quantity_in,quantity_out,unit_cost,movement_at,created_by,notes)
      values
        (v_delivery.tenant_id,v_delivery.warehouse_id,v_line.product_id,'sale_dispatch',
         'delivery',v_delivery.id,0,v_input.picked_quantity_base,v_cost,now(),v_user,
         'Stock issued for delivery '||v_delivery.delivery_number);
    end if;
    update public.delivery_lines set picked_quantity_base=v_input.picked_quantity_base
     where id=v_line.id and tenant_id=v_delivery.tenant_id;
  end loop;
  if v_positive=0 then raise exception 'At least one product quantity must be picked'; end if;
  update public.deliveries set status='dispatched' where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
  update public.sales_orders set status='dispatched',updated_at=now()
   where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id
     and status in ('approved','allocated');
  return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','dispatched');
end;
$$;

create or replace function public.complete_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
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
  if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then
    raise exception 'You do not have permission to confirm delivery';
  end if;
  if v_delivery.status <> 'dispatched' then raise exception 'Only dispatched deliveries can be completed'; end if;
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Delivery confirmation lines must be an array'; end if;
  select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a delivered quantity for every delivery line'; end if;
  if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric)) <> v_count then
    raise exception 'Duplicate or missing delivery line IDs';
  end if;
  for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric)
  loop
    select * into v_line from public.delivery_lines
     where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id
     for update;
    if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
    if v_input.delivered_quantity_base is null or v_input.delivered_quantity_base<0 or v_input.delivered_quantity_base>v_line.picked_quantity_base then
      raise exception 'Delivered quantity must be between zero and picked quantity';
    end if;
    update public.delivery_lines set delivered_quantity_base=v_input.delivered_quantity_base
     where id=v_line.id and tenant_id=v_delivery.tenant_id;
  end loop;
  select coalesce(bool_and(delivered_quantity_base=picked_quantity_base),false)
    into v_all_delivered from public.delivery_lines
   where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
  if v_all_delivered then
    update public.deliveries set status='delivered',delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
    update public.sales_orders set status='delivered',updated_at=now()
     where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status='dispatched';
  end if;
  return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status',case when v_all_delivered then 'delivered' else 'dispatched' end);
end;
$$;

create or replace function public.post_journal_entry(p_journal_entry_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_entry public.journal_entries%rowtype;
  v_debit numeric;
  v_credit numeric;
  v_lines integer;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_entry from public.journal_entries where id=p_journal_entry_id for update;
  if not found then raise exception 'Journal entry not found'; end if;
  if not public.has_tenant_role(v_entry.tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'You do not have permission to post journal entries';
  end if;
  if v_entry.status <> 'draft' then raise exception 'Only draft journals can be posted'; end if;
  select coalesce(sum(debit),0),coalesce(sum(credit),0),count(*)
    into v_debit,v_credit,v_lines
    from public.journal_lines where tenant_id=v_entry.tenant_id and journal_entry_id=v_entry.id;
  if v_lines<2 or v_debit<=0 or abs(v_debit-v_credit)>0.005 then
    raise exception 'Journal must contain at least two lines with equal positive debit and credit totals';
  end if;
  update public.journal_entries set status='posted',posted_by=v_user,posted_at=now()
   where id=v_entry.id and tenant_id=v_entry.tenant_id;
  return jsonb_build_object('success',true,'journal_entry_id',v_entry.id,'status','posted','debit',v_debit,'credit',v_credit);
end;
$$;

revoke all on function public.post_goods_receipt(uuid) from public, anon;
revoke all on function public.dispatch_delivery(uuid,jsonb) from public, anon;
revoke all on function public.complete_delivery(uuid,jsonb) from public, anon;
revoke all on function public.post_journal_entry(uuid) from public, anon;
grant execute on function public.post_goods_receipt(uuid) to authenticated;
grant execute on function public.dispatch_delivery(uuid,jsonb) to authenticated;
grant execute on function public.complete_delivery(uuid,jsonb) to authenticated;
grant execute on function public.post_journal_entry(uuid) to authenticated;
