CREATE OR REPLACE FUNCTION private.restore_tenant_backup_internal(p_tenant_id uuid, p_backup jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare v_table text;v_cols text;v_count integer;v_inserted integer:=0;v_pass integer:=0;v_progress integer;v_errors jsonb:='{}'::jsonb;v_skipped jsonb;v_key_constraint oid;v_key_match text;
begin
 if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin']) then raise exception 'Only company owners or administrators can restore a company backup.' using errcode='42501';end if;
 if jsonb_typeof(p_backup)<>'object' or p_backup->>'format'<>'EBS-PRO-TENANT-BACKUP-V1' or p_backup->>'tenant_id'<>p_tenant_id::text or jsonb_typeof(p_backup->'tables')<>'object' then raise exception 'Backup format or company ID is invalid. Restore is allowed only into the same company.';end if;
 perform set_config('app.ebs_backup_restore','on',true);
 for v_pass in 1..100 loop
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
   select c.oid into v_key_constraint
   from pg_constraint c
   where c.conrelid=to_regclass(format('public.%I',v_table)) and c.contype in ('p','u')
   order by case c.contype when 'p' then 0 else 1 end,array_length(c.conkey,1),c.oid
   limit 1;
   if v_key_constraint is null then
    v_errors:=jsonb_set(v_errors,array[v_table],to_jsonb('No stable primary or unique key was found.'::text),true);
    continue;
   end if;
   select string_agg(format('dst.%I IS NOT DISTINCT FROM src.%I',a.attname,a.attname),' AND ' order by k.ord)
   into v_key_match
   from pg_constraint c
   cross join lateral unnest(c.conkey) with ordinality as k(attnum,ord)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
   where c.oid=v_key_constraint;
   if v_key_match is null then
    v_errors:=jsonb_set(v_errors,array[v_table],to_jsonb('Could not build the primary/unique key match.'::text),true);
    continue;
   end if;
   begin
    execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) as src where src.tenant_id=$2 and not exists (select 1 from public.%I dst where %s) on conflict do nothing',v_table,v_cols,v_cols,v_table,v_table,v_key_match) using p_backup->'tables'->v_table,p_tenant_id;
    get diagnostics v_count=row_count;v_inserted:=v_inserted+v_count;v_progress:=v_progress+v_count;v_errors:=v_errors-v_table;
   exception when others then v_errors:=jsonb_set(v_errors,array[v_table],to_jsonb(left(sqlerrm,500)),true);
   end;
  end loop;
  exit when v_progress=0;
 end loop;
 select coalesce(jsonb_agg(key),'[]'::jsonb) into v_skipped from jsonb_object_keys(v_errors) as x(key);
 return jsonb_build_object(
    'success',(select count(*) from jsonb_object_keys(v_errors))=0 and not (v_pass=100 and v_progress>0),
    'complete',(select count(*) from jsonb_object_keys(v_errors))=0 and not (v_pass=100 and v_progress>0),
    'dependency_pass_limit_reached',v_pass=100 and v_progress>0,
    'imported_rows',v_inserted,'passes',v_pass,'skipped_tables',v_skipped,'errors',v_errors,
    'mode','additive_only_no_overwrite_no_delete'
  );
end;
$function$
