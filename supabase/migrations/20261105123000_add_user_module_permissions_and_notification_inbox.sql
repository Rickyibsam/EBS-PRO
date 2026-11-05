-- Per-user module permission overrides and persistent notification inbox.
-- Existing role policies remain the default. Explicit owner-set overrides can
-- restrict or extend a member's access, while tenant membership is always checked.

create table if not exists public.tenant_user_module_permissions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  module_key text not null check (module_key in (
    'dashboard_management','sales_customer','order_booking','inventory','purchase_supplier',
    'accounts_finance','distribution_delivery','hr_payroll',
    'reports_analytics','administration_security'
  )),
  can_view boolean not null default true,
  can_create boolean not null default false,
  can_update boolean not null default false,
  can_delete boolean not null default false,
  updated_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,user_id,module_key)
);
create index if not exists tenant_user_module_permissions_lookup_idx
  on public.tenant_user_module_permissions(tenant_id,user_id,module_key);
alter table public.tenant_user_module_permissions enable row level security;
drop policy if exists module_permissions_select on public.tenant_user_module_permissions;
create policy module_permissions_select on public.tenant_user_module_permissions
 for select to authenticated using (
   user_id = (select auth.uid())
   or private.has_tenant_role_internal(tenant_id,array['owner']::text[])
 );
drop policy if exists module_permissions_owner_insert on public.tenant_user_module_permissions;
create policy module_permissions_owner_insert on public.tenant_user_module_permissions
 for insert to authenticated with check (
   private.has_tenant_role_internal(tenant_id,array['owner']::text[])
   and updated_by = (select auth.uid())
 );
drop policy if exists module_permissions_owner_update on public.tenant_user_module_permissions;
create policy module_permissions_owner_update on public.tenant_user_module_permissions
 for update to authenticated using (
   private.has_tenant_role_internal(tenant_id,array['owner']::text[])
 ) with check (
   private.has_tenant_role_internal(tenant_id,array['owner']::text[])
   and updated_by = (select auth.uid())
 );
drop policy if exists module_permissions_owner_delete on public.tenant_user_module_permissions;
create policy module_permissions_owner_delete on public.tenant_user_module_permissions
 for delete to authenticated using (
   private.has_tenant_role_internal(tenant_id,array['owner']::text[])
 );
grant select,insert,update,delete on public.tenant_user_module_permissions to authenticated;

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  notification_key text not null,
  title text not null,
  body text not null,
  module_key text not null default 'overview',
  severity text not null default 'info' check (severity in ('info','warning','success','error')),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tenant_id,user_id,notification_key)
);
create index if not exists user_notifications_inbox_idx
 on public.user_notifications(tenant_id,user_id,read_at,created_at desc);
alter table public.user_notifications enable row level security;
drop policy if exists user_notifications_read_own on public.user_notifications;
create policy user_notifications_read_own on public.user_notifications
 for select to authenticated using (
   user_id = (select auth.uid())
   and private.is_tenant_member_internal(tenant_id)
 );
drop policy if exists user_notifications_insert_own on public.user_notifications;
create policy user_notifications_insert_own on public.user_notifications
 for insert to authenticated with check (
   user_id = (select auth.uid())
   and private.is_tenant_member_internal(tenant_id)
 );
drop policy if exists user_notifications_update_own on public.user_notifications;
create policy user_notifications_update_own on public.user_notifications
 for update to authenticated using (
   user_id = (select auth.uid())
   and private.is_tenant_member_internal(tenant_id)
 ) with check (
   user_id = (select auth.uid())
   and private.is_tenant_member_internal(tenant_id)
 );
grant select,insert,update on public.user_notifications to authenticated;

create or replace function private.module_permission_guard_internal(
 p_tenant_id uuid,p_module_key text,p_action text
) returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, public, private, auth
as $$
declare v_permission public.tenant_user_module_permissions%rowtype;
begin
 if auth.uid() is null or not private.is_tenant_member_internal(p_tenant_id) then return false; end if;
 if private.has_tenant_role_internal(p_tenant_id,array['owner','admin']::text[]) then return true; end if;
 select * into v_permission from public.tenant_user_module_permissions
  where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
 if not found then return true; end if;
 return case p_action
  when 'view' then v_permission.can_view
  when 'create' then v_permission.can_create
  when 'update' then v_permission.can_update
  when 'delete' then v_permission.can_delete
  else false end;
