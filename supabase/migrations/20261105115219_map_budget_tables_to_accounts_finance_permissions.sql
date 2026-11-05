do $$
declare t text;
begin
 foreach t in array array['budgets','budget_lines'] loop
  execute format('alter policy module_override_guard_select on public.%I using (private.module_permission_guard_internal(tenant_id,''accounts_finance'',''view''))',t);
  execute format('alter policy module_override_grant_select on public.%I using (private.module_permission_grant_internal(tenant_id,''accounts_finance'',''view''))',t);
  execute format('alter policy module_override_guard_insert on public.%I with check (private.module_permission_guard_internal(tenant_id,''accounts_finance'',''create''))',t);
  execute format('alter policy module_override_grant_insert on public.%I with check (private.module_permission_grant_internal(tenant_id,''accounts_finance'',''create''))',t);
  execute format('alter policy module_override_guard_update on public.%I using (private.module_permission_guard_internal(tenant_id,''accounts_finance'',''update'')) with check (private.module_permission_guard_internal(tenant_id,''accounts_finance'',''update''))',t);
  execute format('alter policy module_override_grant_update on public.%I using (private.module_permission_grant_internal(tenant_id,''accounts_finance'',''update'')) with check (private.module_permission_grant_internal(tenant_id,''accounts_finance'',''update''))',t);
  execute format('alter policy module_override_guard_delete on public.%I using (private.module_permission_guard_internal(tenant_id,''accounts_finance'',''delete''))',t);
  execute format('alter policy module_override_grant_delete on public.%I using (private.module_permission_grant_internal(tenant_id,''accounts_finance'',''delete''))',t);
 end loop;
end $$;
