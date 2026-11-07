-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.record_van_stock_transfer(
 p_tenant_id uuid,
 p_warehouse_id uuid,
 p_vehicle_number text,
 p_employee_id uuid,
 p_product_id uuid,
 p_movement_type text,
 p_quantity numeric,
 p_batch_number text default null,
 p_expiry_date date default null,
 p_idempotency_key text default null,
 p_notes text default null
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
declare
 v_user_id uuid := auth.uid();
 v_existing public.van_stock_movements%rowtype;
 v_movement public.van_stock_movements%rowtype;
 v_product public.products%rowtype;
 v_available numeric := 0;
 v_value numeric := 0;
 v_unit_cost numeric := 0;
begin
 if v_user_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
 if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
  raise exception 'You do not have permission to transfer van stock.' using errcode='42501';
 end if;
 if p_movement_type not in ('load','unload') then raise exception 'Only warehouse load and unload transfers are supported.' using errcode='22023'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero.' using errcode='22023'; end if;
 if nullif(btrim(p_vehicle_number),'') is null then raise exception 'Vehicle number is required.' using errcode='22023'; end if;
 if p_idempotency_key is null or length(btrim(p_idempotency_key))<12 then raise exception 'A unique idempotency key is required.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||'|'||p_idempotency_key,0));
 select * into v_existing from public.van_stock_movements where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('movement_id',v_existing.id,'replayed',true,'movement_type',v_existing.movement_type); end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||'|'||p_warehouse_id::text||'|'||upper(btrim(p_vehicle_number))||'|'||p_product_id::text||'|'||coalesce(p_batch_number,'')||'|'||coalesce(p_expiry_date::text,''),0));
 select * into v_product from public.products where id=p_product_id and tenant_id=p_tenant_id;
 if not found then raise exception 'Product does not belong to this tenant.' using errcode='23503'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then
  raise exception 'Warehouse does not belong to this tenant or is inactive.' using errcode='23503';
 end if;
 if p_employee_id is not null and not exists(select 1 from public.employees where id=p_employee_id and tenant_id=p_tenant_id and employment_status='active') then
  raise exception 'Delivery employee does not belong to this tenant or is inactive.' using errcode='23503';
 end if;
 if v_product.track_batch and nullif(btrim(p_batch_number),'') is null then raise exception 'Batch number is required for this product.' using errcode='23514'; end if;
 if v_product.track_expiry and p_expiry_date is null then raise exception 'Expiry date is required for this product.' using errcode='23514'; end if;
 if p_expiry_date is not null and p_expiry_date<current_date then raise exception 'Expired batch cannot be transferred.' using errcode='23514'; end if;

 if p_movement_type='load' then
  select coalesce(sum(quantity_in-quantity_out),0),
         coalesce(sum((quantity_in-quantity_out)*unit_cost),0)
    into v_available,v_value
  from public.stock_movements
  where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=p_product_id
    and batch_number is not distinct from p_batch_number
    and expiry_date is not distinct from p_expiry_date;
  if v_available<p_quantity then raise exception 'Insufficient warehouse batch stock. Available: %',v_available using errcode='23514'; end if;
  v_unit_cost:=case when v_available>0 then greatest(v_value/v_available,0) else 0 end;
  insert into public.van_stock_movements(tenant_id,vehicle_number,employee_id,product_id,movement_type,reference_type,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,idempotency_key,notes,created_by)
  values(p_tenant_id,upper(btrim(p_vehicle_number)),p_employee_id,p_product_id,'load','warehouse_transfer',p_quantity,0,v_unit_cost,p_batch_number,p_expiry_date,p_idempotency_key,p_notes,v_user_id)
  returning * into v_movement;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
  values(p_tenant_id,p_warehouse_id,p_product_id,'transfer_out','van_stock',v_movement.id,0,p_quantity,v_unit_cost,p_batch_number,p_expiry_date,now(),v_user_id,coalesce(p_notes,'Loaded into vehicle '||upper(btrim(p_vehicle_number))));
 else
  select coalesce(sum(quantity_in-quantity_out),0),
         coalesce(sum((quantity_in-quantity_out)*unit_cost),0)
    into v_available,v_value
  from public.van_stock_movements
  where tenant_id=p_tenant_id and vehicle_number=upper(btrim(p_vehicle_number)) and product_id=p_product_id
    and batch_number is not distinct from p_batch_number
    and expiry_date is not distinct from p_expiry_date;
  if v_available<p_quantity then raise exception 'Insufficient van batch stock. Available: %',v_available using errcode='23514'; end if;
  v_unit_cost:=case when v_available>0 then greatest(v_value/v_available,0) else 0 end;
  insert into public.van_stock_movements(tenant_id,vehicle_number,employee_id,product_id,movement_type,reference_type,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,idempotency_key,notes,created_by)
  values(p_tenant_id,upper(btrim(p_vehicle_number)),p_employee_id,p_product_id,'unload','warehouse_transfer',0,p_quantity,v_unit_cost,p_batch_number,p_expiry_date,p_idempotency_key,p_notes,v_user_id)
  returning * into v_movement;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
  values(p_tenant_id,p_warehouse_id,p_product_id,'transfer_in','van_stock',v_movement.id,p_quantity,0,v_unit_cost,p_batch_number,p_expiry_date,now(),v_user_id,coalesce(p_notes,'Unloaded from vehicle '||upper(btrim(p_vehicle_number))));
 end if;
 return jsonb_build_object('movement_id',v_movement.id,'replayed',false,'movement_type',v_movement.movement_type,'quantity',p_quantity,'unit_cost',v_unit_cost);
end;
$$;
revoke all on function public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text) from public, anon;
grant execute on function public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text) to authenticated;
