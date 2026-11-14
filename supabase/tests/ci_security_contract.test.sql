begin;

select plan(10);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='products'),
  'products has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='product_prices'),
  'product_prices has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='product_units'),
  'product_units has RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='products'
           and p.polname='products_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'products has restrictive Booker SELECT guard'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='product_prices'
           and p.polname='product_prices_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'product_prices has restrictive Booker SELECT guard'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='product_units'
           and p.polname='product_units_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'product_units has restrictive Booker SELECT guard'
);
select ok(
  has_function_privilege('authenticated','public.get_booker_catalog(uuid,uuid)','EXECUTE'),
  'authenticated can execute restricted Booker catalogue RPC'
);
select ok(
  not has_function_privilege('anon','public.get_booker_catalog(uuid,uuid)','EXECUTE'),
  'anonymous role cannot execute Booker catalogue RPC'
);
select ok(
  not has_function_privilege('authenticated','public.get_booker_stock_balances(uuid)','EXECUTE'),
  'authenticated cannot execute legacy tenant-wide stock RPC'
);
select ok(
  not has_function_privilege('authenticated','private.booker_product_allowed(uuid,uuid,uuid)','EXECUTE'),
  'authenticated cannot execute private visibility helper'
);

select * from finish();
rollback;
