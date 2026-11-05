-- Allow only the draft-to-approved/approved-to-closed status workflow to update timestamps.
do $$
declare d text;
begin
 select pg_get_functiondef('public.prevent_approved_budget_mutation()'::regprocedure) into d;
 d:=replace(d,'(to_jsonb(new)-array[''status''])=(to_jsonb(old)-array[''status''])','(to_jsonb(new)-array[''status'',''updated_at''])=(to_jsonb(old)-array[''status'',''updated_at''])');
 execute d;
end;
$$;
