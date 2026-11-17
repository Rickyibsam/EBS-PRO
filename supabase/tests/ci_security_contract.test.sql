begin;

select plan(32);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='products'),
  'products has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='product_prices'),
  'product_prices has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='product_units'),
  'product_units has RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='products'
           and p.polname='products_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'products has restrictive Booker SELECT guard'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='product_prices'
           and p.polname='product_prices_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'product_prices has restrictive Booker SELECT guard'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='product_units'
           and p.polname='product_units_booker_direct_select_block'
           and p.polcmd='r' and p.polpermissive=false),
  'product_units has restrictive Booker SELECT guard'
);
select ok(
  has_function_privilege('authenticated','public.get_booker_catalog(uuid,uuid)','EXECUTE'),
  'authenticated can execute restricted Booker catalogue RPC'
);
select ok(
  not has_function_privilege('anon','public.get_booker_catalog(uuid,uuid)','EXECUTE'),
  'anonymous role cannot execute Booker catalogue RPC'
);
select ok(
  not has_function_privilege('authenticated','public.get_booker_stock_balances(uuid)','EXECUTE'),
  'authenticated cannot execute legacy tenant-wide stock RPC'
);
select ok(
  not has_function_privilege('authenticated','private.booker_product_allowed(uuid,uuid,uuid)','EXECUTE'),
  'authenticated cannot execute private visibility helper'
);


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='van_stock_movements'),
  'van_stock_movements has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='fixed_assets'),
  'fixed_assets has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='asset_depreciation_entries'),
  'asset_depreciation_entries has RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='van_stock_movements'
           and p.polname in ('van_stock_movements_read','van_stock_movements_insert')),
  'van stock ledger has tenant-role access policies'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='fixed_assets'
           and p.polname='fixed_assets_tenant_access'),
  'fixed asset register has tenant-role access policy'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='asset_depreciation_entries'
           and p.polname='asset_depreciation_entries_tenant_access'),
  'asset depreciation ledger has tenant-role access policy'
);
select ok(
  exists(select 1 from pg_constraint c
         where c.conrelid='public.asset_depreciation_entries'::regclass
           and c.contype='f'
           and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, asset_id)%'),
  'asset depreciation rows enforce same-tenant asset references'
);
select ok(
  exists(select 1 from pg_constraint c
         where c.conrelid='public.fixed_assets'::regclass
           and c.contype='f'
           and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, branch_id)%'),
  'fixed assets enforce same-tenant branch references'
);


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='budgets'),
  'budgets has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='budget_lines'),
  'budget_lines has RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='budgets'
           and p.polname='budgets_tenant_access'),
  'budget headers have tenant-role access policy'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='budget_lines'
           and p.polname='budget_lines_tenant_access'),
  'budget lines have tenant-role access policy'
);


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='voucher_revisions'),
  'voucher revision history has RLS enabled'
);
select ok(
  not has_table_privilege('authenticated','public.voucher_revisions','UPDATE')
  and not has_table_privilege('authenticated','public.voucher_revisions','DELETE'),
  'authenticated users cannot mutate immutable voucher revision history'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='voucher_revisions'
           and p.polname='voucher_revisions_tenant_read')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='voucher_revisions'
           and p.polname='voucher_revisions_tenant_insert'),
  'voucher revision history has tenant-scoped read and insert policies'
);


select ok(
  has_function_privilege('authenticated','public.restore_draft_voucher_revision(uuid)','EXECUTE'),
  'authenticated users can execute guarded voucher header restore RPC'
);
select ok(
  not has_function_privilege('anon','public.restore_draft_voucher_revision(uuid)','EXECUTE'),
  'anonymous users cannot execute voucher header restore RPC'
);


select ok(
  has_function_privilege('authenticated','private.has_tenant_role_internal(uuid,text[])','EXECUTE')
  and has_function_privilege('authenticated','private.is_tenant_member_internal(uuid)','EXECUTE'),
  'authenticated RLS sessions can use private tenant membership helpers'
);
select ok(
  not has_function_privilege('anon','private.has_tenant_role_internal(uuid,text[])','EXECUTE')
  and not has_function_privilege('anon','private.is_tenant_member_internal(uuid)','EXECUTE'),
  'anonymous role cannot execute private tenant membership helpers'
);


select ok(
  (select bool_and(p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=pg_catalog, public, auth%')
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname in ('has_tenant_role_internal','is_tenant_member_internal')),
  'private tenant helpers are SECURITY DEFINER with a fixed safe search_path'
);


select ok(
  (select position('current_setting(''app.ebs_backup_restore''' in p.prosrc)>0
          and position('public.has_tenant_role' in p.prosrc)>0
          and position('if not v_restore' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='enforce_stock_batch_expiry_rules'),
  'batch/expiry validation bypass is limited to authorized backup restore sessions'
);


select ok(
  (select position('module_permission_grant_internal' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='post_payroll_run'),
  'payroll posting RPC honors explicit HR/payroll update grants'
);

select * from finish();
rollback;
