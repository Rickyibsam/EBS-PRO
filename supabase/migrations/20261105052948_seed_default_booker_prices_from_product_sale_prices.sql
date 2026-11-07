-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.ensure_tenant_default_price_list()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if not exists(select 1 from public.price_lists where tenant_id=new.id and is_default=true) then
  insert into public.price_lists(tenant_id,name,price_type,is_default,valid_from)
  values(new.id,'Default Retail','retail',true,current_date)
  on conflict(tenant_id,name) do update set is_default=true;
 end if;
 return new;
end $$;
revoke all on function public.ensure_tenant_default_price_list() from public;
drop trigger if exists organizations_default_price_list on public.organizations;
create trigger organizations_default_price_list after insert on public.organizations for each row execute function public.ensure_tenant_default_price_list();

insert into public.price_lists(tenant_id,name,price_type,is_default,valid_from)
select o.id,'Default Retail','retail',true,current_date from public.organizations o
where not exists(select 1 from public.price_lists p where p.tenant_id=o.id and p.is_default=true)
on conflict(tenant_id,name) do nothing;

create or replace function public.sync_default_price_from_product_unit()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_price numeric;v_list uuid;
begin
 if new.is_sales_unit is not true then return new;end if;
 select p.sale_price*new.conversion_to_base into v_price from public.products p where p.id=new.product_id and p.tenant_id=new.tenant_id and p.is_active;
 if coalesce(v_price,0)<=0 then return new;end if;
 select id into v_list from public.price_lists where tenant_id=new.tenant_id and is_default=true and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date) order by created_at desc limit 1;
 if v_list is not null then
  insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
  values(new.tenant_id,v_list,new.product_id,new.unit_id,v_price,1)
  on conflict(price_list_id,product_id,unit_id,min_quantity) do update set price=excluded.price;
 end if;
 return new;
end $$;
revoke all on function public.sync_default_price_from_product_unit() from public;
drop trigger if exists product_units_sync_default_price on public.product_units;
create trigger product_units_sync_default_price after insert or update of conversion_to_base,is_sales_unit on public.product_units for each row execute function public.sync_default_price_from_product_unit();

create or replace function public.sync_default_price_from_product()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if new.sale_price is distinct from old.sale_price then
  insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
  select pu.tenant_id,pl.id,pu.product_id,pu.unit_id,new.sale_price*pu.conversion_to_base,1
  from public.product_units pu join public.price_lists pl on pl.tenant_id=pu.tenant_id and pl.is_default=true
  where pu.tenant_id=new.tenant_id and pu.product_id=new.id and pu.is_sales_unit=true and new.sale_price>0
  on conflict(price_list_id,product_id,unit_id,min_quantity) do update set price=excluded.price;
 end if;
 return new;
end $$;
revoke all on function public.sync_default_price_from_product() from public;
drop trigger if exists products_sync_default_price on public.products;
create trigger products_sync_default_price after update of sale_price on public.products for each row execute function public.sync_default_price_from_product();

insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
select pu.tenant_id,pl.id,pu.product_id,pu.unit_id,p.sale_price*pu.conversion_to_base,1
from public.product_units pu
join public.products p on p.id=pu.product_id and p.tenant_id=pu.tenant_id
join public.price_lists pl on pl.tenant_id=pu.tenant_id and pl.is_default=true
where pu.is_sales_unit=true and p.is_active=true and p.sale_price>0
on conflict(price_list_id,product_id,unit_id,min_quantity) do nothing;
