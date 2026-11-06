-- A payroll run spanning multiple branches or including unassigned employees must not be attributed to one branch.
do $$
declare v_definition text;v_old text:='count(distinct e.branch_id)=1';v_new text:='count(*)=count(e.branch_id) and count(distinct e.branch_id)=1';
begin
 select pg_get_functiondef('private.assign_journal_entry_branch()'::regprocedure) into v_definition;
 if position(v_old in v_definition)=0 then raise exception 'Expected payroll branch inference expression was not found.'; end if;
 execute replace(v_definition,v_old,v_new);
end $$;