end $$;

create or replace function private.module_permission_grant_internal(
 p_tenant_id uuid,p_module_key text,p_action text
) returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, public, private, auth
as $$
declare v_permission public.tenant_user_module_permissions%rowtype;
begin
 if auth.uid() is null or not private.is_tenant_member_internal(p_tenant_id)
    or private.has_tenant_role_internal(p_tenant_id,array['owner','admin']::text[]) then return false; end if;
 select * into v_permission from public.tenant_user_module_permissions
  where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
 if not found then return false; end if;
 return case p_action
  when 'view' then v_permission.can_view
  when 'create' then v_permission.can_create
  when 'update' then v_permission.can_update
  when 'delete' then v_permission.can_delete
  else false end;
end $$;
revoke all on function private.module_permission_guard_internal(uuid,text,text) from public,anon;
revoke all on function private.module_permission_grant_internal(uuid,text,text) from public,anon;
grant execute on function private.module_permission_guard_internal(uuid,text,text) to authenticated;
grant execute on function private.module_permission_grant_internal(uuid,text,text) to authenticated;

do $$
declare r record; v_module text;
begin
 for r in
  select c.table_name from information_schema.columns c
  where c.table_schema='public' and c.column_name='tenant_id'
  group by c.table_name
 loop
  v_module := case r.table_name
   when 'parties' then 'sales_customer'
   when 'sales_orders' then 'sales_customer' when 'sales_order_lines' then 'sales_customer'
   when 'sales_invoices' then 'sales_customer' when 'sales_invoice_lines' then 'sales_customer'
   when 'sales_credit_notes' then 'sales_customer' when 'sales_credit_note_lines' then 'sales_customer'
   when 'customer_price_lists' then 'sales_customer' when 'price_lists' then 'sales_customer'
   when 'product_prices' then 'sales_customer' when 'sales_targets' then 'sales_customer'
   when 'booker_product_visibility' then 'order_booking' when 'booker_visits' then 'order_booking'
   when 'route_assignments' then 'order_booking' when 'route_customers' then 'order_booking'
   when 'sales_routes' then 'order_booking'
   when 'products' then 'inventory' when 'product_categories' then 'inventory'
   when 'product_units' then 'inventory' when 'units_of_measure' then 'inventory'
   when 'stock_movements' then 'inventory' when 'stock_takes' then 'inventory'
   when 'stock_take_lines' then 'inventory' when 'stock_transfers' then 'inventory'
   when 'stock_transfer_lines' then 'inventory' when 'warehouses' then 'inventory'
   when 'branches' then 'inventory'
   when 'purchase_orders' then 'purchase_supplier' when 'purchase_order_lines' then 'purchase_supplier'
   when 'goods_receipts' then 'purchase_supplier' when 'goods_receipt_lines' then 'purchase_supplier'
   when 'purchase_invoices' then 'purchase_supplier' when 'purchase_invoice_lines' then 'purchase_supplier'
   when 'purchase_debit_notes' then 'purchase_supplier' when 'purchase_debit_note_lines' then 'purchase_supplier'
   when 'vendor_product_catalog' then 'purchase_supplier' when 'vendor_reconciliations' then 'purchase_supplier'
   when 'chart_of_accounts' then 'accounts_finance' when 'journal_entries' then 'accounts_finance'
   when 'journal_lines' then 'accounts_finance' when 'payments' then 'accounts_finance'
   when 'expenses' then 'accounts_finance' when 'bank_reconciliations' then 'accounts_finance'
   when 'cheque_register' then 'accounts_finance' when 'cash_flow_account_mappings' then 'accounts_finance'
   when 'fixed_assets' then 'accounts_finance' when 'fixed_asset_account_mappings' then 'accounts_finance'
   when 'asset_depreciation_entries' then 'accounts_finance'
   when 'employee_advance_account_mappings' then 'accounts_finance'
   when 'deliveries' then 'distribution_delivery' when 'delivery_lines' then 'distribution_delivery'
   when 'delivery_shop_visits' then 'distribution_delivery' when 'delivery_charges' then 'distribution_delivery'
   when 'delivery_charge_rules' then 'distribution_delivery'
   when 'delivery_charge_collections' then 'distribution_delivery'
   when 'delivery_charge_account_mappings' then 'distribution_delivery'
   when 'van_delivery_reservations' then 'distribution_delivery'
   when 'van_stock_movements' then 'distribution_delivery'
   when 'employees' then 'hr_payroll' when 'departments' then 'hr_payroll'
   when 'designations' then 'hr_payroll' when 'employee_attendance' then 'hr_payroll'
   when 'employee_leaves' then 'hr_payroll' when 'employee_advances' then 'hr_payroll'
   when 'employee_advance_repayments' then 'hr_payroll' when 'payroll_runs' then 'hr_payroll'
   when 'payroll_lines' then 'hr_payroll' when 'payroll_incentive_accruals' then 'hr_payroll'
   when 'sales_incentive_accruals' then 'hr_payroll'
   when 'sales_incentive_adjustments' then 'hr_payroll'
   when 'app_settings' then 'administration_security' when 'audit_logs' then 'administration_security'
   when 'login_history' then 'administration_security' when 'voucher_revisions' then 'administration_security'
   when 'document_sequences' then 'administration_security'
   when 'tenant_memberships' then null
   else 'administration_security'
  end;
  if v_module is null then continue; end if;
  execute format('drop policy if exists module_override_guard_select on public.%I',r.table_name);
  execute format('drop policy if exists module_override_grant_select on public.%I',r.table_name);
  execute format('drop policy if exists module_override_guard_insert on public.%I',r.table_name);
  execute format('drop policy if exists module_override_grant_insert on public.%I',r.table_name);
  execute format('drop policy if exists module_override_guard_update on public.%I',r.table_name);
  execute format('drop policy if exists module_override_grant_update on public.%I',r.table_name);
  execute format('drop policy if exists module_override_guard_delete on public.%I',r.table_name);
  execute format('drop policy if exists module_override_grant_delete on public.%I',r.table_name);
  execute format('create policy module_override_guard_select on public.%I as restrictive for select to authenticated using (private.module_permission_guard_internal(tenant_id,%L,''view''))',r.table_name,v_module);
  execute format('create policy module_override_grant_select on public.%I as permissive for select to authenticated using (private.module_permission_grant_internal(tenant_id,%L,''view''))',r.table_name,v_module);
  execute format('create policy module_override_guard_insert on public.%I as restrictive for insert to authenticated with check (private.module_permission_guard_internal(tenant_id,%L,''create''))',r.table_name,v_module);
  execute format('create policy module_override_grant_insert on public.%I as permissive for insert to authenticated with check (private.module_permission_grant_internal(tenant_id,%L,''create''))',r.table_name,v_module);
  execute format('create policy module_override_guard_update on public.%I as restrictive for update to authenticated using (private.module_permission_guard_internal(tenant_id,%L,''update'')) with check (private.module_permission_guard_internal(tenant_id,%L,''update''))',r.table_name,v_module,v_module);
  execute format('create policy module_override_grant_update on public.%I as permissive for update to authenticated using (private.module_permission_grant_internal(tenant_id,%L,''update'')) with check (private.module_permission_grant_internal(tenant_id,%L,''update''))',r.table_name,v_module,v_module);
  execute format('create policy module_override_guard_delete on public.%I as restrictive for delete to authenticated using (private.module_permission_guard_internal(tenant_id,%L,''delete''))',r.table_name,v_module);
  execute format('create policy module_override_grant_delete on public.%I as permissive for delete to authenticated using (private.module_permission_grant_internal(tenant_id,%L,''delete''))',r.table_name,v_module);
 end loop;
end $$;
