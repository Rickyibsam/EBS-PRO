create or replace function private.module_permission_guard_internal(
 p_tenant_id uuid,p_module_key text,p_action text
) returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, public, private, auth
as $$
declare v_permission public.tenant_user_module_permissions%rowtype;v_reports public.tenant_user_module_permissions%rowtype;
begin
 if auth.uid() is null or not private.is_tenant_member_internal(p_tenant_id) then return false; end if;
 if private.has_tenant_role_internal(p_tenant_id,array['owner','admin']::text[]) then return true; end if;
 select * into v_permission from public.tenant_user_module_permissions
  where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
 if p_action='view' then
  if found and v_permission.can_view then return true; end if;
  select * into v_reports from public.tenant_user_module_permissions
   where tenant_id=p_tenant_id and user_id=auth.uid() and module_key='reports_analytics';
  if found and v_reports.can_view then return true; end if;
  if v_permission.id is not null then return false; end if;
  return true;
 end if;
 if not found then return true; end if;
 if not v_permission.can_view then return false; end if;
 return case p_action when 'create' then v_permission.can_create
  when 'update' then v_permission.can_update when 'delete' then v_permission.can_delete else false end;
end $$;

create or replace function private.module_permission_grant_internal(
 p_tenant_id uuid,p_module_key text,p_action text
) returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, public, private, auth
as $$
declare v_permission public.tenant_user_module_permissions%rowtype;v_reports public.tenant_user_module_permissions%rowtype;
begin
 if auth.uid() is null or not private.is_tenant_member_internal(p_tenant_id)
    or private.has_tenant_role_internal(p_tenant_id,array['owner','admin']::text[]) then return false; end if;
 if p_action='view' then
  select * into v_permission from public.tenant_user_module_permissions
   where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
  if found and v_permission.can_view then return true; end if;
  select * into v_reports from public.tenant_user_module_permissions
   where tenant_id=p_tenant_id and user_id=auth.uid() and module_key='reports_analytics';
  return found and v_reports.can_view;
 end if;
 select * into v_permission from public.tenant_user_module_permissions
  where tenant_id=p_tenant_id and user_id=auth.uid() and module_key=p_module_key;
 if not found or not v_permission.can_view then return false; end if;
 return case p_action when 'create' then v_permission.can_create
  when 'update' then v_permission.can_update when 'delete' then v_permission.can_delete else false end;
end $$;
