-- New branches receive their own auto-generated warehouse code.
-- Keep the existing default warehouse codes untouched.
create or replace function public.bootstrap_tenant_warehouse()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.warehouses(tenant_id,branch_id,name,code,is_default)
  values(new.tenant_id,new.id,'Main Warehouse','',true);
  return new;
end;
$$;
revoke all on function public.bootstrap_tenant_warehouse() from public, anon, authenticated;
