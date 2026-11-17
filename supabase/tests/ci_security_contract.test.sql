begin;

select plan(73);

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
  case when to_regprocedure('public.get_booker_stock_balances(uuid)') is null then true
       else not has_function_privilege('authenticated','public.get_booker_stock_balances(uuid)','EXECUTE') end,
  'legacy tenant-wide stock RPC is absent or not executable by authenticated users'
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


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='sales_incentive_adjustments'),
  'sales incentive adjustment ledger has RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='sales_incentive_adjustments'
           and p.polname='sales_incentive_adjustments_select')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='sales_incentive_adjustments'
           and p.polname='sales_incentive_adjustments_insert'),
  'sales incentive adjustment ledger has tenant-scoped read/insert policies'
);
select ok(
  has_function_privilege('authenticated','public.apply_commission_return_adjustments(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.apply_commission_return_adjustments(uuid)','EXECUTE')
  and (select position('module_permission_grant_internal' in p.prosrc)>0
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='apply_commission_return_adjustments'),
  'commission clawback RPC is authenticated-only and honors HR/payroll custom update grants'
);


select ok(
  (select count(*)=3 from pg_constraint c
   where c.conrelid='public.sales_incentive_adjustments'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'commission clawback rows enforce same-tenant employee, payroll and sales-target references'
);
select ok(
  exists(select 1 from pg_constraint c
         where c.conrelid='public.sales_incentive_adjustments'::regclass and c.contype='u'
           and pg_get_constraintdef(c.oid) like 'UNIQUE (tenant_id, sales_target_id, payroll_run_id)%'),
  'commission clawback ledger is idempotent per tenant, target and payroll run'
);


select ok(
  (select count(*)=3 and bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('employee_advances','employee_advance_repayments','employee_advance_account_mappings')),
  'employee advance and account mapping tables all have RLS enabled'
);
select ok(
  has_function_privilege('authenticated','private.create_employee_advance_internal(uuid,uuid,numeric,date,text)','EXECUTE')
  and has_function_privilege('authenticated','private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.create_employee_advance(uuid,uuid,numeric,date,text)','EXECUTE')
  and has_function_privilege('authenticated','public.record_employee_advance_repayment(uuid,numeric,date,text,text,text)','EXECUTE')
  and not has_function_privilege('anon','private.create_employee_advance_internal(uuid,uuid,numeric,date,text)','EXECUTE')
  and not has_function_privilege('anon','private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.create_employee_advance(uuid,uuid,numeric,date,text)','EXECUTE')
  and not has_function_privilege('anon','public.record_employee_advance_repayment(uuid,numeric,date,text,text,text)','EXECUTE'),
  'employee advance internal and public RPCs are authenticated-only'
);
select ok(
  (select count(*)=2 from pg_constraint c
   where c.conrelid='public.employee_advances'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %')
  and (select count(*)=2 from pg_constraint c
   where c.conrelid='public.employee_advance_repayments'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %')
  and (select count(*)=3 from pg_constraint c
   where c.conrelid='public.employee_advance_account_mappings'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'employee advances, repayments and account mappings enforce same-tenant foreign keys'
);
select ok(
  (select count(*)=4 and bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('delivery_charge_rules','delivery_charges','delivery_charge_collections','delivery_charge_account_mappings')),
  'all delivery charge tables have RLS enabled'
);
select ok(
  has_function_privilege('authenticated','private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text)','EXECUTE')
  and has_function_privilege('authenticated','public.settle_delivery_charge(uuid,numeric,text,text,boolean,text)','EXECUTE')
  and not has_function_privilege('anon','private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text)','EXECUTE')
  and not has_function_privilege('anon','public.settle_delivery_charge(uuid,numeric,text,text,boolean,text)','EXECUTE'),
  'delivery charge settlement RPCs are authenticated-only'
);
select ok(
  (select count(*)=4 from pg_constraint c
   where c.conrelid='public.delivery_charges'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %')
  and (select count(*)=2 from pg_constraint c
   where c.conrelid='public.delivery_charge_collections'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %')
  and (select count(*)=3 from pg_constraint c
   where c.conrelid='public.delivery_charge_account_mappings'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'delivery charge records and account mappings enforce same-tenant foreign keys'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public' and tablename='delivery_charge_collections'
         and indexname='delivery_charge_collections_tenant_idempotency_uidx'),
  'delivery charge collection retries have a tenant-scoped idempotency index'
);


select ok(
  (select count(*)=2 and bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('stock_takes','stock_take_lines')),
  'stock take headers and lines both have RLS enabled'
);
select ok(
  has_function_privilege('authenticated','public.create_stock_take(uuid,uuid,date,jsonb,text)','EXECUTE')
  and has_function_privilege('authenticated','public.update_stock_take_counts(uuid,jsonb)','EXECUTE')
  and has_function_privilege('authenticated','public.post_stock_take(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.create_stock_take(uuid,uuid,date,jsonb,text)','EXECUTE')
  and not has_function_privilege('anon','public.update_stock_take_counts(uuid,jsonb)','EXECUTE')
  and not has_function_privilege('anon','public.post_stock_take(uuid)','EXECUTE'),
  'stock take workflow RPCs are authenticated-only'
);
select ok(
  (select count(*)=1 from pg_constraint c
   where c.conrelid='public.stock_takes'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, warehouse_id)%')
  and (select count(*)=2 from pg_constraint c
   where c.conrelid='public.stock_take_lines'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'stock take headers and lines enforce same-tenant warehouse, parent and product references'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public' and tablename='stock_take_lines'
         and indexname='stock_take_lines_lot_uidx'),
  'stock take prevents duplicate product/batch/expiry count lines'
);


select ok(
  has_function_privilege('authenticated','public.get_erp_report_summary(uuid,date,date)','EXECUTE')
  and not has_function_privilege('anon','public.get_erp_report_summary(uuid,date,date)','EXECUTE')
  and (select position('module_permission_grant_internal' in p.prosrc)>0
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='get_erp_report_summary'),
  'date-filtered ERP report RPC is authenticated-only and honors custom report permissions'
);


select ok(
  (select count(*)=8 from pg_policy p join pg_class c on c.oid=p.polrelid
   join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('stock_takes','stock_take_lines')
     and p.polname in ('module_override_guard_select','module_override_grant_select','module_override_guard_update','module_override_grant_update')),
  'stock take headers and lines enforce custom inventory view/update permissions'
);


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='booker_product_visibility'),
  'Booker product visibility rules have RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='booker_product_visibility' and p.polname='booker_visibility_read')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='booker_product_visibility' and p.polname='booker_visibility_write')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='booker_product_visibility' and p.polname='module_override_guard_select')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='booker_product_visibility' and p.polname='module_override_grant_select'),
  'Booker visibility rules have role and custom order-booking access policies'
);
select ok(
  (select count(*)=3 from pg_constraint c
   where c.conrelid='public.booker_product_visibility'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'Booker visibility rules enforce same-tenant employee, vendor and product references'
);


select ok(
  exists(select 1 from pg_trigger t where t.tgrelid='public.booker_product_visibility'::regclass
         and not t.tgisinternal and t.tgname='booker_visibility_tenant_guard')
  and (select position('party_type in' in p.prosrc)>0
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='validate_booker_visibility_tenant'),
  'Booker visibility writes validate same-tenant employee, vendor and product ownership'
);


select ok(
  (select count(*)=2 and bool_and(c.relrowsecurity)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('departments','designations')),
  'HR departments and designations both exist with RLS enabled'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='departments' and p.polname='departments_select')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='departments' and p.polname='departments_write')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='designations' and p.polname='designations_select')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='designations' and p.polname='designations_write'),
  'HR department and designation access is tenant-role scoped'
);
select ok(
  (select count(*)=1 from pg_constraint c
   where c.conrelid='public.designations'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, department_id)%')
  and (select count(*)=2 from pg_constraint c
   where c.conrelid='public.employees'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'
     and (pg_get_constraintdef(c.oid) like '%REFERENCES departments%'
          or pg_get_constraintdef(c.oid) like '%REFERENCES designations%')),
  'employee department/designation and designation department links are tenant-safe'
);


select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='payroll_incentive_accruals'),
  'payroll incentive accrual ledger has RLS enabled'
);
select ok(
  (select count(*)=4 from pg_constraint c
   where c.conrelid='public.payroll_incentive_accruals'::regclass and c.contype='f'
     and pg_get_constraintdef(c.oid) like 'FOREIGN KEY (tenant_id, %'),
  'payroll incentive accruals enforce same-tenant run, line, employee and target references'
);
select ok(
  exists(select 1 from pg_constraint c
         where c.conrelid='public.payroll_incentive_accruals'::regclass and c.contype='u'
           and pg_get_constraintdef(c.oid) like 'UNIQUE (tenant_id, payroll_run_id, sales_target_id)%')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='payroll_incentive_accruals'
           and p.polname='module_override_guard_insert')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='payroll_incentive_accruals'
           and p.polname='module_override_grant_insert'),
  'payroll incentive accrual import is idempotent and custom-permission guarded'
);


