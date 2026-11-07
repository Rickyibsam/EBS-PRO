-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.enforce_stock_batch_expiry_rules()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_track_batch boolean;
  v_track_expiry boolean;
  v_received_date date;
begin
  select p.track_batch, p.track_expiry
    into v_track_batch, v_track_expiry
  from public.products p
  where p.id = new.product_id
    and p.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Product does not belong to this tenant.' using errcode = '23503';
  end if;

  if v_track_batch and nullif(btrim(new.batch_number), '') is null then
    raise exception 'Batch number is required for this batch-tracked product.' using errcode = '23514';
  end if;

  if v_track_expiry and new.expiry_date is null then
    raise exception 'Expiry date is required for this expiry-tracked product.' using errcode = '23514';
  end if;

  if new.expiry_date is not null then
    if tg_table_name = 'goods_receipt_lines' then
      select gr.received_date into v_received_date
      from public.goods_receipts gr
      where gr.id = new.goods_receipt_id
        and gr.tenant_id = new.tenant_id;

      if v_received_date is null then
        raise exception 'Goods receipt was not found for this tenant.' using errcode = '23503';
      end if;

      if new.expiry_date < greatest(v_received_date, current_date) then
        raise exception 'Expired stock cannot be received into available inventory.' using errcode = '23514';
      end if;
    elsif tg_table_name = 'stock_movements' and coalesce(new.quantity_in, 0) > 0 then
      if new.expiry_date < current_date then
        raise exception 'Expired stock cannot be added to available inventory.' using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_goods_receipt_line_batch_expiry_guard on public.goods_receipt_lines;
create trigger trg_goods_receipt_line_batch_expiry_guard
before insert or update of product_id, tenant_id, goods_receipt_id, batch_number, expiry_date
on public.goods_receipt_lines
for each row execute function public.enforce_stock_batch_expiry_rules();

drop trigger if exists trg_stock_movement_batch_expiry_guard on public.stock_movements;
create trigger trg_stock_movement_batch_expiry_guard
before insert or update of product_id, tenant_id, batch_number, expiry_date, quantity_in
on public.stock_movements
for each row execute function public.enforce_stock_batch_expiry_rules();

comment on function public.enforce_stock_batch_expiry_rules() is
'Validates batch and expiry metadata on goods receipt lines and inbound stock movements; does not alter existing stock data.';
