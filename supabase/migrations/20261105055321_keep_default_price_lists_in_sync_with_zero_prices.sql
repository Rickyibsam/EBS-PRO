-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.sync_default_price_from_product()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
 if new.sale_price is distinct from old.sale_price then
  insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
  select pu.tenant_id,pl.id,pu.product_id,pu.unit_id,
         round(greatest(new.sale_price,0)*pu.conversion_to_base,4),1
  from public.product_units pu
  join public.price_lists pl on pl.tenant_id=pu.tenant_id and pl.is_default=true
    and (pl.valid_from is null or pl.valid_from<=current_date)
    and (pl.valid_to is null or pl.valid_to>=current_date)
  where pu.tenant_id=new.tenant_id and pu.product_id=new.id and pu.is_sales_unit=true
  on conflict(price_list_id,product_id,unit_id,min_quantity)
  do update set price=excluded.price;
 end if;
 return new;
end
$function$;
