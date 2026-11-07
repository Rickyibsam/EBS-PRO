-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

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
 if current_setting('ebs.stock_transfer_posting',true) is distinct from old.id::text then
  raise exception 'Use the controlled stock transfer posting workflow';
 end if;
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
create or replace function public.post_stock_transfer(p_transfer_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_transfer public.stock_transfers%rowtype;
 v_line record;
 v_user uuid:=auth.uid();
 v_balance numeric;
 v_value numeric;
 v_cost numeric;
 v_count integer:=0;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_transfer from public.stock_transfers where id=p_transfer_id for update;
 if not found then raise exception 'Stock transfer not found'; end if;
 if not public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You do not have permission to post stock transfers'; end if;
 if v_transfer.status<>'draft' then raise exception 'Only draft stock transfers can be posted'; end if;
 if v_transfer.from_warehouse_id=v_transfer.to_warehouse_id then raise exception 'Source and destination warehouses must be different'; end if;
 if not exists(select 1 from public.stock_transfer_lines where tenant_id=v_transfer.tenant_id and stock_transfer_id=v_transfer.id) then raise exception 'Add at least one transfer line'; end if;
 for v_line in select * from public.stock_transfer_lines where tenant_id=v_transfer.tenant_id and stock_transfer_id=v_transfer.id for update loop
  if v_transfer.from_warehouse_id::text<v_transfer.to_warehouse_id::text then
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.from_warehouse_id::text||':'||v_line.product_id::text,0));
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.to_warehouse_id::text||':'||v_line.product_id::text,0));
  else
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.to_warehouse_id::text||':'||v_line.product_id::text,0));
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.from_warehouse_id::text||':'||v_line.product_id::text,0));
  end if;
  select coalesce(sum(quantity_in-quantity_out),0),coalesce(sum(quantity_in*unit_cost)-sum(quantity_out*unit_cost),0)
   into v_balance,v_value from public.stock_movements
   where tenant_id=v_transfer.tenant_id and warehouse_id=v_transfer.from_warehouse_id and product_id=v_line.product_id;
  if v_balance<v_line.quantity_base then raise exception 'Insufficient source stock for product %. Available %, requested %',v_line.product_id,v_balance,v_line.quantity_base; end if;
  v_cost:=case when v_balance>0 then greatest(v_value/v_balance,0) else 0 end;
  update public.stock_transfer_lines set unit_cost=v_cost where id=v_line.id and tenant_id=v_transfer.tenant_id;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,movement_at,created_by,notes)
  values
   (v_transfer.tenant_id,v_transfer.from_warehouse_id,v_line.product_id,'transfer_out','stock_transfer',v_transfer.id,0,v_line.quantity_base,v_cost,now(),v_user,'Transfer out '||v_transfer.transfer_number),
   (v_transfer.tenant_id,v_transfer.to_warehouse_id,v_line.product_id,'transfer_in','stock_transfer',v_transfer.id,v_line.quantity_base,0,v_cost,now(),v_user,'Transfer in '||v_transfer.transfer_number);
  v_count:=v_count+1;
 end loop;
 perform set_config('ebs.stock_transfer_posting',v_transfer.id::text,true);
 update public.stock_transfers set status='posted',posted_by=v_user,posted_at=now() where id=v_transfer.id and tenant_id=v_transfer.tenant_id;
 return jsonb_build_object('success',true,'transfer_id',v_transfer.id,'lines_posted',v_count,'status','posted');
end;
$$;
revoke all on function public.post_stock_transfer(uuid) from public,anon;
grant execute on function public.post_stock_transfer(uuid) to authenticated;
