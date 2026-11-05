do $$
declare t text;
begin
 foreach t in array array['tenant_user_module_permissions','user_notifications'] loop
  execute format('drop policy if exists module_override_guard_select on public.%I',t);
  execute format('drop policy if exists module_override_grant_select on public.%I',t);
  execute format('drop policy if exists module_override_guard_insert on public.%I',t);
  execute format('drop policy if exists module_override_grant_insert on public.%I',t);
  execute format('drop policy if exists module_override_guard_update on public.%I',t);
  execute format('drop policy if exists module_override_grant_update on public.%I',t);
  execute format('drop policy if exists module_override_guard_delete on public.%I',t);
  execute format('drop policy if exists module_override_grant_delete on public.%I',t);
 end loop;
end $$;
