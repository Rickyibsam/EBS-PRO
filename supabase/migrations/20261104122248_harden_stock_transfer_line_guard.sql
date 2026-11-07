-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.protect_stock_transfer_line()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public
as $$
declare v_status text;
begin
 if tg_op='DELETE' then
  select status into v_status from public.stock_transfers where id=old.stock_transfer_id and tenant_id=old.tenant_id;
 else
  select status into v_status from public.stock_transfers where id=new.stock_transfer_id and tenant_id=new.tenant_id;
 end if;
 if v_status is distinct from 'draft' then raise exception 'Lines on posted stock transfers cannot be changed'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$$;
