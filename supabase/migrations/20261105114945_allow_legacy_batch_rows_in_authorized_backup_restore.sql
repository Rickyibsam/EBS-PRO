-- A same-tenant owner/admin backup restore may restore legacy stock rows
-- whose batch/expiry metadata predates the current intake validation rules.
do $$
declare
 v_definition text;
 v_old text := $old$
 if v_track_batch and nullif(btrim(new.batch_number),'') is null then raise exception 'Batch number is required for this batch-tracked product.' using errcode='23514';end if;
 if v_track_expiry and new.expiry_date is null then raise exception 'Expiry date is required for this expiry-tracked product.' using errcode='23514';end if;
$old$;
 v_new text := $new$
 if not v_restore then
  if v_track_batch and nullif(btrim(new.batch_number),'') is null then raise exception 'Batch number is required for this batch-tracked product.' using errcode='23514';end if;
  if v_track_expiry and new.expiry_date is null then raise exception 'Expiry date is required for this expiry-tracked product.' using errcode='23514';end if;
 end if;
$new$;
begin
 select pg_get_functiondef('public.enforce_stock_batch_expiry_rules()'::regprocedure) into v_definition;
 if position(v_old in v_definition)=0 then raise exception 'Batch/expiry validation block not found; no function was changed.'; end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end $$;
