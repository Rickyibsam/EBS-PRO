CREATE OR REPLACE FUNCTION public.adjust_stock(p_tenant_id uuid, p_warehouse_id uuid, p_product_id uuid, p_direction text, p_quantity numeric, p_unit_cost numeric, p_batch_number text, p_expiry_date date, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
 v_user uuid:=auth.uid();
 v_balance numeric;
 v_product public.products%rowtype;
 v_cost numeric;
 v_batch text;
 v_expiry date;
 v_role_allowed boolean;
 v_is_owner_admin boolean;
 v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='inventory') into v_has_override;
 if not v_role_allowed then
   if not private.module_permission_grant_internal(p_tenant_id,'inventory','create') then raise exception 'You do not have permission to adjust stock' using errcode='42501'; end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(p_tenant_id,'inventory','create') then
   raise exception 'Stock adjustment creation is disabled for this user' using errcode='42501';
 end if;
 if p_direction not in ('in','out') or p_quantity is null or p_quantity<=0 or p_unit_cost is null or p_unit_cost<0 then
   raise exception 'Enter a valid direction, positive quantity and non-negative cost';
 end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then
   raise exception 'Select an active warehouse';
 end if;
 select * into v_product from public.products where id=p_product_id and tenant_id=p_tenant_id and is_active;
 if not found then raise exception 'Select an active product'; end if;
 v_batch:=nullif(trim(p_batch_number),'');
 v_expiry:=p_expiry_date;
 if v_product.track_batch and v_batch is null then raise exception 'Batch number is required for this product'; end if;
 if v_product.track_expiry and v_expiry is null then raise exception 'Expiry date is required for this product'; end if;
 if not v_product.track_batch then v_batch:=null; end if;
 if not v_product.track_expiry then v_expiry:=null; end if;
 if p_direction='in' and v_expiry is not null and v_expiry<current_date then
   raise exception 'Expired stock cannot be added to available inventory';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_warehouse_id::text||':'||p_product_id::text,0));
 select coalesce(sum(quantity_in-quantity_out),0) into v_balance
 from public.stock_movements
 where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=p_product_id
   and batch_number is not distinct from v_batch and expiry_date is not distinct from v_expiry;
 if p_direction='out' and v_balance<p_quantity then
   raise exception 'Insufficient stock in selected batch. Available %, requested %',v_balance,p_quantity;
 end if;
 if p_direction='out' then
   select case when coalesce(sum(quantity_in),0)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else p_unit_cost end
   into v_cost
   from public.stock_movements
   where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=p_product_id
     and batch_number is not distinct from v_batch and expiry_date is not distinct from v_expiry
     and quantity_in>0;
 else
   v_cost:=p_unit_cost;
 end if;
 insert into public.stock_movements
 (tenant_id,warehouse_id,product_id,movement_type,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
 values
 (p_tenant_id,p_warehouse_id,p_product_id,'adjustment',
  case when p_direction='in' then p_quantity else 0 end,
  case when p_direction='out' then p_quantity else 0 end,
  coalesce(v_cost,0),v_batch,v_expiry,now(),v_user,nullif(trim(p_notes),''));
 return jsonb_build_object('success',true,'balance_after',v_balance+case when p_direction='in' then p_quantity else -p_quantity end);
end;
$function$


revoke all on function public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text) from public,anon;
grant execute on function public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text) to authenticated;
