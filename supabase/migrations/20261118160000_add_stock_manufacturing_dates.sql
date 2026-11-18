-- Preserve manufacturing dates alongside batch and expiry metadata.
-- Nullable for legacy rows; new tracked-lot intake continues to require batch and expiry.
alter table public.goods_receipt_lines
  add column if not exists manufactured_date date;

alter table public.stock_movements
  add column if not exists manufactured_date date;

alter table public.goods_receipt_lines
  drop constraint if exists goods_receipt_lines_manufactured_before_expiry_check;
alter table public.goods_receipt_lines
  add constraint goods_receipt_lines_manufactured_before_expiry_check
  check (manufactured_date is null or expiry_date is null or manufactured_date <= expiry_date);

alter table public.stock_movements
  drop constraint if exists stock_movements_manufactured_before_expiry_check;
alter table public.stock_movements
  add constraint stock_movements_manufactured_before_expiry_check
  check (manufactured_date is null or expiry_date is null or manufactured_date <= expiry_date);

comment on column public.goods_receipt_lines.manufactured_date is
  'Manufacturer-declared production date for the received batch; nullable for legacy records.';
comment on column public.stock_movements.manufactured_date is
  'Manufacturing date carried with the stock lot for traceability; nullable for legacy records.';
