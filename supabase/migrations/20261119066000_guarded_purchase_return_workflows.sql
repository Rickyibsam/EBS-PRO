CREATE OR REPLACE FUNCTION public.create_purchase_debit_note(p_goods_receipt_id uuid, p_lines jsonb, p_reason text, p_note_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_grn public.goods_receipts%rowtype;v_supplier uuid;v_user uuid:=auth.uid();v_note uuid;v_no text;v_input record;v_grl public.goods_receipt_lines%rowtype;v_prior numeric;v_total numeric:=0;v_count integer:=0;v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found or v_grn.status<>'posted' then raise exception 'Select a posted goods receipt';end if;
 v_role_allowed:=public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']);
 v_is_owner_admin:=public.has_tenant_role(v_grn.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_grn.tenant_id and p.user_id=v_user and p.module_key='purchase_supplier') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create') then raise exception 'Purchase return creation permission required' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create') then
  raise exception 'Purchase return creation is disabled for this user' using errcode='42501';
 end if;
 if nullif(trim(p_reason),'') is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Return reason and at least one line are required';end if;
 select supplier_id into v_supplier from public.purchase_orders where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id;
 v_no:='EBS-PR-'||right(replace(gen_random_uuid()::text,'-',''),10);
 insert into public.purchase_debit_notes(tenant_id,goods_receipt_id,supplier_id,warehouse_id,debit_note_number,note_date,reason,status,created_by)
 values(v_grn.tenant_id,v_grn.id,v_supplier,v_grn.warehouse_id,v_no,coalesce(p_note_date,current_date),trim(p_reason),'draft',v_user) returning id into v_note;
 for v_input in select * from jsonb_to_recordset(p_lines) as x(goods_receipt_line_id uuid,quantity numeric) loop
  select * into v_grl from public.goods_receipt_lines where id=v_input.goods_receipt_line_id and tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id for update;
  if not found then raise exception 'A selected return line does not belong to this GRN';end if;
  if v_input.quantity is null or v_input.quantity<=0 then raise exception 'Return quantity must be greater than zero';end if;
  select coalesce(sum(l.quantity),0) into v_prior from public.purchase_debit_note_lines l join public.purchase_debit_notes h on h.id=l.debit_note_id and h.tenant_id=l.tenant_id where l.tenant_id=v_grn.tenant_id and l.goods_receipt_line_id=v_grl.id and h.status in ('draft','posted');
  if v_prior+v_input.quantity>v_grl.accepted_quantity then raise exception 'Return quantity exceeds accepted GRN quantity for product %',v_grl.product_id;end if;
  insert into public.purchase_debit_note_lines(tenant_id,debit_note_id,goods_receipt_line_id,product_id,quantity,quantity_base,unit_cost,batch_number,expiry_date,line_total)
  values(v_grn.tenant_id,v_note,v_grl.id,v_grl.product_id,v_input.quantity,v_input.quantity*v_grl.conversion_to_base,v_grl.unit_cost/v_grl.conversion_to_base,v_grl.batch_number,v_grl.expiry_date,round(v_input.quantity*v_grl.unit_cost,2));
  v_total:=v_total+round(v_input.quantity*v_grl.unit_cost,2);v_count:=v_count+1;
 end loop;
 if v_count=0 then raise exception 'No valid return lines were supplied';end if;
 update public.purchase_debit_notes set subtotal=v_total where id=v_note and tenant_id=v_grn.tenant_id;
 return jsonb_build_object('success',true,'debit_note_id',v_note,'debit_note_number',v_no,'subtotal',v_total);
end $function$


