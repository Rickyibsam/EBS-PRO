-- Finish custom inventory/distribution action checks for stock take and van stock workflows.
do $$
declare v_item record;v_oid oid;v_definition text;
begin
 for v_item in select * from (values
 ('public.create_stock_take(uuid,uuid,date,jsonb,text)',
  $old$if v_user is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot create a physical stock take.' using errcode='42501'; end if;$old$,
  $new$if v_user is null or not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'inventory','create')) then raise exception 'You cannot create a physical stock take.' using errcode='42501'; end if;$new$),
 ('public.update_stock_take_counts(uuid,jsonb)',
  $old$if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot edit this stock take.' using errcode='42501'; end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_take.tenant_id,'inventory','update')) then raise exception 'You cannot edit this stock take.' using errcode='42501'; end if;$new$),
 ('public.post_stock_take(uuid)',
  $old$if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot post this stock take.' using errcode='42501'; end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_take.tenant_id,'inventory','update')) then raise exception 'You cannot post this stock take.' using errcode='42501'; end if;$new$),
 ('public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text)',
  $old$if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
  raise exception 'You do not have permission to transfer van stock.' using errcode='42501';
 end if;$old$,
  $new$if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','create')) then
  raise exception 'You do not have permission to transfer van stock.' using errcode='42501';
 end if;$new$),
 ('public.dispatch_van_delivery(uuid,text,jsonb)',
  $old$if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only warehouse/management can dispatch a van delivery.' using errcode='42501'; end if;$old$,
  $new$if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only authorized distribution/warehouse users can dispatch a van delivery.' using errcode='42501'; end if;$new$)
 ) as x(signature,old_text,new_text)
 loop
  v_oid:=to_regprocedure(v_item.signature);
  if v_oid is null then raise exception 'Required workflow RPC % not found.',v_item.signature; end if;
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_item.old_text in v_definition)=0 then raise exception 'Expected action guard not found in %.',v_item.signature; end if;
  execute replace(v_definition,v_item.old_text,v_item.new_text);
 end loop;

 select pg_get_functiondef('public.post_journal_entry(uuid)'::regprocedure) into v_definition;
 if position('when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'') then' in v_definition)=0 then
  raise exception 'Expected inventory journal source mapping not found.';
 end if;
 execute replace(v_definition,
  'when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'') then',
  'when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'',''stock_take'') then');

 select pg_get_functiondef('private.assign_journal_entry_branch()'::regprocedure) into v_definition;
 if position('when ''stock_transfer'' then' in v_definition)=0 then raise exception 'Expected branch inference stock transfer block not found.'; end if;
 execute replace(v_definition,
  'when ''stock_transfer'' then',
  'when ''stock_take'' then select w.branch_id into v_branch from public.stock_takes t join public.warehouses w on w.id=t.warehouse_id and w.tenant_id=t.tenant_id where t.id=new.source_id and t.tenant_id=new.tenant_id;' || chr(10) || '  when ''stock_transfer'' then');
end $$;
