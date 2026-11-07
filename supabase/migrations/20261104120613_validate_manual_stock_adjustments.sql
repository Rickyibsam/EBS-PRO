-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.adjust_stock(
 p_tenant_id uuid,p_warehouse_id uuid,p_product_id uuid,p_direction text,
 p_quantity numeric,p_unit_cost numeric,p_batch_number text,p_expiry_date date,p_notes text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
 v_user uuid:=auth.uid();
 v_balance numeric;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
   raise exception 'You do not have permission to adjust stock';
 end if;
 if p_direction not in ('in','out') or p_quantity is null or p_quantity<=0 or p_unit_cost is null or p_unit_cost<0 then
   raise exception 'Enter a valid direction, positive quantity and non-negative cost';
 end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then
   raise exception 'Select an active warehouse';
 end if;
 if not exists(select 1 from public.products where id=p_product_id and tenant_id=p_tenant_id and is_active) then
   raise exception 'Select an active product';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_warehouse_id::text||':'||p_product_id::text,0));
 select coalesce(sum(quantity_in-quantity_out),0) into v_balance
 from public.stock_movements where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=p_product_id;
 if p_direction='out' and v_balance<p_quantity then
   raise exception 'Insufficient stock. Available %, requested %',v_balance,p_quantity;
 end if;
 insert into public.stock_movements
 (tenant_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
 values
 (p_tenant_id,p_warehouse_id,p_product_id,'adjustment',
  case when p_direction='in' then p_quantity else 0 end,
  case when p_direction='out' then p_quantity else 0 end,
  p_unit_cost,p_batch_number,p_expiry_date,now(),v_user,nullif(trim(p_notes),''));
 return jsonb_build_object('success',true,'balance_after',v_balance+case when p_direction='in' then p_quantity else -p_quantity end);
end;
$$;
revoke all on function public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text) from public,anon;
grant execute on function public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text) to authenticated;