select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='employee_advance_account_mappings'
           and p.polname='module_override_guard_update')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='employee_advance_account_mappings'
           and p.polname='module_override_grant_update'),
  'employee advance account mappings honor custom accounts/finance update permissions'
);


select ok(
  (select count(*)=8 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('departments','designations')
     and p.polname in ('module_override_guard_update','module_override_grant_update','module_override_guard_select','module_override_grant_select')),
  'department and designation masters honor custom HR/payroll view/update permissions'
);


select ok(
  (select count(*)=3 and bool_and(c.relrowsecurity)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('platform_admins','platform_support_tickets','platform_support_messages')),
  'platform admin and support tables all enforce row level security'
);
select ok(
  not has_table_privilege('anon','public.platform_admins','SELECT')
  and has_table_privilege('authenticated','public.platform_admins','SELECT')
  and not has_table_privilege('authenticated','public.platform_admins','INSERT')
  and exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='platform_admins' and p.polname='platform_admins_read_self'),
  'platform role registry is not directly readable or writable through the Data API'
);
select ok(
  has_function_privilege('authenticated','public.platform_admin_me()','EXECUTE')
  and not has_function_privilege('anon','public.platform_admin_me()','EXECUTE')
  and has_function_privilege('authenticated','public.platform_admin_list_companies()','EXECUTE')
  and not has_function_privilege('anon','public.platform_admin_list_companies()','EXECUTE'),
  'platform admin RPCs are authenticated-only'
);
select ok(
  (select p.prosecdef and position('is_platform_staff_internal' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_admin_list_companies'),
  'company directory RPC uses a server-side platform role check'
);
select ok(
  (select count(*)=9 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and
     ((c.relname='platform_support_tickets' and p.polname like 'platform_support_tickets_%')
      or (c.relname='platform_support_messages' and p.polname like 'platform_support_messages_%'))),
  'support tickets and messages have separate platform-staff and tenant-member policies'
);
select ok(
  (select count(*)=1 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='platform_support_tickets' and p.polcmd='w'
     and p.polname='platform_support_tickets_staff_update'),
  'only platform staff can update ticket status and assignment'
);
select ok(
  has_column_privilege('authenticated','public.platform_support_tickets','status','UPDATE')
  and has_column_privilege('authenticated','public.platform_support_tickets','assigned_to','UPDATE')
  and not has_column_privilege('authenticated','public.platform_support_tickets','tenant_id','UPDATE')
  and not has_column_privilege('authenticated','public.platform_support_tickets','subject','UPDATE'),
  'ticket updates are column-scoped so staff cannot rewrite tenant identity or issue details'
);
select ok(
  not has_table_privilege('authenticated','public.platform_support_tickets','DELETE')
  and not has_table_privilege('authenticated','public.platform_support_messages','UPDATE')
  and not has_table_privilege('authenticated','public.platform_support_messages','DELETE'),
  'support API grants exclude ticket deletion and message mutation'
);
select ok(
  exists(select 1 from pg_trigger t
         where t.tgrelid='public.platform_support_messages'::regclass
           and not t.tgisinternal and t.tgname='platform_support_message_touch_ticket'),
  'support replies automatically update ticket activity time'
);


select ok(
  (select not p.prosecdef
      and position('v_product.track_expiry' in p.prosrc)>0
      and position('expiry_date is not null' in p.prosrc)>0
      and position('v_product.track_batch' in p.prosrc)>0
      and position('nullif(btrim(batch_number)' in p.prosrc)>0
   from pg_proc p
   where p.oid='public.dispatch_delivery(uuid,jsonb)'::regprocedure),
  'warehouse dispatch excludes missing expiry and batch metadata when product tracking requires it'
);


select ok(
  exists(select 1 from pg_trigger t where t.tgrelid='public.products'::regclass and not t.tgisinternal and t.tgname='guard_product_tracking_enablement')
  and (select p.prosecdef and position('positive stock has no expiry date' in lower(p.prosrc))>0
        and position('positive stock has no batch number' in lower(p.prosrc))>0
       from pg_proc p where p.oid='private.guard_product_tracking_enablement()'::regprocedure),
  'product tracking cannot be enabled while positive legacy stock lacks required metadata'
);

select * from finish();
rollback;
