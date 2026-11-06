-- Enforce tenant ownership on every foreign key between tenant-scoped tables.
-- Existing cross-tenant links are audited before this migration; the migration validates
-- each new composite FK before removing its former single-column FK.
-- No business rows are rewritten or deleted.

do $tenant_fk_hardening$
declare
  r record;
  child_columns text;
  parent_columns text;
  set_null_columns text;
  index_name text;
  new_constraint_name text;
  delete_clause text;
  update_clause text;
  index_sql text;
  fk_sql text;
begin
  for r in
    select c.oid,c.conname,c.conrelid,c.confrelid,c.conkey,c.confkey,
           c.confdeltype,c.confupdtype,
           cn.nspname child_schema,ct.relname child_name,
           pn.nspname parent_schema,pt.relname parent_name,
           ca.attnum child_tenant_att,pa.attnum parent_tenant_att
    from pg_constraint c
    join pg_class ct on ct.oid=c.conrelid join pg_namespace cn on cn.oid=ct.relnamespace
    join pg_class pt on pt.oid=c.confrelid join pg_namespace pn on pn.oid=pt.relnamespace
    join pg_attribute ca on ca.attrelid=c.conrelid and ca.attname='tenant_id' and not ca.attisdropped
    join pg_attribute pa on pa.attrelid=c.confrelid and pa.attname='tenant_id' and not pa.attisdropped
    where c.contype='f' and cn.nspname='public' and pn.nspname='public'
      and not (ca.attnum=any(c.conkey) and pa.attnum=any(c.confkey))
    order by cn.nspname,ct.relname,c.conname
  loop
    select string_agg(format('%I',a.attname),', ' order by k.ord)
      into child_columns
    from unnest(r.conkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=r.conrelid and a.attnum=k.attnum;
    select string_agg(format('%I',a.attname),', ' order by k.ord)
      into parent_columns
    from unnest(r.confkey) with ordinality k(attnum,ord)
    join pg_attribute a on a.attrelid=r.confrelid and a.attnum=k.attnum;

    child_columns:=format('%I', 'tenant_id')||', '||child_columns;
    parent_columns:=format('%I', 'tenant_id')||', '||parent_columns;
    index_name:='tenant_fk_uq_'||substr(md5(r.parent_schema||'.'||r.parent_name||':'||parent_columns),1,20);
    new_constraint_name:=left(r.conname,32)||'_tenant_'||substr(md5(r.conname),1,8);

    index_sql:=format('create unique index if not exists %I on %I.%I (%s)',
      index_name,r.parent_schema,r.parent_name,parent_columns);
    execute index_sql;

    if r.confdeltype='c' then
      delete_clause:=' on delete cascade';
    elsif r.confdeltype='r' then
      delete_clause:=' on delete restrict';
    elsif r.confdeltype='n' then
      select string_agg(format('%I',a.attname),', ' order by k.ord)
        into set_null_columns
      from unnest(r.conkey) with ordinality k(attnum,ord)
      join pg_attribute a on a.attrelid=r.conrelid and a.attnum=k.attnum;
      delete_clause:=format(' on delete set null (%s)',set_null_columns);
    elsif r.confdeltype='d' then
      raise exception 'SET DEFAULT FK action needs manual tenant-safe handling: %.%',r.child_name,r.conname;
    else
      delete_clause:=' on delete no action';
    end if;

    if r.confupdtype='c' then
      update_clause:=' on update cascade';
    elsif r.confupdtype='r' then
      update_clause:=' on update restrict';
    elsif r.confupdtype='n' then
      raise exception 'ON UPDATE SET NULL FK action needs manual tenant-safe handling: %.%',r.child_name,r.conname;
    elsif r.confupdtype='d' then
      raise exception 'ON UPDATE SET DEFAULT FK action needs manual tenant-safe handling: %.%',r.child_name,r.conname;
    else
      update_clause:=' on update no action';
    end if;

    fk_sql:=format(
      'alter table %I.%I add constraint %I foreign key (%s) references %I.%I (%s)%s%s not valid',
      r.child_schema,r.child_name,new_constraint_name,child_columns,
      r.parent_schema,r.parent_name,parent_columns,update_clause,delete_clause);
    execute fk_sql;
    execute format('alter table %I.%I validate constraint %I',
      r.child_schema,r.child_name,new_constraint_name);
    execute format('alter table %I.%I drop constraint %I',
      r.child_schema,r.child_name,r.conname);
  end loop;
end
$tenant_fk_hardening$;

do $verify$
declare v_remaining integer;
begin
  select count(*) into v_remaining
  from pg_constraint c
  join pg_class ct on ct.oid=c.conrelid join pg_namespace cn on cn.oid=ct.relnamespace
  join pg_class pt on pt.oid=c.confrelid join pg_namespace pn on pn.oid=pt.relnamespace
  join pg_attribute ca on ca.attrelid=c.conrelid and ca.attname='tenant_id' and not ca.attisdropped
  join pg_attribute pa on pa.attrelid=c.confrelid and pa.attname='tenant_id' and not pa.attisdropped
  where c.contype='f' and cn.nspname='public' and pn.nspname='public'
    and not (ca.attnum=any(c.conkey) and pa.attnum=any(c.confkey));
  if v_remaining<>0 then
    raise exception 'Tenant FK hardening incomplete: % relationships remain',v_remaining;
  end if;
end
$verify$;