CREATE OR REPLACE FUNCTION public.post_purchase_debit_note(p_debit_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_note public.purchase_debit_notes%rowtype;v_user uuid:=auth.uid();v_line record;v_lot_balance numeric;v_inventory uuid;v_ap uuid;v_journal uuid;v_no text;v_receipt_line public.goods_receipt_lines%rowtype;v_prior_returned numeric;v_received_base numeric;v_role_allowed boolean;v_is_owner_admin boolean;v_has_override boolean;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_note from public.purchase_debit_notes where id=p_debit_note_id for update;
 if not found then raise exception 'Purchase debit note not found';end if;
 v_role_allowed:=public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts','warehouse','purchase']);
 v_is_owner_admin:=public.has_tenant_role(v_note.tenant_id,array['owner','admin']);
 select exists(select 1 from public.tenant_user_module_permissions p where p.tenant_id=v_note.tenant_id and p.user_id=v_user and p.module_key='purchase_supplier') into v_has_override;
 if not v_role_allowed then
  if not private.module_permission_grant_internal(v_note.tenant_id,'purchase_supplier','update') then raise exception 'Purchase return posting permission required' using errcode='42501';end if;
 elsif not v_is_owner_admin and v_has_override and not private.module_permission_grant_internal(v_note.tenant_id,'purchase_supplier','update') then
  raise exception 'Purchase return posting is disabled for this user' using errcode='42501';
 end if;
 if v_note.status<>'draft' then raise exception 'Only draft purchase returns can be posted';end if;
 if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and supplier_id=v_note.supplier_id and status='posted') then raise exception 'Post the matched supplier invoice for this supplier and goods receipt before posting its purchase return';end if;
 if not exists(select 1 from public.goods_receipts where tenant_id=v_note.tenant_id and id=v_note.goods_receipt_id and warehouse_id=v_note.warehouse_id) then raise exception 'Purchase return warehouse must match its source goods receipt';end if;
 if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 if exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id and (quantity_base<=0 or line_total<0)) then raise exception 'Purchase return lines must have positive quantities and non-negative values';end if;
 if abs(coalesce((select sum(line_total) from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id),0)-coalesce(v_note.subtotal,0))>0.01 then raise exception 'Purchase return header subtotal must equal the sum of its line totals';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id loop
  select * into v_receipt_line from public.goods_receipt_lines where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and id=v_line.goods_receipt_line_id for update;
  if not found then raise exception 'Every purchase return line must reference a line from its source goods receipt';end if;
  if v_receipt_line.product_id is distinct from v_line.product_id or v_receipt_line.batch_number is distinct from v_line.batch_number or v_receipt_line.expiry_date is distinct from v_line.expiry_date then raise exception 'Purchase return product, batch and expiry must match the source goods receipt line';end if;
  v_received_base:=coalesce(v_receipt_line.accepted_quantity,0)*coalesce(v_receipt_line.conversion_to_base,1);
  select coalesce(sum(l.quantity_base),0) into v_prior_returned
  from public.purchase_debit_note_lines l join public.purchase_debit_notes n on n.id=l.debit_note_id and n.tenant_id=l.tenant_id
  where l.tenant_id=v_note.tenant_id and l.goods_receipt_line_id=v_receipt_line.id and n.status='posted';
  if v_prior_returned+v_line.quantity_base>v_received_base+0.000001 then raise exception 'Return quantity exceeds accepted source receipt quantity. Received %, previously returned %, requested %',v_received_base,v_prior_returned,v_line.quantity_base;end if;
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));
  with incoming as (
   select batch_number,expiry_date,min(movement_at) received_at,sum(quantity_in) qty_in,
          case when sum(quantity_in)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else 0 end unit_cost
   from public.stock_movements where tenant_id=v_note.tenant_id and warehouse_id=v_note.warehouse_id and product_id=v_line.product_id and quantity_in>0
   group by batch_number,expiry_date
  ),batch_out as (
   select batch_number,expiry_date,sum(quantity_out) qty_out from public.stock_movements
   where tenant_id=v_note.tenant_id and warehouse_id=v_note.warehouse_id and product_id=v_line.product_id and quantity_out>0 and batch_number is not null
   group by batch_number,expiry_date
  ),unbatched_out as (
   select coalesce(sum(quantity_out),0) qty_out from public.stock_movements
   where tenant_id=v_note.tenant_id and warehouse_id=v_note.warehouse_id and product_id=v_line.product_id and quantity_out>0 and batch_number is null
  ),ordered_lots as (
   select i.*,coalesce(o.qty_out,0) batch_qty_out,u.qty_out unbatched_qty_out,
    coalesce(sum(i.qty_in) over(order by i.expiry_date nulls last,i.received_at rows between unbounded preceding and 1 preceding),0) prior_qty
   from incoming i left join batch_out o on o.batch_number is not distinct from i.batch_number and o.expiry_date is not distinct from i.expiry_date cross join unbatched_out u
  )
  select greatest(0,qty_in-batch_qty_out-greatest(0,least(qty_in,unbatched_qty_out-prior_qty))) into v_lot_balance
  from ordered_lots where batch_number is not distinct from v_line.batch_number and expiry_date is not distinct from v_line.expiry_date;
  if coalesce(v_lot_balance,0)+0.000001<v_line.quantity_base then raise exception 'Insufficient stock in source batch % for product %. Available %, return requested %',coalesce(v_line.batch_number,'(unbatched)'),v_line.product_id,coalesce(v_lot_balance,0),v_line.quantity_base;end if;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
  values(v_note.tenant_id,v_note.warehouse_id,v_line.product_id,'purchase_return','purchase_debit_note',v_note.id,0,v_line.quantity_base,v_line.unit_cost,v_line.batch_number,v_line.expiry_date,now(),v_user,'Returned to supplier on debit note '||v_note.debit_note_number);
 end loop;
 select id into v_inventory from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='1200' and is_active;
 select id into v_ap from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='2000' and is_active;
 if v_inventory is null or v_ap is null then raise exception 'Inventory and Accounts Payable control accounts are required';end if;
 v_no:='EBS-PRET-JV-'||right(replace(v_note.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_note.tenant_id,v_no,v_note.note_date,'purchase_return',v_note.id,'Purchase return '||v_note.debit_note_number,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,party_id,debit,credit,memo)
 values(v_note.tenant_id,v_journal,v_ap,v_note.supplier_id,v_note.subtotal,0,'Supplier debit note / AP reduction'),
 (v_note.tenant_id,v_journal,v_inventory,null,0,v_note.subtotal,'Inventory returned to supplier');
 update public.purchase_debit_notes set status='posted',posted_by=v_user,posted_at=now() where id=v_note.id and tenant_id=v_note.tenant_id;
 return jsonb_build_object('success',true,'status','posted','returned_value',v_note.subtotal,'journal_entry_id',v_journal);
end $function$



revoke all on function public.create_purchase_debit_note(uuid,jsonb,text,date) from public,anon;
grant execute on function public.create_purchase_debit_note(uuid,jsonb,text,date) to authenticated;
revoke all on function public.post_purchase_debit_note(uuid) from public,anon;
grant execute on function public.post_purchase_debit_note(uuid) to authenticated;
