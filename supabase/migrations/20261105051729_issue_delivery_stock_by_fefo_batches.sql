-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.dispatch_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $$
declare
 v_delivery public.deliveries%rowtype;
 v_line public.delivery_lines%rowtype;
 v_input record;
 v_lot record;
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
   v_remaining:=v_input.picked_quantity_base;
   for v_lot in
    with incoming as (
      select batch_number,expiry_date,min(movement_at) received_at,
             sum(quantity_in) qty_in,
             case when sum(quantity_in)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else 0 end unit_cost
      from public.stock_movements
      where tenant_id=v_delivery.tenant_id and warehouse_id=v_delivery.warehouse_id and product_id=v_line.product_id and quantity_in>0
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
 update public.sales_orders set status='dispatched',updated_at=now() where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status in ('approved','allocated');
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
end $$;
