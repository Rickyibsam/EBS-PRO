-- Skip existing backup rows before INSERT triggers run, avoiding false restore failures.
do $$
declare
 v_definition text;
 v_old_restore_decl text := 'v_table text;v_cols text;v_count integer;v_inserted integer:=0;v_pass integer:=0;v_progress integer;v_errors jsonb:=''{}''::jsonb;v_skipped jsonb;';
 v_new_restore_decl text := 'v_table text;v_cols text;v_count integer;v_inserted integer:=0;v_pass integer:=0;v_progress integer;v_errors jsonb:=''{}''::jsonb;v_skipped jsonb;v_key_constraint oid;v_key_match text;';
 v_old_cols text := $old$
   select string_agg(quote_ident(column_name),',' order by ordinal_position) into v_cols from information_schema.columns where table_schema='public' and table_name=v_table and is_generated='NEVER' and is_identity='NO';
   if v_cols is null then continue;end if;
$old$;
 v_new_cols text := $new$
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
$new$;
 v_old_insert text := $old$
    execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) as x where x.tenant_id=$2 on conflict do nothing',v_table,v_cols,v_cols,v_table) using p_backup->'tables'->v_table,p_tenant_id;
$old$;
 v_new_insert text := $new$
    execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) as src where src.tenant_id=$2 and not exists (select 1 from public.%I dst where %s) on conflict do nothing',v_table,v_cols,v_cols,v_table,v_table,v_key_match) using p_backup->'tables'->v_table,p_tenant_id;
$new$;
begin
 select pg_get_functiondef('private.restore_tenant_backup_internal(uuid,jsonb)'::regprocedure) into v_definition;
 if position(v_old_restore_decl in v_definition)=0 or position(v_old_cols in v_definition)=0 or position(v_old_insert in v_definition)=0 then
  raise exception 'Expected restore function blocks were not found; no function was changed.';
 end if;
 v_definition:=replace(v_definition,v_old_restore_decl,v_new_restore_decl);
 v_definition:=replace(v_definition,v_old_cols,v_new_cols);
 v_definition:=replace(v_definition,v_old_insert,v_new_insert);
 execute v_definition;
end $$;
