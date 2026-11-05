-- Permit the controlled receipt quantity increment on approved purchase order lines.
do $$
declare
 v_definition text;
 v_old text := $old$
   if lower(coalesce(v_status,''))='approved' then raise exception 'Lines cannot be inserted into or moved to an approved voucher.' using errcode='55000'; end if;
$old$;
 v_new text := $new$
   if lower(coalesce(v_status,''))='approved' then
    if not (v_parent_table='purchase_orders' and tg_op='UPDATE'
      and (to_jsonb(new)-array['received_base_quantity'])=(to_jsonb(old)-array['received_base_quantity'])) then
     raise exception 'Lines cannot be inserted into or moved to an approved voucher.' using errcode='55000';
    end if;
   end if;
$new$;
begin
 select pg_get_functiondef('public.prevent_posted_voucher_mutation()'::regprocedure) into v_definition;
 if position(v_old in v_definition)=0 then raise exception 'Approved line insert guard not found; no function was changed.'; end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end $$;
