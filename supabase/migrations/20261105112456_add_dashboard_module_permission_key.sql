alter table public.tenant_user_module_permissions
 drop constraint if exists tenant_user_module_permissions_module_key_check;
alter table public.tenant_user_module_permissions
 add constraint tenant_user_module_permissions_module_key_check
 check (module_key in (
  'dashboard_management','sales_customer','order_booking','inventory',
  'purchase_supplier','accounts_finance','distribution_delivery',
  'hr_payroll','reports_analytics','administration_security'
 ));
