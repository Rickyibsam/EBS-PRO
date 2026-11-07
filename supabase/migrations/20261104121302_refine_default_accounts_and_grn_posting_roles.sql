-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

update public.chart_of_accounts
set is_control_account = account_code in ('1100','2000')
where tenant_id='2742d92f-04f5-4dea-a55e-62d1e8d6f795'::uuid
  and account_code in ('1000','1010','1100','1200','2000','2100','2200','3000','4000','5000','5100');

create or replace function public.create_tenant(p_name text,p_slug text,p_city text default null,p_phone text default null)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth
as $$
declare v_tenant_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Business name is required'; end if;
 if p_slug !~ '^[a-z0-9][a-z0-9-]{2,49}$' then raise exception 'Use a valid 3-50 character lowercase slug'; end if;
 insert into public.organizations(name,slug,city,phone) values(trim(p_name),lower(p_slug),nullif(trim(p_city),''),nullif(trim(p_phone),'')) returning id into v_tenant_id;
 insert into public.tenant_memberships(tenant_id,user_id,role) values(v_tenant_id,auth.uid(),'owner');
 insert into public.branches(tenant_id,name,code,is_default) values(v_tenant_id,'Main Branch','MAIN',true);
 insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
 values
 (v_tenant_id,'1000','Cash on Hand','asset',false,true),
 (v_tenant_id,'1010','Bank Accounts','asset',false,true),
 (v_tenant_id,'1100','Accounts Receivable','asset',true,true),
 (v_tenant_id,'1200','Inventory','asset',false,true),
 (v_tenant_id,'2000','Accounts Payable','liability',true,true),
 (v_tenant_id,'2100','Goods Received Not Invoiced','liability',false,true),
 (v_tenant_id,'2200','Sales Tax Payable','liability',false,true),
 (v_tenant_id,'3000','Owner Capital','equity',false,true),
 (v_tenant_id,'4000','Sales Revenue','income',false,true),
 (v_tenant_id,'5000','Cost of Goods Sold','expense',false,true),
 (v_tenant_id,'5100','Operating Expenses','expense',false,true);
 return v_tenant_id;
end;
$$;
create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_grn public.goods_receipts%rowtype; v_line record; v_user uuid:=auth.uid(); v_all_received boolean;
 v_total numeric:=0; v_inventory_account uuid; v_grni_account uuid; v_journal_id uuid; v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found then raise exception 'Goods receipt not found'; end if;
 if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager']) then raise exception 'Only an owner, admin or manager can post goods receipts'; end if;
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
$$;
