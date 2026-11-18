-- Customer-wise, read-only data export. This complements (does not replace) the
-- existing company-wide additive backup. It never restores or mutates business data.

create or replace function public.export_customer_backup(p_tenant_id uuid, p_customer_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_party jsonb;
  v_table record;
  v_rows jsonb;
  v_tables jsonb := '{}'::jsonb;
  v_fk_columns text;
begin
  if auth.uid() is null
     or not public.has_tenant_role(p_tenant_id, array['owner','admin']) then
    raise exception 'Only company owners or administrators can export customer data.'
      using errcode = '42501';
  end if;

  select to_jsonb(p)
    into v_party
    from public.parties p
   where p.id = p_customer_id
     and p.tenant_id = p_tenant_id
     and p.party_type in ('customer','both');

  if v_party is null then
    raise exception 'Customer was not found in the selected company.'
      using errcode = 'P0002';
  end if;

  for v_table in
    select distinct tc.table_name
      from information_schema.table_constraints tc
      join information_schema.constraint_column_usage ccu
        on ccu.constraint_catalog = tc.constraint_catalog
       and ccu.constraint_schema = tc.constraint_schema
       and ccu.constraint_name = tc.constraint_name
      join information_schema.columns id_col
        on id_col.table_schema = tc.table_schema
       and id_col.table_name = tc.table_name
       and id_col.column_name = 'id'
      join information_schema.columns tenant_col
        on tenant_col.table_schema = tc.table_schema
       and tenant_col.table_name = tc.table_name
       and tenant_col.column_name = 'tenant_id'
     where tc.constraint_type = 'FOREIGN KEY'
       and tc.table_schema = 'public'
       and ccu.table_schema = 'public'
       and ccu.table_name = 'parties'
       and ccu.column_name = 'id'
       and tc.table_name <> 'parties'
       and not exists (
         select 1 from information_schema.columns secret_col
          where secret_col.table_schema = 'public'
            and secret_col.table_name = tc.table_name
            and (secret_col.column_name ilike '%password%'
              or secret_col.column_name ilike '%secret%'
              or secret_col.column_name ilike '%token%'
              or secret_col.column_name ilike '%api_key%'
              or secret_col.column_name ilike '%private_key%'
              or secret_col.column_name ilike '%access_key%')
       )
     order by tc.table_name
  loop
    select string_agg(format('(%I = $1)', kcu.column_name), ' OR ')
      into v_fk_columns
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on kcu.constraint_catalog = tc.constraint_catalog
       and kcu.constraint_schema = tc.constraint_schema
       and kcu.constraint_name = tc.constraint_name
     where tc.constraint_type = 'FOREIGN KEY'
       and tc.table_schema = 'public'
       and tc.table_name = v_table.table_name
       and exists (
         select 1 from information_schema.constraint_column_usage ccu
          where ccu.constraint_catalog = tc.constraint_catalog
            and ccu.constraint_schema = tc.constraint_schema
            and ccu.constraint_name = tc.constraint_name
            and ccu.table_schema = 'public'
            and ccu.table_name = 'parties'
            and ccu.column_name = 'id'
       );

    if v_fk_columns is null then
      continue;
    end if;

    execute format(
      'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb)
         from public.%I x
        where x.tenant_id = $2 and (%s)',
      v_table.table_name, v_fk_columns
    ) into v_rows using p_customer_id, p_tenant_id;

    v_tables := jsonb_set(v_tables, array[v_table.table_name], coalesce(v_rows, '[]'::jsonb), true);
  end loop;

  return jsonb_build_object(
    'format', 'EBS-PRO-CUSTOMER-BACKUP-V1',
    'tenant_id', p_tenant_id,
    'customer_id', p_customer_id,
    'exported_at', now(),
    'customer', v_party,
    'related_tables', v_tables,
    'mode', 'read_only_export_no_restore_no_mutation'
  );
end;
$$;

revoke all on function public.export_customer_backup(uuid, uuid) from public, anon;
grant execute on function public.export_customer_backup(uuid, uuid) to authenticated;

comment on function public.export_customer_backup(uuid, uuid) is
'Owner/admin-only read-only export of one customer and tenant-scoped rows directly referencing that customer. Does not include passwords, secrets, tenant memberships, or unrelated customer data.';
