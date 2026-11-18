-- Expand customer exports through tenant-scoped FK dependencies (orders -> lines,
-- invoices -> lines, deliveries -> lines, GRNs -> receipt lines, etc.).
-- Read-only, invoker-security, bounded traversal; no writes or restore behavior.

create or replace function public.export_customer_backup(p_tenant_id uuid, p_customer_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
  v_party jsonb;
  v_edge record;
  v_parent_rows jsonb;
  v_rows jsonb;
  v_existing jsonb;
  v_merged jsonb;
  v_tables jsonb := '{}'::jsonb;
  v_frontier text[] := array['parties']::text[];
  v_next text[];
  v_seen text[] := array['parties']::text[];
  v_depth integer;
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

  -- Traverse at most four FK levels. Each selected row must belong to the same
  -- tenant and expose a stable single-column "id" key. Tables containing
  -- credential/secret-like columns are excluded as a whole.
  for v_depth in 1..4 loop
    v_next := array[]::text[];

    for v_edge in
      select distinct tc.table_name as child_table,
             kcu.column_name as child_column,
             ccu.table_name as parent_table
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on kcu.constraint_catalog = tc.constraint_catalog
         and kcu.constraint_schema = tc.constraint_schema
         and kcu.constraint_name = tc.constraint_name
        join information_schema.constraint_column_usage ccu
          on ccu.constraint_catalog = tc.constraint_catalog
         and ccu.constraint_schema = tc.constraint_schema
         and ccu.constraint_name = tc.constraint_name
       where tc.constraint_type = 'FOREIGN KEY'
         and tc.table_schema = 'public'
         and ccu.table_schema = 'public'
         and ccu.table_name = any(v_frontier)
         and ccu.column_name = 'id'
         and not (tc.table_name = any(v_seen))
         and exists (
           select 1 from information_schema.columns c
            where c.table_schema='public' and c.table_name=tc.table_name and c.column_name='id'
         )
         and exists (
           select 1 from information_schema.columns c
            where c.table_schema='public' and c.table_name=tc.table_name and c.column_name='tenant_id'
         )
         and not exists (
           select 1 from information_schema.columns secret_col
            where secret_col.table_schema='public'
              and secret_col.table_name=tc.table_name
              and (secret_col.column_name ilike '%password%'
                or secret_col.column_name ilike '%secret%'
                or secret_col.column_name ilike '%token%'
                or secret_col.column_name ilike '%api_key%'
                or secret_col.column_name ilike '%private_key%'
                or secret_col.column_name ilike '%access_key%')
         )
       order by tc.table_name, kcu.column_name
    loop
      if v_edge.parent_table = 'parties' then
        v_parent_rows := jsonb_build_array(v_party);
      else
        v_parent_rows := coalesce(v_tables->v_edge.parent_table, '[]'::jsonb);
      end if;

      if jsonb_typeof(v_parent_rows) is distinct from 'array'
         or jsonb_array_length(v_parent_rows) = 0 then
        continue;
      end if;

      execute format(
        'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb)
           from public.%I x
          where x.tenant_id = $1
            and x.%I::text in (
              select parent_row->>''id''
                from jsonb_array_elements($2) as parent_row
               where parent_row ? ''id''
            )',
        v_edge.child_table,
        v_edge.child_column
      )
      into v_rows
      using p_tenant_id, v_parent_rows;

      if jsonb_array_length(coalesce(v_rows, '[]'::jsonb)) = 0 then
        continue;
      end if;

      v_existing := coalesce(v_tables->v_edge.child_table, '[]'::jsonb);
      select coalesce(jsonb_agg(value), '[]'::jsonb)
        into v_merged
        from (
          select distinct value
            from jsonb_array_elements(v_existing || v_rows)
        ) deduplicated;

      v_tables := jsonb_set(
        v_tables,
        array[v_edge.child_table],
        coalesce(v_merged, '[]'::jsonb),
        true
      );

      if not (v_edge.child_table = any(v_next)) then
        v_next := array_append(v_next, v_edge.child_table);
      end if;
    end loop;

    exit when coalesce(array_length(v_next, 1), 0) = 0;
    v_seen := v_seen || v_next;
    v_frontier := v_next;
  end loop;

  return jsonb_build_object(
    'format', 'EBS-PRO-CUSTOMER-BACKUP-V1',
    'tenant_id', p_tenant_id,
    'customer_id', p_customer_id,
    'exported_at', now(),
    'customer', v_party,
    'related_tables', v_tables,
    'dependency_depth', 4,
    'mode', 'read_only_export_no_restore_no_mutation'
  );
end;
$$;

revoke all on function public.export_customer_backup(uuid, uuid) from public, anon;
grant execute on function public.export_customer_backup(uuid, uuid) to authenticated;

comment on function public.export_customer_backup(uuid, uuid) is
'Owner/admin-only read-only export of one customer and tenant-scoped FK-dependent business rows up to four levels deep. Excludes tables with credential/secret-like columns, tenant memberships and unrelated tenant data. Not a restorable company backup.';
