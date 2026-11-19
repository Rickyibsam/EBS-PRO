-- Let authorized distribution staff update only delivery-derived sales order
-- status/assignment fields without granting broad sales-order edit rights.

create or replace function public.sync_sales_order_delivery_status(
  p_tenant_id uuid,
  p_sales_order_id uuid,
  p_delivery_id uuid,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_delivery record;
  v_order_status text;
  v_allowed boolean;
  v_full_order boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_new_status not in ('allocated','dispatched','delivered') then
    raise exception 'Invalid delivery-derived sales order status' using errcode='22023';
  end if;

  if p_new_status='allocated' then
    v_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
      or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','create');
  else
    v_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
      or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','update');
  end if;
  if not v_allowed then raise exception 'Distribution delivery permission required' using errcode='42501'; end if;

  select d.id,d.status,d.route_id,d.delivery_man_employee_id
  into v_delivery
  from public.deliveries d
  where d.id=p_delivery_id and d.tenant_id=p_tenant_id and d.sales_order_id=p_sales_order_id
  for update;
  if not found then raise exception 'Delivery does not belong to the selected sales order'; end if;

  select so.status into v_order_status
  from public.sales_orders so
  where so.id=p_sales_order_id and so.tenant_id=p_tenant_id
  for update;
  if not found then raise exception 'Sales order not found'; end if;

  if p_new_status='allocated' and v_delivery.status<>'pending' then
    raise exception 'Only a pending delivery can allocate a sales order';
  elsif p_new_status='dispatched' and v_delivery.status not in ('dispatched','delivered') then
    raise exception 'Sales order can be dispatched only after delivery dispatch';
  elsif p_new_status='delivered' and v_delivery.status<>'delivered' then
    raise exception 'Sales order can be completed only after delivery completion';
  end if;

  if p_new_status='allocated' and v_order_status not in ('approved','allocated') then
    raise exception 'Sales order is not in an allocatable status';
  elsif p_new_status='dispatched' and v_order_status not in ('approved','allocated','dispatched') then
    raise exception 'Sales order is not in a dispatchable status';
  elsif p_new_status='delivered' and v_order_status not in ('approved','allocated','dispatched','delivered') then
    raise exception 'Sales order is not in a deliverable status';
  end if;

  if p_new_status='delivered' then
    if not exists(select 1 from public.sales_order_lines sol
      where sol.tenant_id=p_tenant_id and sol.sales_order_id=p_sales_order_id) then
      raise exception 'Sales order has no product lines';
    end if;
    select not exists(
      select 1 from public.sales_order_lines sol
      where sol.tenant_id=p_tenant_id and sol.sales_order_id=p_sales_order_id
        and coalesce((
          select sum(dl.delivered_quantity_base)
          from public.delivery_lines dl
          join public.deliveries d on d.id=dl.delivery_id and d.tenant_id=dl.tenant_id
          where dl.tenant_id=p_tenant_id and dl.sales_order_line_id=sol.id and d.status='delivered'
        ),0)+0.000001<sol.quantity*sol.conversion_to_base
    ) into v_full_order;
    if not v_full_order then raise exception 'Sales order still has undelivered quantities'; end if;
  end if;

  update public.sales_orders
  set status=p_new_status,
      route_id=coalesce(v_delivery.route_id,route_id),
      delivery_man_employee_id=coalesce(v_delivery.delivery_man_employee_id,delivery_man_employee_id),
      updated_at=now()
  where id=p_sales_order_id and tenant_id=p_tenant_id;

  return jsonb_build_object('success',true,'sales_order_id',p_sales_order_id,'status',p_new_status);
end
$function$;

revoke all on function public.sync_sales_order_delivery_status(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.sync_sales_order_delivery_status(uuid,uuid,uuid,text) to authenticated;


CREATE OR REPLACE FUNCTION public.dispatch_delivery(p_delivery_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_delivery public.deliveries%rowtype;
 v_line public.delivery_lines%rowtype;
 v_input record;
 v_lot record;
 v_product public.products%rowtype;
 v_count integer;
 v_positive integer:=0;
 v_remaining numeric;
 v_take numeric;
 v_total_cost numeric:=0;
 v_user uuid:=auth.uid();
 v_inventory_account uuid;
 v_cogs_account uuid;
 v_journal_id uuid;
 v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found'; end if;
 if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only an authorized distribution/warehouse user can confirm dispatch'; end if;
 if v_delivery.status not in ('pending','picked') then raise exception 'Only pending or picked deliveries can be dispatched'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Dispatch lines must be an array'; end if;
 select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a picked quantity for every delivery line'; end if;
 if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,picked_quantity_base numeric))<>v_count then raise exception 'Duplicate or missing delivery line IDs'; end if;

 for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,picked_quantity_base numeric) loop
  select * into v_line from public.delivery_lines where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
  if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
  if v_input.picked_quantity_base is null or v_input.picked_quantity_base<0 or v_input.picked_quantity_base>v_line.quantity_base then raise exception 'Picked quantity must be between zero and ordered quantity'; end if;
  if v_input.picked_quantity_base>0 then
   select * into v_product from public.products
    where id=v_line.product_id and tenant_id=v_delivery.tenant_id and is_active
    for share;
   if not found then raise exception 'Product is not active in this company.'; end if;
   v_positive:=v_positive+1;
   perform pg_advisory_xact_lock(hashtextextended(v_delivery.tenant_id::text||':'||v_delivery.warehouse_id::text||':'||v_line.product_id::text,0));
   v_remaining:=v_input.picked_quantity_base;
   for v_lot in
    with incoming as (
      select batch_number,expiry_date,min(movement_at) received_at,
             sum(quantity_in) qty_in,
             case when sum(quantity_in)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else 0 end unit_cost
      from public.stock_movements
      where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id and quantity_in>0
        and (expiry_date is null or expiry_date >= current_date)
        and (not v_product.track_expiry or expiry_date is not null)
        and (not v_product.track_batch or nullif(btrim(batch_number),'') is not null)
      group by batch_number,expiry_date
    ), batch_out as (
      select batch_number,expiry_date,sum(quantity_out) qty_out
      from public.stock_movements
      where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id and quantity_out>0 and batch_number is not null
      group by batch_number,expiry_date
    ), unbatched_out as (
      select coalesce(sum(quantity_out),0) qty_out
      from public.stock_movements
      where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id and quantity_out>0 and batch_number is null
    ), ordered_lots as (
      select i.*,coalesce(o.qty_out,0) batch_qty_out,u.qty_out unbatched_qty_out,
             coalesce(sum(i.qty_in) over(order by i.expiry_date nulls last,i.received_at rows between unbounded preceding and 1 preceding),0) prior_qty
      from incoming i left join batch_out o on o.batch_number is not distinct from i.batch_number and o.expiry_date is not distinct from i.expiry_date
      cross join unbatched_out u
    )
    select batch_number,expiry_date,unit_cost,
      greatest(0,qty_in-batch_qty_out-greatest(0,least(qty_in,unbatched_qty_out-prior_qty))) qty_available
    from ordered_lots
    where greatest(0,qty_in-batch_qty_out-greatest(0,least(qty_in,unbatched_qty_out-prior_qty)))>0
    order by expiry_date nulls last,received_at
   loop
    exit when v_remaining<=0;
    v_take:=least(v_remaining,v_lot.qty_available);
    insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
    values(v_delivery.tenant_id,v_delivery.warehouse_id,v_line.product_id,'sale_dispatch','delivery',v_delivery.id,0,v_take,v_lot.unit_cost,v_lot.batch_number,v_lot.expiry_date,now(),v_user,'FEFO stock issue for delivery '||v_delivery.delivery_number);
    v_total_cost:=v_total_cost+(v_take*v_lot.unit_cost);
    v_remaining:=v_remaining-v_take;
   end loop;
   if v_remaining>0.000001 then
     raise exception 'Insufficient available batch stock for product %. Short by % base units',v_line.product_id,v_remaining;
   end if;
  end if;
  update public.delivery_lines set picked_quantity_base=v_input.picked_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 if v_positive=0 then raise exception 'At least one product quantity must be picked'; end if;
 update public.deliveries set status='dispatched' where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 perform public.sync_sales_order_delivery_status(v_delivery.tenant_id,v_delivery.sales_order_id,v_delivery.id,'dispatched');
 if v_total_cost>0 then
  select id into v_inventory_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='1200' and is_active;
  select id into v_cogs_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='5000' and is_active;
  if v_inventory_account is null or v_cogs_account is null then raise exception 'Default Inventory and Cost of Goods Sold accounts are missing. Create accounts 1200 and 5000 first.'; end if;
  v_journal_no:='EBS-DLV-JV-'||right(replace(v_delivery.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_delivery.tenant_id,v_journal_no,v_delivery.delivery_date,'delivery',v_delivery.id,'FEFO cost of goods issued for delivery '||v_delivery.delivery_number,'posted',v_user,v_user,now()) returning id into v_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_delivery.tenant_id,v_journal_id,v_cogs_account,v_total_cost,0,'FIFO/FEFO cost of goods sold'),
        (v_delivery.tenant_id,v_journal_id,v_inventory_account,0,v_total_cost,'Inventory issued by batch');
 end if;
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','dispatched','cost_of_goods_sold',v_total_cost,'valuation_method','FEFO');
end $function$


