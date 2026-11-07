-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

CREATE OR REPLACE FUNCTION public.dispatch_delivery(p_delivery_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_delivery public.deliveries%rowtype;
 v_line public.delivery_lines%rowtype;
 v_input record;
 v_balance numeric;
 v_value numeric;
 v_cost numeric;
 v_count integer;
 v_positive integer:=0;
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
 if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can confirm dispatch'; end if;
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
   v_positive:=v_positive+1;
   perform pg_advisory_xact_lock(hashtextextended(v_delivery.tenant_id::text||':'||v_delivery.warehouse_id::text||':'||v_line.product_id::text,0));
   select coalesce(sum(quantity_in-quantity_out),0),coalesce(sum(quantity_in*unit_cost)-sum(quantity_out*unit_cost),0)
    into v_balance,v_value from public.stock_movements
    where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id;
   if v_balance<v_input.picked_quantity_base then raise exception 'Insufficient stock for product %. Available %, requested %',v_line.product_id,v_balance,v_input.picked_quantity_base; end if;
   v_cost:=case when v_balance>0 then greatest(v_value/v_balance,0) else 0 end;
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,movement_at,created_by,notes)
   values(v_delivery.tenant_id,v_delivery.warehouse_id,v_line.product_id,'sale_dispatch','delivery',v_delivery.id,0,v_input.picked_quantity_base,v_cost,now(),v_user,'Stock issued for delivery '||v_delivery.delivery_number);
   v_total_cost:=v_total_cost+(v_input.picked_quantity_base*v_cost);
  end if;
  update public.delivery_lines set picked_quantity_base=v_input.picked_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 if v_positive=0 then raise exception 'At least one product quantity must be picked'; end if;
 update public.deliveries set status='dispatched' where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 update public.sales_orders set status='dispatched',updated_at=now() where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status in ('approved','allocated');
 if v_total_cost>0 then
  select id into v_inventory_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='1200' and is_active;
  select id into v_cogs_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='5000' and is_active;
  if v_inventory_account is null or v_cogs_account is null then raise exception 'Default Inventory and Cost of Goods Sold accounts are missing. Create accounts 1200 and 5000 first.'; end if;
  v_journal_no:='EBS-DLV-JV-'||right(replace(v_delivery.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_delivery.tenant_id,v_journal_no,v_delivery.delivery_date,'delivery',v_delivery.id,'Cost of goods issued for delivery '||v_delivery.delivery_number,'posted',v_user,v_user,now())
  returning id into v_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_delivery.tenant_id,v_journal_id,v_cogs_account,v_total_cost,0,'Cost of goods sold'),
        (v_delivery.tenant_id,v_journal_id,v_inventory_account,0,v_total_cost,'Inventory issued');
 end if;
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','dispatched','cost_of_goods_sold',v_total_cost);
end;
$function$
;

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
 v_all_delivered boolean;
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
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found'; end if;
 if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can confirm delivery'; end if;
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
 select coalesce(bool_and(delivered_quantity_base=picked_quantity_base),false) into v_all_delivered
  from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if not v_all_delivered then
  return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','dispatched','message','Delivery quantities saved; complete all picked quantities to issue the invoice.');
 end if;

 if exists(select 1 from public.sales_invoices where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id) then
  raise exception 'An invoice already exists for this delivery';
 end if;

 v_invoice_no:='EBS-INV-'||right(replace(v_delivery.id::text,'-',''),10);
 insert into public.sales_invoices(tenant_id,sales_order_id,delivery_id,customer_id,invoice_number,invoice_date,subtotal,tax_total,discount_total,grand_total,status,created_by,posted_by,posted_at)
 select v_delivery.tenant_id,so.id,v_delivery.id,so.customer_id,v_invoice_no,current_date,0,0,0,0,'posted',v_user,v_user,now()
 from public.sales_orders so where so.id=v_delivery.sales_order_id and so.tenant_id=v_delivery.tenant_id
 returning id into v_invoice_id;

 for v_line in select * from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update loop
  if v_line.sales_order_line_id is null then raise exception 'Delivery line is not linked to its sales order line. Recreate the delivery with current version.'; end if;
  select * into v_order_line from public.sales_order_lines
   where id=v_line.sales_order_line_id and tenant_id=v_delivery.tenant_id and sales_order_id=v_delivery.sales_order_id;
  if not found then raise exception 'Delivery line does not match its sales order'; end if;
  if v_order_line.conversion_to_base<=0 then raise exception 'Invalid sales unit conversion'; end if;
  v_line_subtotal:=(v_line.delivered_quantity_base/v_order_line.conversion_to_base)*v_order_line.unit_price;
  v_line_tax:=v_line_subtotal*v_order_line.tax_rate/100;
  v_line_discount:=case when v_order_line.quantity>0 then v_order_line.discount_amount*(v_line.delivered_quantity_base/(v_order_line.quantity*v_order_line.conversion_to_base)) else 0 end;
  v_line_total:=v_line_subtotal+v_line_tax-v_line_discount;
  if v_line.delivered_quantity_base>0 then
   insert into public.sales_invoice_lines(tenant_id,sales_invoice_id,sales_order_line_id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total)
   values(v_delivery.tenant_id,v_invoice_id,v_order_line.id,v_order_line.product_id,v_order_line.unit_id,
    v_line.delivered_quantity_base/v_order_line.conversion_to_base,v_order_line.conversion_to_base,v_order_line.unit_price,
    v_order_line.tax_rate,v_line_discount,v_line_total);
   v_subtotal:=v_subtotal+v_line_subtotal;
   v_tax:=v_tax+v_line_tax;
   v_discount:=v_discount+v_line_discount;
  end if;
 end loop;
 if v_subtotal<=0 then raise exception 'Invoice must contain a positive delivered value'; end if;
 update public.sales_invoices set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount
  where id=v_invoice_id and tenant_id=v_delivery.tenant_id;

 select id into v_ar from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='1100' and is_active;
 select id into v_revenue from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='4000' and is_active;
 select id into v_tax_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='2200' and is_active;
 if v_ar is null or v_revenue is null or (v_tax>0 and v_tax_account is null) then raise exception 'Default Accounts Receivable, Sales Revenue or Sales Tax accounts are missing'; end if;
 v_journal_no:='EBS-INV-JV-'||right(replace(v_invoice_id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_delivery.tenant_id,v_journal_no,current_date,'sales_invoice',v_invoice_id,'Sales invoice '||v_invoice_no,'posted',v_user,v_user,now())
 returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_delivery.tenant_id,v_journal_id,v_ar,v_subtotal+v_tax-v_discount,0,'Customer receivable'),
       (v_delivery.tenant_id,v_journal_id,v_revenue,0,v_subtotal-v_discount,'Sales revenue');
 if v_tax>0 then
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_delivery.tenant_id,v_journal_id,v_tax_account,0,v_tax,'Sales tax payable');
 end if;

 update public.deliveries set status='delivered',delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 select coalesce(bool_and(coalesce(done.delivered,0)>=so_line.quantity*so_line.conversion_to_base),false)
  into v_full_order
  from public.sales_order_lines so_line
  left join lateral (
   select sum(dl.delivered_quantity_base) as delivered
   from public.delivery_lines dl join public.deliveries d on d.id=dl.delivery_id and d.tenant_id=dl.tenant_id
   where dl.tenant_id=so_line.tenant_id and dl.sales_order_line_id=so_line.id and d.status='delivered'
  ) done on true
  where so_line.tenant_id=v_delivery.tenant_id and so_line.sales_order_id=v_delivery.sales_order_id;
 update public.sales_orders set status=case when v_full_order then 'delivered' else 'dispatched' end,updated_at=now()
  where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status in ('dispatched','allocated');
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','delivered','invoice_id',v_invoice_id,'invoice_number',v_invoice_no,'invoice_total',v_subtotal+v_tax-v_discount);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.post_goods_receipt(p_goods_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_grn public.goods_receipts%rowtype; v_line record; v_user uuid:=auth.uid(); v_all_received boolean;
 v_total numeric:=0; v_inventory_account uuid; v_grni_account uuid; v_journal_id uuid; v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found then raise exception 'Goods receipt not found'; end if;
 if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can post goods receipts'; end if;
 if v_grn.status<>'draft' then raise exception 'Only draft goods receipts can be posted'; end if;
 if not exists(select 1 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0) then raise exception 'At least one accepted quantity is required'; end if;
 select id into v_inventory_account from public.chart_of_accounts where tenant_id=v_grn.tenant_id and account_code='1200' and is_active;
 select id into v_grni_account from public.chart_of_accounts where tenant_id=v_grn.tenant_id and account_code='2100' and is_active;
 for v_line in select * from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id for update loop
  if v_line.accepted_quantity+v_line.rejected_quantity>v_line.quantity then raise exception 'Accepted plus rejected quantity exceeds received quantity'; end if;
  if v_line.purchase_order_line_id is null then raise exception 'A goods receipt line is not linked to its purchase order line'; end if;
  if not exists(select 1 from public.purchase_order_lines pol where pol.id=v_line.purchase_order_line_id and pol.tenant_id=v_grn.tenant_id and pol.purchase_order_id=v_grn.purchase_order_id and pol.product_id=v_line.product_id and pol.unit_id=v_line.unit_id) then raise exception 'A goods receipt line does not match its purchase order line'; end if;
  if v_line.accepted_quantity>0 then
   perform pg_advisory_xact_lock(hashtextextended(v_grn.tenant_id::text||':'||v_grn.warehouse_id::text||':'||v_line.product_id::text,0));
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_grn.tenant_id,v_grn.warehouse_id,v_line.product_id,'purchase_receipt','goods_receipt',v_grn.id,v_line.accepted_quantity*v_line.conversion_to_base,0,v_line.unit_cost/v_line.conversion_to_base,v_line.batch_number,v_line.expiry_date,now(),v_user,'Posted from GRN '||v_grn.grn_number);
   v_total:=v_total+(v_line.accepted_quantity*v_line.unit_cost);
  end if;
  update public.purchase_order_lines set received_base_quantity=coalesce(received_base_quantity,0)+(v_line.accepted_quantity*v_line.conversion_to_base) where id=v_line.purchase_order_line_id and tenant_id=v_grn.tenant_id;
 end loop;
 select coalesce(bool_and(coalesce(received_base_quantity,0)>=quantity*conversion_to_base),false) into v_all_received from public.purchase_order_lines where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;
 update public.purchase_orders set status=case when v_all_received then 'received' else 'part_received' end,updated_at=now() where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id and status in ('approved','part_received');
 if v_total>0 then
  if v_inventory_account is null or v_grni_account is null then raise exception 'Default Inventory and GRNI accounts are missing'; end if;
  v_journal_no:='EBS-GRN-JV-'||right(replace(v_grn.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_grn.tenant_id,v_journal_no,v_grn.received_date,'goods_receipt',v_grn.id,'Inventory received against GRN '||v_grn.grn_number,'posted',v_user,v_user,now()) returning id into v_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_grn.tenant_id,v_journal_id,v_inventory_account,v_total,0,'Accepted goods received'),(v_grn.tenant_id,v_journal_id,v_grni_account,0,v_total,'Goods received not invoiced');
 end if;
 update public.goods_receipts set status='posted',posted_at=now() where id=v_grn.id and tenant_id=v_grn.tenant_id;
 return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted','inventory_value',v_total);
end;
$function$
;
