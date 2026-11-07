-- Keep a goods receipt in the same branch as its source purchase order.
-- Existing historical rows are not rewritten; the guard applies to future inserts/updates.

create or replace function private.guard_goods_receipt_purchase_order_branch()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $function$
declare
  v_purchase_order_branch uuid;
  v_receipt_warehouse_branch uuid;
begin
  if new.purchase_order_id is null then
    return new;
  end if;

  select coalesce(po.branch_id, po_wh.branch_id)
    into v_purchase_order_branch
  from public.purchase_orders po
  left join public.warehouses po_wh
    on po_wh.id = po.warehouse_id
   and po_wh.tenant_id = po.tenant_id
  where po.id = new.purchase_order_id
    and po.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Purchase order must belong to the same company.'
      using errcode = '23503';
  end if;

  select w.branch_id
    into v_receipt_warehouse_branch
  from public.warehouses w
  where w.id = new.warehouse_id
    and w.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Goods receipt warehouse must belong to the same company.'
      using errcode = '23503';
  end if;

  if v_purchase_order_branch is not null
     and v_receipt_warehouse_branch is distinct from v_purchase_order_branch then
    raise exception 'Goods receipt warehouse must belong to the purchase order branch.'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.guard_goods_receipt_purchase_order_branch()
  from public, anon, authenticated;

drop trigger if exists goods_receipts_purchase_order_branch_guard
  on public.goods_receipts;

create trigger goods_receipts_purchase_order_branch_guard
before insert or update of purchase_order_id, warehouse_id, tenant_id
on public.goods_receipts
for each row
execute function private.guard_goods_receipt_purchase_order_branch();