CREATE OR REPLACE FUNCTION public.complete_delivery(p_delivery_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_delivery public.deliveries%rowtype;
 v_line public.delivery_lines%rowtype;
 v_input record;
 v_order_line public.sales_order_lines%rowtype;
 v_count integer;
 v_full_order boolean;
 v_user uuid:=auth.uid();
 v_invoice_id uuid;
 v_invoice_no text;
 v_subtotal numeric:=0;
 v_tax numeric:=0;
 v_discount numeric:=0;
 v_line_subtotal numeric;
 v_line_tax numeric;
 v_line_discount numeric;
 v_line_total numeric;
 v_ar uuid;
 v_revenue uuid;
 v_tax_account uuid;
 v_journal_id uuid;
 v_journal_no text;
 v_return record;
 v_issue record;
 v_return_remaining numeric;
 v_return_qty numeric;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found'; end if;
 if not (
  public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse'])
  OR private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')
  OR (public.has_tenant_role(v_delivery.tenant_id,array['delivery_man']) AND EXISTS (
   SELECT 1 FROM public.employees e WHERE e.id=v_delivery.delivery_man_employee_id AND e.tenant_id=v_delivery.tenant_id AND e.user_id=v_user
  ))
 ) then raise exception 'Only an authorized distribution/warehouse user or assigned delivery man can confirm delivery'; end if;
 if v_delivery.status<>'dispatched' then raise exception 'Only dispatched deliveries can be completed'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Delivery confirmation lines must be an array'; end if;
 select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a delivered quantity for every delivery line'; end if;
 if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric))<>v_count then raise exception 'Duplicate or missing delivery line IDs'; end if;
 for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric) loop
  select * into v_line from public.delivery_lines where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
  if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
  if v_input.delivered_quantity_base is null or v_input.delivered_quantity_base<0 or v_input.delivered_quantity_base>v_line.picked_quantity_base then raise exception 'Delivered quantity must be between zero and picked quantity'; end if;
  update public.delivery_lines set delivered_quantity_base=v_input.delivered_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 for v_return in select dl.product_id,sum(dl.picked_quantity_base-dl.delivered_quantity_base) return_qty
  from public.delivery_lines dl where dl.tenant_id=v_delivery.tenant_id and dl.delivery_id=v_delivery.id and not exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in ('delivery','delivery_return'))
  group by dl.product_id having sum(dl.picked_quantity_base-dl.delivered_quantity_base)>0
 loop
  v_return_remaining:=v_return.return_qty;
  for v_issue in select sm.id,sm.quantity_out,sm.unit_cost,sm.batch_number,sm.expiry_date
   from public.stock_movements sm where sm.tenant_id=v_delivery.tenant_id and sm.warehouse_id=v_delivery.warehouse_id
    and sm.product_id=v_return.product_id and sm.movement_type='sale_dispatch'
    and sm.reference_type='delivery' and sm.reference_id=v_delivery.id and sm.quantity_out>0
   order by sm.movement_at,sm.created_at,sm.id
  loop
   exit when v_return_remaining<=0.000001;
   v_return_qty:=least(v_return_remaining,v_issue.quantity_out);
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_delivery.tenant_id,v_delivery.warehouse_id,v_return.product_id,'sales_return','delivery_short_return',v_delivery.id,v_return_qty,0,v_issue.unit_cost,v_issue.batch_number,v_issue.expiry_date,now(),v_user,'Undelivered quantity returned to warehouse from delivery '||v_delivery.delivery_number);
   v_return_remaining:=v_return_remaining-v_return_qty;
  end loop;
  if v_return_remaining>0.000001 then raise exception 'Cannot return short-delivered stock for product %. Missing dispatch batch movements for % base units',v_return.product_id,v_return_remaining; end if;
 end loop;
 if exists(select 1 from public.sales_invoices where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id) then raise exception 'An invoice already exists for this delivery'; end if;
 select public.next_document_number(v_delivery.tenant_id,'sales_invoice') into v_invoice_no;
 insert into public.sales_invoices(tenant_id,sales_order_id,delivery_id,customer_id,invoice_number,invoice_date,subtotal,tax_total,discount_total,grand_total,status,created_by,posted_by,posted_at)
 select v_delivery.tenant_id,so.id,v_delivery.id,so.customer_id,v_invoice_no,current_date,0,0,0,0,'posted',v_user,v_user,now()
 from public.sales_orders so where so.id=v_delivery.sales_order_id and so.tenant_id=v_delivery.tenant_id returning id into v_invoice_id;
 for v_line in select * from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update loop
  if v_line.sales_order_line_id is null then raise exception 'Delivery line is not linked to its sales order line. Recreate the delivery with current version.'; end if;
  select * into v_order_line from public.sales_order_lines where id=v_line.sales_order_line_id and tenant_id=v_delivery.tenant_id and sales_order_id=v_delivery.sales_order_id;
  if not found then raise exception 'Delivery line does not match its sales order'; end if;
  if v_order_line.conversion_to_base<=0 then raise exception 'Invalid sales unit conversion'; end if;
  v_line_subtotal:=(v_line.delivered_quantity_base/v_order_line.conversion_to_base)*v_order_line.unit_price;
  v_line_tax:=v_line_subtotal*v_order_line.tax_rate/100;
  v_line_discount:=case when v_order_line.quantity>0 then v_order_line.discount_amount*(v_line.delivered_quantity_base/(v_order_line.quantity*v_order_line.conversion_to_base)) else 0 end;
  v_line_total:=v_line_subtotal+v_line_tax-v_line_discount;
  if v_line.delivered_quantity_base>0 then
   insert into public.sales_invoice_lines(tenant_id,sales_invoice_id,sales_order_line_id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total)
   values(v_delivery.tenant_id,v_invoice_id,v_order_line.id,v_order_line.product_id,v_order_line.unit_id,v_line.delivered_quantity_base/v_order_line.conversion_to_base,v_order_line.conversion_to_base,v_order_line.unit_price,v_order_line.tax_rate,v_line_discount,v_line_total);
   v_subtotal:=v_subtotal+v_line_subtotal;v_tax:=v_tax+v_line_tax;v_discount:=v_discount+v_line_discount;
  end if;
 end loop;
 if v_subtotal<=0 then raise exception 'Invoice must contain a positive delivered value'; end if;
 update public.sales_invoices set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount where id=v_invoice_id and tenant_id=v_delivery.tenant_id;
 select id into v_ar from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='1100' and is_active;
 select id into v_revenue from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='4000' and is_active;
 select id into v_tax_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='2200' and is_active;
 if v_ar is null or v_revenue is null or (v_tax>0 and v_tax_account is null) then raise exception 'Default Accounts Receivable, Sales Revenue or Sales Tax accounts are missing'; end if;
 v_journal_no:='EBS-INV-JV-'||right(replace(v_invoice_id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_delivery.tenant_id,v_journal_no,current_date,'sales_invoice',v_invoice_id,'Sales invoice '||v_invoice_no,'posted',v_user,v_user,now()) returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_delivery.tenant_id,v_journal_id,v_ar,v_subtotal+v_tax-v_discount,0,'Customer receivable'),(v_delivery.tenant_id,v_journal_id,v_revenue,0,v_subtotal-v_discount,'Sales revenue');
 if v_tax>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_delivery.tenant_id,v_journal_id,v_tax_account,0,v_tax,'Sales tax payable'); end if;
 update public.deliveries set status='delivered',delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 select coalesce(bool_and(coalesce(done.delivered,0)>=so_line.quantity*so_line.conversion_to_base),false) into v_full_order
 from public.sales_order_lines so_line left join lateral (
  select sum(dl.delivered_quantity_base) delivered from public.delivery_lines dl join public.deliveries d on d.id=dl.delivery_id and d.tenant_id=dl.tenant_id
  where dl.tenant_id=so_line.tenant_id and dl.sales_order_line_id=so_line.id and d.status='delivered'
 ) done on true where so_line.tenant_id=v_delivery.tenant_id and so_line.sales_order_id=v_delivery.sales_order_id;
 perform public.sync_sales_order_delivery_status(v_delivery.tenant_id,v_delivery.sales_order_id,v_delivery.id,case when v_full_order then 'delivered' else 'dispatched' end);
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','delivered','invoice_id',v_invoice_id,'invoice_number',v_invoice_no,'invoice_total',v_subtotal+v_tax-v_discount,'short_returned_to_warehouse',not exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in ('delivery','delivery_return')),'short_remaining_on_van',exists(select 1 from public.van_stock_movements vsm where vsm.tenant_id=v_delivery.tenant_id and vsm.vehicle_number=upper(v_delivery.vehicle_number) and vsm.reference_id=v_delivery.id and vsm.reference_type in ('delivery','delivery_return')));
end;$function$

