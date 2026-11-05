-- Voucher revision rows are immutable. Read them without SELECT FOR UPDATE,
-- which would require UPDATE privileges on the audit-history table.
do $$
declare d text;
begin
 select pg_get_functiondef('public.restore_draft_voucher_line_revision(uuid)'::regprocedure) into d;
 d:=replace(d,'from public.voucher_revisions where id=p_revision_id for update;','from public.voucher_revisions where id=p_revision_id;');
 execute d;
end;
$$;
