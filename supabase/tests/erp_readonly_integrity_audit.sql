-- EBS PRO read-only integrity audit.
-- Safe to run in Supabase SQL Editor: only creates a transaction-scoped TEMP table.
-- It does not insert, update, delete, or alter any business records or schema objects.

create temporary table if not exists _ebs_integrity_findings (
  check_key text primary key,
  severity text not null,
  finding_count bigint not null,
  details text not null
) on commit drop;

truncate table _ebs_integrity_findings;

insert into _ebs_integrity_findings
select 'tables_without_rls','critical',count(*)::bigint,
       'Public base tables without row-level security'
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;

insert into _ebs_integrity_findings
select 'unvalidated_constraints','high',count(*)::bigint,
       'Unvalidated foreign-key or check constraints'
from pg_constraint
where connamespace='public'::regnamespace and contype in ('f','c') and not convalidated;

insert into _ebs_integrity_findings
select 'posted_journal_unbalanced','critical',count(*)::bigint,
       'Posted journals whose debit and credit totals differ by more than 0.005'
from journal_entries j
where j.status='posted'
and abs(coalesce((select sum(l.debit-l.credit) from journal_lines l
                  where l.tenant_id=j.tenant_id and l.journal_entry_id=j.id),0))>0.005;

insert into _ebs_integrity_findings
select 'posted_journal_too_few_lines','high',count(*)::bigint,
       'Posted journals with fewer than two lines'
from journal_entries j
where j.status='posted'
and (select count(*) from journal_lines l where l.tenant_id=j.tenant_id and l.journal_entry_id=j.id)<2;

insert into _ebs_integrity_findings
select 'posted_sales_invoice_total_mismatch','high',count(*)::bigint,
       'Posted sales invoice grand totals differ from line totals'
from sales_invoices i
where i.status='posted'
and abs(coalesce(i.grand_total,0)-coalesce((select sum(l.line_total) from sales_invoice_lines l
  where l.tenant_id=i.tenant_id and l.sales_invoice_id=i.id),0))>0.02;

insert into _ebs_integrity_findings
select 'posted_purchase_invoice_total_mismatch','high',count(*)::bigint,
       'Posted purchase invoice grand totals differ from lines plus tax'
from purchase_invoices i
where i.status='posted'
and abs(coalesce(i.grand_total,0)-coalesce((select sum(l.line_total) from purchase_invoice_lines l
  where l.tenant_id=i.tenant_id and l.purchase_invoice_id=i.id),0)-coalesce(i.tax_amount,0))>0.02;

insert into _ebs_integrity_findings
select 'posted_payroll_without_journal','high',count(*)::bigint,
       'Posted payroll runs without a matching journal entry'
from payroll_runs r
where r.status='posted'
and not exists(select 1 from journal_entries j where j.tenant_id=r.tenant_id and j.source_type='payroll' and j.source_id=r.id and j.status='posted');

insert into _ebs_integrity_findings
select 'paid_payroll_without_journal','high',count(*)::bigint,
       'Paid payroll lines without a matching posted payment journal'
from payroll_lines l
where l.payment_status='paid'
and not exists(select 1 from journal_entries j where j.tenant_id=l.tenant_id
               and j.source_type='payroll_payment' and j.source_id=l.id and j.status='posted');

insert into _ebs_integrity_findings
select 'tenant_fk_missing_child_indexes','high',count(*)::bigint,
       'Tenant-scoped foreign keys without a covering child-side index'
from pg_constraint c
join pg_class ct on ct.oid=c.conrelid join pg_namespace cn on cn.oid=ct.relnamespace
join pg_class pt on pt.oid=c.confrelid join pg_namespace pn on pn.oid=pt.relnamespace
join pg_attribute ca on ca.attrelid=c.conrelid and ca.attname='tenant_id' and not ca.attisdropped
join pg_attribute pa on pa.attrelid=c.confrelid and pa.attname='tenant_id' and not pa.attisdropped
where c.contype='f' and cn.nspname='public' and pn.nspname='public'
  and ca.attnum=any(c.conkey) and pa.attnum=any(c.confkey)
  and not exists(select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid
    and i.indpred is null and i.indexprs is null and i.indnkeyatts>=cardinality(c.conkey)
    and (select array_agg(i.indkey[s]::smallint order by s)
         from generate_series(0,cardinality(c.conkey)-1) s)=c.conkey);

