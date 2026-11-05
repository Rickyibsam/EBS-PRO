-- Validate that an assigned van transfer employee is active and belongs to the same tenant.
do $$
declare d text;
begin
 select pg_get_functiondef('public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text)'::regprocedure) into d;
 d:=replace(d,
  'select * into v_product from public.products where id=p_product_id and tenant_id=p_tenant_id;',
  'if p_employee_id is not null and not exists(select 1 from public.employees where id=p_employee_id and tenant_id=p_tenant_id and employment_status=''active'') then raise exception ''Employee does not belong to this tenant or is inactive.''; end if; select * into v_product from public.products where id=p_product_id and tenant_id=p_tenant_id;');
 execute d;
end;
$$;
