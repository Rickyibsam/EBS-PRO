-- Reject inactive warehouses before recording a van load/unload transfer.
do $$
declare d text;
begin
 select pg_get_functiondef('public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text)'::regprocedure) into d;
 d:=replace(d,
  'if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id) then',
  'if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then');
 execute d;
end;
$$;
