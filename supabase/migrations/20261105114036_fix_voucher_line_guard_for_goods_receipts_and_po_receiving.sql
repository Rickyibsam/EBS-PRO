-- The shared voucher-line guard must use received_by for goods_receipts
-- (there is no created_by column) and allow only received quantity accumulation
-- on an approved purchase order line.
do $$
declare
 v_definition text;
 v_old_decl text := 'v_parent_id uuid;v_status text;v_parent_table text;v_fk text;v_record jsonb;v_parent_created timestamptz;v_parent_creator uuid;';
 v_new_decl text := 'v_parent_id uuid;v_status text;v_parent_table text;v_fk text;v_record jsonb;v_parent_created timestamptz;v_parent_creator uuid;v_creator_col text;';
 v_old_guard text := $old$
   if lower(coalesce(v_status,'')) in ('posted','approved') then raise exception 'Lines belonging to an approved or posted voucher cannot be changed.' using errcode='55000'; end if;
$old$;
 v_new_guard text := $new$
   if lower(coalesce(v_status,'')) in ('posted','approved') then
    if not (v_parent_table='purchase_orders' and tg_op='UPDATE'
      and lower(coalesce(v_status,''))='approved'
      and (to_jsonb(new)-array['received_base_quantity'])=(to_jsonb(old)-array['received_base_quantity'])) then
     raise exception 'Lines belonging to an approved or posted voucher cannot be changed.' using errcode='55000';
    end if;
   end if;
$new$;
 v_old_select text := $old$
   execute format('select status,created_at,created_by from public.%I where id=$1',v_parent_table) into v_status,v_parent_created,v_parent_creator using v_parent_id;
$old$;
 v_new_select text := $new$
   v_creator_col:=case when v_parent_table='goods_receipts' then 'received_by' else 'created_by' end;
   execute format('select status,created_at,%I from public.%I where id=$1',v_creator_col,v_parent_table) into v_status,v_parent_created,v_parent_creator using v_parent_id;
$new$;
begin
 select pg_get_functiondef('public.prevent_posted_voucher_mutation()'::regprocedure) into v_definition;
 if position(v_old_decl in v_definition)=0 or position(v_old_guard in v_definition)=0 or position(v_old_select in v_definition)=0 then
  raise exception 'Expected voucher line guard blocks were not found; no function was changed.';
 end if;
 v_definition:=replace(v_definition,v_old_decl,v_new_decl);
 v_definition:=replace(v_definition,v_old_guard,v_new_guard);
 v_definition:=replace(v_definition,v_old_select,v_new_select);
 execute v_definition;
end $$;
