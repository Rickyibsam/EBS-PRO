-- Extend tenant-scoped automatic identifiers to the remaining ERP master records.
alter table public.master_code_sequences
  drop constraint if exists master_code_sequences_entity_type_check;
alter table public.master_code_sequences
  add constraint master_code_sequences_entity_type_check
  check (entity_type in ('product','customer','supplier','party','branch','warehouse','department','designation','employee','asset','route'));

create or replace function public.generate_master_entry_code()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_entity text;
  v_prefix text;
  v_code_column text;
  v_existing_code text;
  v_number bigint;
  v_new_code text;
begin
  case tg_table_name
    when 'products' then v_entity:='product';v_prefix:='SKU-';v_code_column:='sku';
    when 'parties' then
      v_entity:=case new.party_type when 'customer' then 'customer' when 'supplier' then 'supplier' else 'party' end;
      v_prefix:=case v_entity when 'customer' then 'CUS-' when 'supplier' then 'SUP-' else 'PTY-' end;
      v_code_column:='party_code';
    when 'branches' then v_entity:='branch';v_prefix:='BR-';v_code_column:='code';
    when 'warehouses' then v_entity:='warehouse';v_prefix:='WH-';v_code_column:='code';
    when 'departments' then v_entity:='department';v_prefix:='DEP-';v_code_column:='code';
    when 'designations' then v_entity:='designation';v_prefix:='DSG-';v_code_column:='code';
    when 'employees' then v_entity:='employee';v_prefix:='EMP-';v_code_column:='employee_code';
    when 'fixed_assets' then v_entity:='asset';v_prefix:='AST-';v_code_column:='asset_code';
    when 'sales_routes' then v_entity:='route';v_prefix:='RTE-';v_code_column:='route_code';
    else raise exception 'Unsupported master-code table: %',tg_table_name;
  end case;

  v_existing_code:=nullif(btrim(to_jsonb(new)->>v_code_column),'');
  if v_existing_code is not null then
    return new;
  end if;

  insert into public.master_code_sequences(tenant_id, entity_type, next_number)
  values (new.tenant_id, v_entity, 2)
  on conflict (tenant_id, entity_type)
  do update set next_number = public.master_code_sequences.next_number + 1
  returning next_number - 1 into v_number;

  v_new_code:=v_prefix||lpad(v_number::text,6,'0');
  new:=jsonb_populate_record(new,jsonb_build_object(v_code_column,v_new_code));
  return new;
end;
$$;

drop trigger if exists branches_generate_master_code on public.branches;
create trigger branches_generate_master_code before insert on public.branches
for each row execute function public.generate_master_entry_code();
drop trigger if exists warehouses_generate_master_code on public.warehouses;
create trigger warehouses_generate_master_code before insert on public.warehouses
for each row execute function public.generate_master_entry_code();
drop trigger if exists departments_generate_master_code on public.departments;
create trigger departments_generate_master_code before insert on public.departments
for each row execute function public.generate_master_entry_code();
drop trigger if exists designations_generate_master_code on public.designations;
create trigger designations_generate_master_code before insert on public.designations
for each row execute function public.generate_master_entry_code();
drop trigger if exists employees_generate_master_code on public.employees;
create trigger employees_generate_master_code before insert on public.employees
for each row execute function public.generate_master_entry_code();
drop trigger if exists fixed_assets_generate_master_code on public.fixed_assets;
create trigger fixed_assets_generate_master_code before insert on public.fixed_assets
for each row execute function public.generate_master_entry_code();
drop trigger if exists sales_routes_generate_master_code on public.sales_routes;
create trigger sales_routes_generate_master_code before insert on public.sales_routes
for each row execute function public.generate_master_entry_code();
