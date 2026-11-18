-- Carry the GRN line's manufacturer date onto the corresponding inbound stock lot.
create or replace function public.set_stock_movement_manufactured_date_from_grn()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_date date;
  v_distinct_dates integer;
begin
  if new.reference_type = 'goods_receipt'
     and new.reference_id is not null
     and new.manufactured_date is null then
    select min(grl.manufactured_date), count(distinct grl.manufactured_date)
      into v_date, v_distinct_dates
    from public.goods_receipt_lines grl
    where grl.tenant_id = new.tenant_id
      and grl.goods_receipt_id = new.reference_id
      and grl.product_id = new.product_id
      and grl.batch_number is not distinct from new.batch_number
      and grl.expiry_date is not distinct from new.expiry_date
      and grl.manufactured_date is not null;

    if v_distinct_dates > 1 then
      raise exception 'Matching GRN lines contain conflicting manufacturing dates for this stock lot.'
        using errcode = '23514';
    end if;
    if v_distinct_dates = 1 then
      new.manufactured_date := v_date;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stock_movement_copy_grn_manufactured_date on public.stock_movements;
create trigger trg_stock_movement_copy_grn_manufactured_date
before insert on public.stock_movements
for each row execute function public.set_stock_movement_manufactured_date_from_grn();

comment on function public.set_stock_movement_manufactured_date_from_grn() is
'Copies the matching GRN line manufacturing date onto its inbound stock movement; rejects ambiguous lot matches.';
