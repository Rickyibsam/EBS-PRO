CREATE OR REPLACE FUNCTION public.create_stock_take(p_tenant_id uuid, p_warehouse_id uuid, p_count_date date, p_lines jsonb, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_user uuid:=auth.uid();v_id uuid;v_number text;v_product public.products%rowtype;x record;v_expected numeric;v_cost numeric;v_count integer;v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='42501';end if;
 v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='inventory') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(p_tenant_id,'inventory','create') then raise exception 'You cannot create a physical stock take.' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(p_tenant_id,'inventory','create') then
  raise exception 'Stock take creation is disabled for this user' using errcode='42501';
 end if;
 if p_count_date is null or p_count_date>current_date then raise exception 'Stock take date cannot be in the future.'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then raise exception 'Select an active warehouse in this company.'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Load the warehouse stock snapshot before creating a count.'; end if;
 select count(*),count(distinct (z.product_id,coalesce(z.batch_number,''),coalesce(z.expiry_date,date '0001-01-01'))) into v_count,v_expected
 from jsonb_to_recordset(p_lines) z(product_id uuid,batch_number text,expiry_date date,counted_quantity numeric);
 if v_count=0 or v_count<>v_expected then raise exception 'Duplicate or missing product batch lines in stock take.'; end if;
 v_number:='ST-'||to_char(p_count_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.stock_takes(tenant_id,warehouse_id,stock_take_number,count_date,status,notes,created_by)
 values(p_tenant_id,p_warehouse_id,v_number,p_count_date,'draft',p_notes,v_user) returning id into v_id;
 for x in select * from jsonb_to_recordset(p_lines) z(product_id uuid,batch_number text,expiry_date date,counted_quantity numeric,expected_quantity numeric) loop
  if x.counted_quantity is null or x.counted_quantity<0 then raise exception 'Counted stock cannot be negative.'; end if;
  select * into v_product from public.products where id=x.product_id and tenant_id=p_tenant_id and is_active;
  if not found then raise exception 'A counted product is not active in this company.'; end if;
  if v_product.track_batch and nullif(btrim(x.batch_number),'') is null then raise exception 'Batch number is required for %.',v_product.name; end if;
  if v_product.track_expiry and x.expiry_date is null then raise exception 'Expiry date is required for %.',v_product.name; end if;
  select coalesce(sum(quantity_in-quantity_out),0),
   case when sum(quantity_in)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else coalesce(v_product.cost_price,0) end
  into v_expected,v_cost from public.stock_movements
  where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=x.product_id
   and batch_number is not distinct from nullif(btrim(x.batch_number),'') and expiry_date is not distinct from x.expiry_date;
  if v_expected<0 then raise exception 'Negative ledger stock found for product % batch %.',v_product.name,x.batch_number; end if; if x.expected_quantity is not null and abs(v_expected-x.expected_quantity)>0.000001 then raise exception 'Stock changed after the snapshot for product %. Refresh the snapshot and recount.',v_product.name; end if;
  insert into public.stock_take_lines(tenant_id,stock_take_id,product_id,batch_number,expiry_date,expected_quantity,counted_quantity,unit_cost)
  values(p_tenant_id,v_id,x.product_id,nullif(btrim(x.batch_number),''),x.expiry_date,v_expected,x.counted_quantity,greatest(v_cost,0));
 end loop;
 return v_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.get_stock_take_snapshot(p_tenant_id uuid, p_warehouse_id uuid)
 RETURNS TABLE(product_id uuid, sku text, product_name text, batch_number text, expiry_date date, expected_quantity numeric, unit_cost numeric, track_batch boolean, track_expiry boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_user uuid:=auth.uid();v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='42501';end if;
 v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='inventory') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(p_tenant_id,'inventory','view') then raise exception 'You cannot view this warehouse stock snapshot.' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(p_tenant_id,'inventory','view') then
  raise exception 'Inventory view is disabled for this user' using errcode='42501';
 end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then raise exception 'Select an active warehouse in this company.'; end if;
 return query
 select p.id,p.sku,p.name,sm.batch_number,sm.expiry_date,coalesce(sm.expected_quantity,0)::numeric,
  coalesce(sm.unit_cost,coalesce(p.cost_price,0))::numeric,p.track_batch,p.track_expiry
 from public.products p
 left join lateral(
  select x.product_id,x.batch_number,x.expiry_date,sum(x.quantity_in-x.quantity_out)::numeric expected_quantity,
   case when sum(x.quantity_in)>0 then sum(x.quantity_in*x.unit_cost)/sum(x.quantity_in) else null end::numeric unit_cost
  from public.stock_movements x
  where x.tenant_id=p_tenant_id and x.warehouse_id=p_warehouse_id and x.product_id=p.id
  group by x.product_id,x.batch_number,x.expiry_date
  having sum(x.quantity_in-x.quantity_out)>0
 ) sm on true
 where p.tenant_id=p_tenant_id and p.is_active
  and (sm.product_id is not null or (not p.track_batch and not p.track_expiry))
 order by p.name,sm.expiry_date nulls last,sm.batch_number nulls first;
end;
$function$


CREATE OR REPLACE FUNCTION public.post_stock_take(p_stock_take_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_take public.stock_takes%rowtype;x record;v_current numeric;v_variance numeric;v_count integer:=0;v_user uuid:=auth.uid();v_product public.products%rowtype;v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required.' using errcode='42501';end if;
 select * into v_take from public.stock_takes where id=p_stock_take_id for update;
 if not found then raise exception 'Stock take not found' using errcode='42501';end if;
 v_role_allowed:=public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(v_take.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_take.tenant_id and p.user_id=v_user and p.module_key='inventory') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_take.tenant_id,'inventory','update') then raise exception 'You cannot post this stock take.' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_take.tenant_id,'inventory','update') then
  raise exception 'Stock take posting is disabled for this user' using errcode='42501';
 end if;
 if v_take.status<>'draft' then raise exception 'Only draft stock takes can be posted.'; end if;
 if not exists(select 1 from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id) then raise exception 'Stock take has no count lines.'; end if;
 for x in select * from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id order by product_id,batch_number,expiry_date for update loop
  if x.counted_quantity is null or x.counted_quantity<0 or x.expected_quantity is null or x.expected_quantity<0 then
   raise exception 'Stock take line quantities are invalid';
  end if;
  select * into v_product from public.products where id=x.product_id and tenant_id=v_take.tenant_id and is_active;
  if not found then raise exception 'Stock take product is no longer active in this company'; end if;
  if v_product.track_batch and nullif(btrim(x.batch_number),'') is null then raise exception 'Batch number is required for %.',v_product.name; end if;
  if v_product.track_expiry and x.expiry_date is null then raise exception 'Expiry date is required for %.',v_product.name; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_take.tenant_id::text||'|'||v_take.warehouse_id::text||'|'||x.product_id::text,0));
  select coalesce(sum(quantity_in-quantity_out),0) into v_current from public.stock_movements
  where tenant_id=v_take.tenant_id and warehouse_id=v_take.warehouse_id and product_id=x.product_id
   and batch_number is not distinct from x.batch_number and expiry_date is not distinct from x.expiry_date;
  if abs(v_current-x.expected_quantity)>0.000001 then raise exception 'Stock changed after count began for product %. Refresh and recount before posting.',x.product_id; end if;
  v_variance:=x.counted_quantity-x.expected_quantity;
  if v_variance>0 then
   if x.expiry_date is not null and x.expiry_date<current_date then raise exception 'Expired stock cannot be added to available inventory. Record it through the damage/write-off workflow.'; end if;
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_take.tenant_id,v_take.warehouse_id,x.product_id,'adjustment','stock_take',v_take.id,v_variance,0,x.unit_cost,x.batch_number,x.expiry_date,now(),auth.uid(),'Physical stock count variance increase · '||v_take.stock_take_number);
  elsif v_variance<0 then
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_take.tenant_id,v_take.warehouse_id,x.product_id,'adjustment','stock_take',v_take.id,0,abs(v_variance),x.unit_cost,x.batch_number,x.expiry_date,now(),auth.uid(),'Physical stock count variance decrease · '||v_take.stock_take_number);
  end if;
  if v_variance<>0 then v_count:=v_count+1; end if;
 end loop;
 update public.stock_takes set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_take.id and tenant_id=v_take.tenant_id;
 return jsonb_build_object('success',true,'stock_take_number',v_take.stock_take_number,'adjusted_lines',v_count,'status','posted');
