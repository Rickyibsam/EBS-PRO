-- Save the complete per-user module permission matrix atomically.
-- The invoker's RLS context remains active; only a company owner can manage it.

create or replace function public.save_tenant_user_module_permissions(
  p_tenant_id uuid,
  p_user_id uuid,
  p_permissions jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_requested integer;
  v_distinct integer;
  v_saved integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if not private.has_tenant_role_internal(p_tenant_id,array['owner']::text[]) then
    raise exception 'Only the company owner can manage individual user permissions' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.tenant_memberships m
    where m.tenant_id=p_tenant_id and m.user_id=p_user_id
      and m.role not in ('owner','admin')
  ) then
    raise exception 'Target user is not an eligible member of this company';
  end if;
  if jsonb_typeof(p_permissions)<>'array' then
    raise exception 'Permission matrix must be a JSON array';
  end if;

  v_requested:=jsonb_array_length(p_permissions);
  select count(distinct module_key) into v_distinct
  from jsonb_to_recordset(p_permissions) as x(
    module_key text,can_view boolean,can_create boolean,can_update boolean,can_delete boolean
  );
  if v_requested<>v_distinct then
    raise exception 'Permission matrix contains duplicate or invalid module entries';
  end if;
  if exists(
    select 1
    from jsonb_to_recordset(p_permissions) as x(
      module_key text,can_view boolean,can_create boolean,can_update boolean,can_delete boolean
    )
    where module_key is null
       or can_view is null or can_create is null or can_update is null or can_delete is null
       or (not can_view and (can_create or can_update or can_delete))
  ) then
    raise exception 'View access is required before create, update or delete permissions';
  end if;

  delete from public.tenant_user_module_permissions
  where tenant_id=p_tenant_id and user_id=p_user_id;

  insert into public.tenant_user_module_permissions(
    tenant_id,user_id,module_key,can_view,can_create,can_update,can_delete,updated_by
  )
  select p_tenant_id,p_user_id,x.module_key,x.can_view,x.can_create,x.can_update,x.can_delete,auth.uid()
  from jsonb_to_recordset(p_permissions) as x(
    module_key text,can_view boolean,can_create boolean,can_update boolean,can_delete boolean
  );

  get diagnostics v_saved=row_count;
  return jsonb_build_object('success',true,'saved_count',v_saved);
end
$function$;

revoke all on function public.save_tenant_user_module_permissions(uuid,uuid,jsonb) from public,anon;
grant execute on function public.save_tenant_user_module_permissions(uuid,uuid,jsonb) to authenticated;
