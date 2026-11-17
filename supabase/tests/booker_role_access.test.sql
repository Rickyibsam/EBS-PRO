begin;
select plan(12);

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) values
('00000000-0000-0000-0000-000000000201','authenticated','authenticated','booker-one@example.test','',now(),now(),now(),
 '{"provider":"email","providers":["email"]}','{"full_name":"Booker One"}'),
('00000000-0000-0000-0000-000000000202','authenticated','authenticated','booker-two@example.test','',now(),now(),now(),
 '{"provider":"email","providers":["email"]}','{"full_name":"Booker Two"}');

insert into public.organizations(id,name,slug)
values
('00000000-0000-0000-0000-000000000101','Booker Test Tenant A','booker-test-tenant-a'),
('00000000-0000-0000-0000-000000000102','Booker Test Tenant B','booker-test-tenant-b');

insert into public.tenant_memberships(tenant_id,user_id,role,is_active)
values
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000201','order_booker',true),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000202','order_booker',true);

insert into public.branches(id,tenant_id,name,code,is_default,is_active)
values ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000101','Booker Test Branch','BT-BR-01',true,true);

insert into public.warehouses(id,tenant_id,branch_id,name,code,is_default,is_active)
values ('00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000301','Booker Test Warehouse','BT-WH-01',true,true);

insert into public.employees(id,tenant_id,user_id,branch_id,employee_code,full_name,employment_status)
values
('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000301','BT-EMP-01','Booker One','active'),
('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000301','BT-EMP-02','Booker Two','active');

insert into public.units_of_measure(id,tenant_id,name,symbol,unit_type,decimal_places)
values ('00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000101','Test Unit','TU','quantity',0);

insert into public.products(
  id,tenant_id,sku,name,brand,base_unit_id,cost_price,sale_price,sales_tax_rate,is_active,track_batch,track_expiry
) values
('00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000101','BT-SKU-01','Allowed Stock Product','TestBrand','00000000-0000-0000-0000-000000000601',25,50,0,true,false,false),
('00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000101','BT-SKU-02','Denied Product','TestBrand','00000000-0000-0000-0000-000000000601',30,60,0,true,false,false),
('00000000-0000-0000-0000-000000000703','00000000-0000-0000-0000-000000000101','BT-SKU-03','Unmatched Product','OtherBrand','00000000-0000-0000-0000-000000000601',35,70,0,true,false,false);

insert into public.product_units(tenant_id,product_id,unit_id,conversion_to_base,is_sales_unit)
select '00000000-0000-0000-0000-000000000101',p.id,'00000000-0000-0000-0000-000000000601',1,true
from public.products p
where p.tenant_id='00000000-0000-0000-0000-000000000101'
  and p.id in ('00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000703');

insert into public.parties(id,tenant_id,party_code,party_type,name,status)
values ('00000000-0000-0000-0000-000000000801','00000000-0000-0000-0000-000000000101','BT-CUST-01','customer','Assigned Test Customer','active');

insert into public.sales_routes(id,tenant_id,branch_id,route_code,name,is_active)
values ('00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000301','BT-ROUTE-01','Booker Test Route',true);

insert into public.route_assignments(tenant_id,route_id,employee_id,assigned_from)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000501',current_date);

insert into public.route_customers(tenant_id,route_id,customer_id,visit_order)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000901','00000000-0000-0000-0000-000000000801',1);

insert into public.price_lists(id,tenant_id,name,price_type,is_default,is_active,valid_from)
values ('00000000-0000-0000-0000-000000000a01','00000000-0000-0000-0000-000000000101','Booker VIP Price List','special',false,true,current_date);

insert into public.customer_price_lists(tenant_id,customer_id,price_list_id)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000801','00000000-0000-0000-0000-000000000a01');

insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
values ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000a01',
        '00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000601',55,1);

insert into public.stock_movements(
  tenant_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,created_by,notes
) values (
  '00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000701','purchase_receipt',10,0,25,
  '00000000-0000-0000-0000-000000000201','Booker security test stock'
);

-- Booker One has an allow-list plus an explicit deny; Booker Two has deny-only rules.
insert into public.booker_product_visibility(tenant_id,employee_id,product_id,is_allowed,require_stock)
values
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000701',true,true),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000702',false,false),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000702',false,false);

create temporary table booker_catalog_probe(user_key text not null,product_id uuid not null,price numeric) on commit drop;
create temporary table booker_rls_probe(user_key text not null,table_name text not null,rows_seen bigint not null) on commit drop;
grant insert,select on booker_catalog_probe to authenticated;
grant insert,select on booker_rls_probe to authenticated;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000201',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',true);

insert into booker_catalog_probe(user_key,product_id,price)
select 'booker_one',product_id,price
from public.get_booker_catalog('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000801');

select is((select count(*) from booker_catalog_probe where user_key='booker_one'),1::bigint,
  'allow-list booker receives only the permitted in-stock product');
select is((select product_id from booker_catalog_probe where user_key='booker_one'),
  '00000000-0000-0000-0000-000000000701'::uuid,'booker catalogue returns the explicitly allowed product');
select is((select price from booker_catalog_probe where user_key='booker_one'),55::numeric,
  'customer-specific price list takes precedence over the default list');
select is((select count(*) from booker_catalog_probe where user_key='booker_one' and product_id='00000000-0000-0000-0000-000000000702'),
  0::bigint,'explicit product deny rule overrides visibility');
select is((select count(*) from booker_catalog_probe where user_key='booker_one' and product_id='00000000-0000-0000-0000-000000000703'),
  0::bigint,'allow-list mode hides products without a matching allow rule');
select ok(position('cost_price' in lower(pg_get_function_result('public.get_booker_catalog(uuid,uuid)'::regprocedure)))=0,
  'restricted Booker catalogue result schema does not expose cost price');
throws_ok(
  $$select * from public.get_booker_catalog('00000000-0000-0000-0000-000000000102',null)$$,
  '42501','Order Booker authorization is required.','Booker cannot request another tenant catalogue'
);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000202',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',true);

insert into booker_catalog_probe(user_key,product_id,price)
select 'booker_two',product_id,price
from public.get_booker_catalog('00000000-0000-0000-0000-000000000101',null);

select is((select count(*) from booker_catalog_probe where user_key='booker_two' and product_id in (
  '00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000703'
)),2::bigint,'deny-only rules preserve unmatched catalogue visibility');
select is((select count(*) from booker_catalog_probe where user_key='booker_two' and product_id='00000000-0000-0000-0000-000000000702'),
  0::bigint,'deny-only rule hides only its matching product');

set local role authenticated;
insert into booker_rls_probe(user_key,table_name,rows_seen)
select 'booker_two','products',count(*) from public.products where tenant_id='00000000-0000-0000-0000-000000000101';
insert into booker_rls_probe(user_key,table_name,rows_seen)
select 'booker_two','product_prices',count(*) from public.product_prices where tenant_id='00000000-0000-0000-0000-000000000101';
insert into booker_rls_probe(user_key,table_name,rows_seen)
select 'booker_two','product_units',count(*) from public.product_units where tenant_id='00000000-0000-0000-0000-000000000101';
reset role;

select is((select rows_seen from booker_rls_probe where table_name='products'),0::bigint,
  'pure Booker cannot directly read product rows');
select is((select rows_seen from booker_rls_probe where table_name='product_prices'),0::bigint,
  'pure Booker cannot directly read product price rows');
select is((select rows_seen from booker_rls_probe where table_name='product_units'),0::bigint,
  'pure Booker cannot directly read product unit rows');

select * from finish();
rollback;
