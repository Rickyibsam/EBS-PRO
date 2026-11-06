-- Report additive restore completeness accurately and allow deeper FK dependency chains.
-- Existing rows remain untouched; no business data is modified by this function replacement.
do $$
declare
  v_definition text;
  v_old_loop text := 'for v_pass in 1..10 loop';
  v_new_loop text := 'for v_pass in 1..100 loop';
  v_old_return text := $old$return jsonb_build_object('success',true,'imported_rows',v_inserted,'passes',v_pass,'skipped_tables',v_skipped,'errors',v_errors,'mode','additive_only_no_overwrite_no_delete');$old$;
  v_new_return text := $new$return jsonb_build_object(
    'success',jsonb_object_length(v_errors)=0 and not (v_pass=100 and v_progress>0),
    'complete',jsonb_object_length(v_errors)=0 and not (v_pass=100 and v_progress>0),
    'dependency_pass_limit_reached',v_pass=100 and v_progress>0,
    'imported_rows',v_inserted,'passes',v_pass,'skipped_tables',v_skipped,'errors',v_errors,
    'mode','additive_only_no_overwrite_no_delete'
  );$new$;
begin
  select pg_get_functiondef('private.restore_tenant_backup_internal(uuid,jsonb)'::regprocedure)
    into v_definition;
  if position(v_old_loop in v_definition)=0 or position(v_old_return in v_definition)=0 then
    raise exception 'Expected additive restore loop/return blocks were not found; no function was changed.';
  end if;
  v_definition:=replace(v_definition,v_old_loop,v_new_loop);
  v_definition:=replace(v_definition,v_old_return,v_new_return);
  execute v_definition;
end $$;
