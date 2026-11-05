-- Include tenant-scoped tables with composite primary keys in backup and restore.
-- This covers settings, pricing assignments, account mappings and document sequences.

create or replace function private.export_tenant_backup_internal(p_tenant_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth
as $$
declare v_table text;v_rows jsonb;v_tables jsonb:='{}'::jsonb;v_org jsonb;
begin
 if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin']) then raise exception 'Only company owners or administrators can export a company backup.' using errcode='42501';end if;
 select to_jsonb(o) into v_org from public.organizations o where o.id=p_tenant_id;
 for v_table in
  select t.table_name from information_schema.tables t
  where t.table_schema='public' and t.table_type='BASE TABLE'
   and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=t.table_name and c.column_name='tenant_id')
   and exists(select 1 from pg_constraint pc where pc.conrelid=to_regclass(format('public.%I',t.table_name)) and pc.contype in ('p','u'))
   and t.table_name<>'tenant_memberships'
   and not exists(select 1 from information_schema.columns s where s.table_schema='public' and s.table_name=t.table_name and (s.column_name ilike '%password%' or s.column_name ilike '%secret%' or s.column_name ilike '%token%' or s.column_name ilike '%api_key%' or s.column_name ilike '%private_key%' or s.column_name ilike '%access_key%'))
  order by t.table_name
 loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x where x.tenant_id=$1',v_table) into v_rows using p_tenant_id;
  v_tables:=jsonb_set(v_tables,array[v_table],coalesce(v_rows,'[]'::jsonb),true);
 end loop;
 return jsonb_build_object('format','EBS-PRO-TENANT-BACKUP-V1','tenant_id',p_tenant_id,'exported_at',now(),'organization',v_org,'tables',v_tables);
end;
$$;

create or replace function private.restore_tenant_backup_internal(p_tenant_id uuid,p_backup jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth
as $$
declare v_table text;v_cols text;v_count integer;v_inserted integer:=0;v_pass integer:=0;v_progress integer;v_errors jsonb:='{}'::jsonb;v_skipped jsonb;
begin
 if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin']) then raise exception 'Only company owners or administrators can restore a company backup.' using errcode='42501';end if;
 if jsonb_typeof(p_backup)<>'object' or p_backup->>'format'<>'EBS-PRO-TENANT-BACKUP-V1' or p_backup->>'tenant_id'<>p_tenant_id::text or jsonb_typeof(p_backup->'tables')<>'object' then raise exception 'Backup format or company ID is invalid. Restore is allowed only into the same company.';end if;
 perform set_config('app.ebs_backup_restore','on',true);
 for v_pass in 1..10 loop
  v_progress:=0;
  for v_table in
   select key from jsonb_each(p_backup->'tables') order by
    case key when 'chart_of_accounts' then 1 when 'branches' then 2 when 'departments' then 3 when 'designations' then 4 when 'warehouses' then 5 when 'parties' then 6 when 'products' then 7 when 'sales_routes' then 8 when 'employees' then 9 when 'sales_orders' then 10 when 'purchase_orders' then 11 when 'journal_entries' then 12 when 'goods_receipts' then 13 when 'sales_invoices' then 14 when 'deliveries' then 15 else 100 end,key
  loop
   if jsonb_typeof(p_backup->'tables'->v_table)<>'array' or jsonb_array_length(p_backup->'tables'->v_table)=0 then continue;end if;
   if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=v_table and table_type='BASE TABLE')
      or not exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_table and column_name='tenant_id')
      or not exists(select 1 from pg_constraint pc where pc.conrelid=to_regclass(format('public.%I',v_table)) and pc.contype in ('p','u'))
      or v_table='tenant_memberships'
      or exists(select 1 from information_schema.columns s where s.table_schema='public' and s.table_name=v_table and (s.column_name ilike '%password%' or s.column_name ilike '%secret%' or s.column_name ilike '%token%' or s.column_name ilike '%api_key%' or s.column_name ilike '%private_key%' or s.column_name ilike '%access_key')) then
    v_errors:=jsonb_set(v_errors,array[v_table],to_jsonb('Table is not an eligible tenant data table.'::text),true);continue;
   end if;
   if exists(select 1 from jsonb_array_elements(p_backup->'tables'->v_table) as j(value) where coalesce(j.value->>'tenant_id','')<>p_tenant_id::text) then raise exception 'Backup contains rows belonging to another company in table %.',v_table;end if;
   select string_agg(quote_ident(column_name),',' order by ordinal_position) into v_cols from information_schema.columns where table_schema='public' and table_name=v_table and is_generated='NEVER' and is_identity='NO';
   if v_cols is null then continue;end if;
   begin
    execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) as x where x.tenant_id=$2 on conflict do nothing',v_table,v_cols,v_cols,v_table) using p_backup->'tables'->v_table,p_tenant_id;
    get diagnostics v_count=row_count;v_inserted:=v_inserted+v_count;v_progress:=v_progress+v_count;v_errors:=v_errors-v_table;
   exception when others then v_errors:=jsonb_set(v_errors,array[v_table],to_jsonb(left(sqlerrm,500)),true);
   end;
  end loop;
  exit when v_progress=0;
 end loop;
 select coalesce(jsonb_agg(key),'[]'::jsonb) into v_skipped from jsonb_object_keys(v_errors) as x(key);
 return jsonb_build_object('success',true,'imported_rows',v_inserted,'passes',v_pass,'skipped_tables',v_skipped,'errors',v_errors,'mode','additive_only_no_overwrite_no_delete');
end;
$$;
