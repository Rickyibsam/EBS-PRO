-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

-- Standard, editable starter chart for this tenant. Existing account rows are never overwritten.
insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
select '2742d92f-04f5-4dea-a55e-62d1e8d6f795'::uuid,x.code,x.name,x.kind,true,true
from (values
 ('1000','Cash on Hand','asset'),
 ('1010','Bank Accounts','asset'),
 ('1100','Accounts Receivable','asset'),
 ('1200','Inventory','asset'),
 ('2000','Accounts Payable','liability'),
 ('2100','Goods Received Not Invoiced','liability'),
 ('2200','Sales Tax Payable','liability'),
 ('3000','Owner Capital','equity'),
 ('4000','Sales Revenue','income'),
 ('5000','Cost of Goods Sold','expense'),
 ('5100','Operating Expenses','expense')
) as x(code,name,kind)
where not exists(select 1 from public.chart_of_accounts c where c.tenant_id='2742d92f-04f5-4dea-a55e-62d1e8d6f795'::uuid and c.account_code=x.code);

create or replace function public.create_tenant(p_name text,p_slug text,p_city text default null,p_phone text default null)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare v_tenant_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Business name is required'; end if;
 if p_slug !~ '^[a-z0-9][a-z0-9-]{2,49}$' then raise exception 'Use a valid 3-50 character lowercase slug'; end if;
 insert into public.organizations(name,slug,city,phone)
 values(trim(p_name),lower(p_slug),nullif(trim(p_city),''),nullif(trim(p_phone),'')) returning id into v_tenant_id;
 insert into public.tenant_memberships(tenant_id,user_id,role) values(v_tenant_id,auth.uid(),'owner');
 insert into public.branches(tenant_id,name,code,is_default) values(v_tenant_id,'Main Branch','MAIN',true);
 insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
 values
 (v_tenant_id,'1000','Cash on Hand','asset',true,true),
 (v_tenant_id,'1010','Bank Accounts','asset',true,true),
 (v_tenant_id,'1100','Accounts Receivable','asset',true,true),
 (v_tenant_id,'1200','Inventory','asset',true,true),
 (v_tenant_id,'2000','Accounts Payable','liability',true,true),
 (v_tenant_id,'2100','Goods Received Not Invoiced','liability',true,true),
 (v_tenant_id,'2200','Sales Tax Payable','liability',true,true),
 (v_tenant_id,'3000','Owner Capital','equity',true,true),
 (v_tenant_id,'4000','Sales Revenue','income',true,true),
 (v_tenant_id,'5000','Cost of Goods Sold','expense',true,true),
 (v_tenant_id,'5100','Operating Expenses','expense',true,true);
 return v_tenant_id;
end;
$$;
revoke all on function public.create_tenant(text,text,text,text) from public,anon;
grant execute on function public.create_tenant(text,text,text,text) to authenticated;

create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_grn public.goods_receipts%rowtype;
 v_line record;
 v_user uuid:=auth.uid();
 v_all_received boolean;
 v_total numeric:=0;
 v_inventory_account uuid;
 v_grni_account uuid;
 v_journal_id uuid;
 v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found then raise exception 'Goods receipt not found'; end if;
 if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'You do not have permission to post goods receipts'; end if;
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
   values(v_grn.tenant_id,v_grn.warehouse_id,v_line.product_id,'purchase_receipt','goods_receipt',v_grn.id,
    v_line.accepted_quantity*v_line.conversion_to_base,0,
    case when v_line.conversion_to_base>0 then v_line.unit_cost/v_line.conversion_to_base else 0 end,
    v_line.batch_number,v_line.expiry_date,now(),v_user,'Posted from GRN '||v_grn.grn_number);
   v_total:=v_total+(v_line.accepted_quantity*v_line.unit_cost);
  end if;
  update public.purchase_order_lines set received_base_quantity=coalesce(received_base_quantity,0)+(v_line.accepted_quantity*v_line.conversion_to_base)
   where id=v_line.purchase_order_line_id and tenant_id=v_grn.tenant_id;
 end loop;
 select coalesce(bool_and(coalesce(received_base_quantity,0)>=quantity*conversion_to_base),false) into v_all_received
 from public.purchase_order_lines where tenant_id=v_grn.tenant_id and purchase_order_id=v_grn.purchase_order_id;
 update public.purchase_orders set status=case when v_all_received then 'received' else 'part_received' end,updated_at=now()
 where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id and status in ('approved','part_received');
 if v_total>0 then
  if v_inventory_account is null or v_grni_account is null then raise exception 'Default Inventory and GRNI accounts are missing. Create accounts 1200 and 2100 first.'; end if;
  v_journal_no:='EBS-GRN-JV-'||right(replace(v_grn.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_grn.tenant_id,v_journal_no,v_grn.received_date,'goods_receipt',v_grn.id,'Inventory received against GRN '||v_grn.grn_number,'posted',v_user,v_user,now())
  returning id into v_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_grn.tenant_id,v_journal_id,v_inventory_account,v_total,0,'Accepted goods received'),
        (v_grn.tenant_id,v_journal_id,v_grni_account,0,v_total,'Goods received not invoiced');
 end if;
 update public.goods_receipts set status='posted',posted_at=now() where id=v_grn.id and tenant_id=v_grn.tenant_id;
 return jsonb_build_object('success',true,'goods_receipt_id',v_grn.id,'status','posted','inventory_value',v_total);
end;
$$;
revoke all on function public.post_goods_receipt(uuid) from public,anon;
grant execute on function public.post_goods_receipt(uuid) to authenticated;

create or replace function public.dispatch_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
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
 if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager']) then raise exception 'Only an owner, admin or manager can confirm dispatch'; end if;
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
$$;
revoke all on function public.dispatch_delivery(uuid,jsonb) from public,anon;
grant execute on function public.dispatch_delivery(uuid,jsonb) to authenticated;
