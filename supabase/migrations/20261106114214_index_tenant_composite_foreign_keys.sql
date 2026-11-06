-- Add child-side indexes for tenant-scoped composite foreign keys.
-- The indexes are created only when no valid non-partial index already covers
-- the FK columns in their declared order.

do $tenant_fk_indexes$
declare r record; cols text; idx text;
begin
 for r in
  select c.oid,c.conrelid,c.conkey,cn.nspname,ct.relname,c.conname
  from pg_constraint c
  join pg_class ct on ct.oid=c.conrelid join pg_namespace cn on cn.oid=ct.relnamespace
  join pg_class pt on pt.oid=c.confrelid join pg_namespace pn on pn.oid=pt.relnamespace
  join pg_attribute ca on ca.attrelid=c.conrelid and ca.attname='tenant_id' and not ca.attisdropped
  join pg_attribute pa on pa.attrelid=c.confrelid and pa.attname='tenant_id' and not pa.attisdropped
  where c.contype='f' and cn.nspname='public' and pn.nspname='public'
    and ca.attnum=any(c.conkey) and pa.attnum=any(c.confkey)
    and not exists (
      select 1 from pg_index i
      where i.indrelid=c.conrelid and i.indisvalid and i.indpred is null and i.indexprs is null
        and i.indnkeyatts>=cardinality(c.conkey)
        and (select array_agg(i.indkey[s]::smallint order by s)
             from generate_series(0,cardinality(c.conkey)-1) s)=c.conkey
    )
  order by cn.nspname,ct.relname,c.conname
 loop
  select string_agg(format('%I',a.attname),', ' order by k.ord) into cols
  from unnest(r.conkey) with ordinality k(attnum,ord)
  join pg_attribute a on a.attrelid=r.conrelid and a.attnum=k.attnum;
  idx:='tenant_fk_idx_'||substr(md5(r.nspname||'.'||r.relname||':'||cols),1,20);
  execute format('create index if not exists %I on %I.%I (%s)',idx,r.nspname,r.relname,cols);
 end loop;
end
$tenant_fk_indexes$;