-- Compare tenant ownership on every FK edge where both tables carry tenant_id.
-- This detects existing cross-tenant links even when the FK itself is single-column.
do $tenant_audit$
declare
  r record;
  join_sql text;
  sql_text text;
  mismatch_count bigint;
  total_mismatches bigint := 0;
  missing_pair_count bigint := 0;
begin
  for r in
    select c.oid,c.conname,c.conrelid,c.confrelid,c.conkey,c.confkey,
           cn.nspname child_schema,ct.relname child_name,
           pn.nspname parent_schema,pt.relname parent_name,
           ca.attnum child_tenant_att,pa.attnum parent_tenant_att
    from pg_constraint c
    join pg_class ct on ct.oid=c.conrelid join pg_namespace cn on cn.oid=ct.relnamespace
    join pg_class pt on pt.oid=c.confrelid join pg_namespace pn on pn.oid=pt.relnamespace
    join pg_attribute ca on ca.attrelid=c.conrelid and ca.attname='tenant_id' and not ca.attisdropped
    join pg_attribute pa on pa.attrelid=c.confrelid and pa.attname='tenant_id' and not pa.attisdropped
    where c.contype='f' and cn.nspname='public' and pn.nspname='public'
  loop
    if not (r.child_tenant_att=any(r.conkey) and r.parent_tenant_att=any(r.confkey)) then
      missing_pair_count:=missing_pair_count+1;
    end if;
    select string_agg(format('c.%I = p.%I',ca.attname,pa.attname),' and ')
      into join_sql
    from unnest(r.conkey,r.confkey) with ordinality k(c_att,p_att,ord)
    join pg_attribute ca on ca.attrelid=r.conrelid and ca.attnum=k.c_att
    join pg_attribute pa on pa.attrelid=r.confrelid and pa.attnum=k.p_att;
    sql_text:=format('select count(*) from %I.%I c join %I.%I p on %s where c.tenant_id is distinct from p.tenant_id',
      r.child_schema,r.child_name,r.parent_schema,r.parent_name,join_sql);
    execute sql_text into mismatch_count;
    total_mismatches:=total_mismatches+mismatch_count;
  end loop;

  insert into _ebs_integrity_findings values
    ('cross_tenant_reference_rows','critical',total_mismatches,
     'Existing FK-linked rows whose child and parent tenant IDs differ');
  insert into _ebs_integrity_findings values
    ('tenant_fk_without_composite_pair','medium',missing_pair_count,
     'FK relationships between tenant-scoped tables that do not include tenant_id in the FK pair; review for future hardening');
end
$tenant_audit$;

insert into _ebs_integrity_findings
select 'voucher_rpc_custom_permission_guards','high',
       count(*)::bigint,
       'Required voucher RPCs containing the database-side custom update guard (expected 2)'
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('update_draft_voucher_lines','restore_draft_voucher_revision')
and position('module_permission_guard_internal' in pg_get_functiondef(p.oid))>0;

insert into _ebs_integrity_findings
select 'updated_at_trigger_missing_column','high',count(*)::bigint,
       'Tables with set_updated_at trigger but no updated_at column'
from pg_trigger t
join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
join pg_proc p on p.oid=t.tgfoid
where n.nspname='public' and not t.tgisinternal and p.proname='set_updated_at'
  and not exists(select 1 from information_schema.columns x
    where x.table_schema='public' and x.table_name=c.relname and x.column_name='updated_at');

insert into _ebs_integrity_findings
select 'backup_restore_invalid_jsonb_object_length','high',count(*)::bigint,
       'Backup restore functions still referencing unsupported jsonb_object_length'
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='private' and p.prokind='f' and p.proname='restore_tenant_backup_internal'
  and pg_get_functiondef(p.oid) ilike '%jsonb_object_length%';

insert into _ebs_integrity_findings
select 'security_definer_without_search_path','high',count(*)::bigint,
       'SECURITY DEFINER public functions without an explicit search_path'
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef
and not exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) cfg where cfg like 'search_path=%');


insert into _ebs_integrity_findings
select 'custom_permission_guard_policies_permissive','high',count(*)::bigint,
       'Custom permission guard policies that are permissive; expected zero because guard policies must be RESTRICTIVE'
from pg_policy p
join pg_class c on c.oid=p.polrelid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and p.polname like 'module_override_guard_%'
  and p.polpermissive;

select check_key,severity,finding_count,details
from _ebs_integrity_findings
order by case severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,check_key;
