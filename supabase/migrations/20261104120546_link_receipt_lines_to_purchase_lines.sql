-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.goods_receipt_lines
  add column if not exists purchase_order_line_id uuid;

create unique index if not exists purchase_order_lines_id_tenant_uidx
  on public.purchase_order_lines(id,tenant_id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='goods_receipt_lines_po_line_tenant_fkey'
      and conrelid='public.goods_receipt_lines'::regclass
  ) then
    alter table public.goods_receipt_lines
      add constraint goods_receipt_lines_po_line_tenant_fkey
      foreign key (purchase_order_line_id,tenant_id)
      references public.purchase_order_lines(id,tenant_id);
  end if;
end $$;

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
  if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase','warehouse']) then
    raise exception 'You do not have permission to post goods receipts';
  end if;
  if v_grn.status <> 'draft' then raise exception 'Only draft goods receipts can be posted'; end if;
  if not exists(select 1 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0) then
    raise exception 'At least one accepted quantity is required';
  end if;
  for v_line in
    select * from public.goods_receipt_lines
    where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id
    for update
  loop
    if v_line.accepted_quantity+v_line.rejected_quantity>v_line.quantity then
      raise exception 'Accepted plus rejected quantity exceeds received quantity';
    end if;
    if v_line.purchase_order_line_id is null then
      raise exception 'A goods receipt line is not linked to its purchase order line';
    end if;
    if not exists(select 1 from public.purchase_order_lines pol where pol.id=v_line.purchase_order_line_id and pol.tenant_id=v_grn.tenant_id and pol.purchase_order_id=v_grn.purchase_order_id and pol.product_id=v_line.product_id and pol.unit_id=v_line.unit_id) then
      raise exception 'A goods receipt line does not match its purchase order line';
    end if;
    if v_line.accepted_quantity>0 then
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
    into v_all_received
    from public.purchase_order_lines
   where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;
  update public.purchase_orders
     set status=case when v_all_received then 'received' else 'part_received' end,updated_at=now()
   where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id and status in ('approved','part_received');
  update public.goods_receipts set status='posted',posted_at=now()
   where id=v_grn.id and tenant_id=v_grn.tenant_id;
  return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted');
end;
$$;
revoke all on function public.post_goods_receipt(uuid) from public,anon;
grant execute on function public.post_goods_receipt(uuid) to authenticated;
