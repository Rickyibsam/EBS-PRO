-- Permit controlled forward status progression for approved sales and purchase orders.
-- All other approved voucher fields remain immutable.
do $$
declare
 v_definition text;
 v_old text := $old$
   if lower(coalesce(to_jsonb(old)->>'status',''))='approved' then
    if lower(coalesce(to_jsonb(new)->>'status','')) not in ('approved','posted') then raise exception 'Approved vouchers cannot return to draft or another status.' using errcode='55000'; end if;
    if (to_jsonb(new)-array['status','approved_by','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at']) then raise exception 'Approved vouchers are locked. Only posting is permitted.' using errcode='55000'; end if;
   end if;
$old$;
 v_new text := $new$
   if lower(coalesce(to_jsonb(old)->>'status',''))='approved' then
    if tg_table_name='sales_orders' then
     if lower(coalesce(to_jsonb(new)->>'status','')) not in ('approved','allocated','posted') then
      raise exception 'Approved sales orders may only progress to allocation.' using errcode='55000';
     end if;
     if (to_jsonb(new)-array['status','approved_by','updated_at','delivery_man_employee_id']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at','delivery_man_employee_id']) then
      raise exception 'Approved sales orders are locked except for controlled delivery allocation.' using errcode='55000';
     end if;
    elsif tg_table_name='purchase_orders' then
     if lower(coalesce(to_jsonb(new)->>'status','')) not in ('approved','part_received','received','posted') then
      raise exception 'Approved purchase orders may only progress through goods receipt.' using errcode='55000';
     end if;
     if (to_jsonb(new)-array['status','approved_by','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at']) then
      raise exception 'Approved purchase orders are locked except for goods-receipt status progression.' using errcode='55000';
     end if;
    else
     if lower(coalesce(to_jsonb(new)->>'status','')) not in ('approved','posted') then
      raise exception 'Approved vouchers cannot return to draft or another status.' using errcode='55000';
     end if;
     if (to_jsonb(new)-array['status','approved_by','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at']) then
      raise exception 'Approved vouchers are locked. Only posting is permitted.' using errcode='55000';
     end if;
    end if;
   end if;
$new$;
begin
 select pg_get_functiondef('public.prevent_posted_voucher_mutation()'::regprocedure) into v_definition;
 if position(v_old in v_definition)=0 then
  raise exception 'Expected approved-voucher guard block was not found; no function was changed.';
 end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end $$;
