-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.prevent_approved_budget_mutation()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public,pg_temp
as $$
declare v_budget_id uuid;v_status text;
begin
 if tg_table_name='budgets' then
  if tg_op='DELETE' and old.status in ('approved','closed') then raise exception 'Approved or closed budgets cannot be deleted.' using errcode='55000'; end if;
  if tg_op='UPDATE' and old.status in ('approved','closed') then
   if old.status='approved' and new.status='closed' and (to_jsonb(new)-array['status'])=(to_jsonb(old)-array['status']) then return new; end if;
   raise exception 'Approved or closed budgets are locked.' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
 end if;
 if tg_op<>'INSERT' then
  v_budget_id:=old.budget_id;
  select status into v_status from public.budgets where id=v_budget_id and tenant_id=old.tenant_id;
  if v_status in ('approved','closed') then raise exception 'Budget lines for approved or closed budgets cannot be changed.' using errcode='55000'; end if;
 end if;
 if tg_op<>'DELETE' then
  v_budget_id:=new.budget_id;
  select status into v_status from public.budgets where id=v_budget_id and tenant_id=new.tenant_id;
  if v_status in ('approved','closed') then raise exception 'Budget lines cannot be inserted into or moved to approved/closed budgets.' using errcode='55000'; end if;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
drop trigger if exists trg_prevent_approved_budget_mutation on public.budgets;
create trigger trg_prevent_approved_budget_mutation before update or delete on public.budgets for each row execute function public.prevent_approved_budget_mutation();
drop trigger if exists trg_prevent_approved_budget_line_mutation on public.budget_lines;
create trigger trg_prevent_approved_budget_line_mutation before insert or update or delete on public.budget_lines for each row execute function public.prevent_approved_budget_mutation();
