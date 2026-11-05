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
 if p_action <> 'view' and not v_permission.can_view then return false; end if;
 return case p_action when 'view' then v_permission.can_view
  when 'create' then v_permission.can_create when 'update' then v_permission.can_update
  when 'delete' then v_permission.can_delete else false end;
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
 if not found or (p_action <> 'view' and not v_permission.can_view) then return false; end if;
 return case p_action when 'view' then v_permission.can_view
  when 'create' then v_permission.can_create when 'update' then v_permission.can_update
  when 'delete' then v_permission.can_delete else false end;
end $$;
