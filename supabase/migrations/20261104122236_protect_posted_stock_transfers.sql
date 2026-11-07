-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists stock_transfers_delete on public.stock_transfers;
create policy stock_transfers_delete on public.stock_transfers for delete to authenticated
 using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));

create or replace function public.protect_stock_transfer_header()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
begin
 if tg_op='DELETE' then
  if old.status<>'draft' then raise exception 'Posted stock transfers cannot be deleted'; end if;
  return old;
 end if;
 if old.status<>'draft' then raise exception 'Posted stock transfers are immutable'; end if;
 if new.tenant_id<>old.tenant_id or new.transfer_number<>old.transfer_number
    or new.from_warehouse_id<>old.from_warehouse_id or new.to_warehouse_id<>old.to_warehouse_id
    or new.transfer_date<>old.transfer_date or coalesce(new.notes,'')<>coalesce(old.notes,'')
    or new.created_by is distinct from old.created_by then
  raise exception 'Transfer details cannot be edited during posting';
 end if;
 if new.status<>'posted' or new.posted_by is distinct from auth.uid() or new.posted_at is null then
  raise exception 'Only the controlled posting workflow can finalize a transfer';
 end if;
 return new;
end;
$$;
drop trigger if exists stock_transfer_header_protection on public.stock_transfers;
create trigger stock_transfer_header_protection before update or delete on public.stock_transfers
for each row execute function public.protect_stock_transfer_header();

create or replace function public.protect_stock_transfer_line()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public
as $$
declare v_status text;
begin
 select status into v_status from public.stock_transfers where id=coalesce(new.stock_transfer_id,old.stock_transfer_id)
  and tenant_id=coalesce(new.tenant_id,old.tenant_id);
 if v_status is distinct from 'draft' then raise exception 'Lines on posted stock transfers cannot be changed'; end if;
 return case when tg_op='DELETE' then old else new end;
end;
$$;
drop trigger if exists stock_transfer_line_protection on public.stock_transfer_lines;
create trigger stock_transfer_line_protection before update or delete on public.stock_transfer_lines
for each row execute function public.protect_stock_transfer_line();