end;
$function$


CREATE OR REPLACE FUNCTION public.update_stock_take_counts(p_stock_take_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_take public.stock_takes%rowtype;x record;v_count integer;v_expected integer;v_updated integer;v_user uuid:=auth.uid();v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select * into v_take from public.stock_takes where id=p_stock_take_id for update;
 if not found then raise exception 'Stock take not found' using errcode='42501';end if;
 v_role_allowed:=public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']);
 v_is_owner_admin:=public.has_tenant_role(v_take.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_take.tenant_id and p.user_id=v_user and p.module_key='inventory') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_take.tenant_id,'inventory','update') then raise exception 'You cannot edit this stock take.' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_take.tenant_id,'inventory','update') then
  raise exception 'Stock take editing is disabled for this user' using errcode='42501';
 end if;
 if v_take.status<>'draft' then raise exception 'Only draft stock takes can be edited.'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Stock take count lines must be an array.'; end if;
 select count(*),count(distinct z.id) into v_count,v_expected from jsonb_to_recordset(p_lines) z(id uuid,counted_quantity numeric);
 if v_count=0 or v_count<>v_expected or v_count<>(select count(*) from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id) then raise exception 'Submit every stock take line exactly once.'; end if;
 for x in select * from jsonb_to_recordset(p_lines) z(id uuid,counted_quantity numeric) loop
  if x.counted_quantity is null or x.counted_quantity<0 then raise exception 'Counted quantity cannot be negative.'; end if;
  update public.stock_take_lines set counted_quantity=x.counted_quantity where id=x.id and tenant_id=v_take.tenant_id and stock_take_id=v_take.id;
  get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A stock take line does not belong to this count.'; end if;
 end loop;
 return jsonb_build_object('success',true,'lines_saved',v_count);
end;
$function$



revoke all on function public.get_stock_take_snapshot(uuid,uuid) from public,anon;
grant execute on function public.get_stock_take_snapshot(uuid,uuid) to authenticated;
revoke all on function public.create_stock_take(uuid,uuid,date,jsonb,text) from public,anon;
grant execute on function public.create_stock_take(uuid,uuid,date,jsonb,text) to authenticated;
revoke all on function public.update_stock_take_counts(uuid,jsonb) from public,anon;
grant execute on function public.update_stock_take_counts(uuid,jsonb) to authenticated;
revoke all on function public.post_stock_take(uuid) from public,anon;
grant execute on function public.post_stock_take(uuid) to authenticated;
