-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.post_purchase_debit_note(p_debit_note_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_note public.purchase_debit_notes%rowtype;v_user uuid:=auth.uid();v_line record;v_lot_balance numeric;v_inventory uuid;v_ap uuid;v_journal uuid;v_no text;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_note from public.purchase_debit_notes where id=p_debit_note_id for update;
 if not found then raise exception 'Purchase debit note not found';end if;
 if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts','warehouse']) then raise exception 'Purchase return posting permission required';end if;
 if v_note.status<>'draft' then raise exception 'Only draft purchase returns can be posted';end if;
 if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and status='posted') then raise exception 'Post the matched supplier invoice before posting its purchase return';end if;
 if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id for update loop
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
end $$;

create or replace function public.record_party_payment(p_party_id uuid,p_payment_type text,p_amount numeric,p_method text,p_reference_no text,p_notes text,p_payment_date date,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_invoice public.purchase_invoices%rowtype;v_paid numeric;v_credits numeric;v_outstanding numeric;v_result jsonb;v_payment uuid;v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required';end if;
 if p_purchase_invoice_id is null then return public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);end if;
 if p_payment_type<>'payment' then raise exception 'Only supplier payments can be allocated to a supplier invoice';end if;
 select * into v_invoice from public.purchase_invoices where id=p_purchase_invoice_id for update;
 if not found or v_invoice.supplier_id<>p_party_id then raise exception 'Supplier invoice does not belong to the selected supplier';end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted supplier invoices can receive payments';end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Supplier payment permission required';end if;
 select coalesce(sum(amount),0) into v_paid from public.payments where tenant_id=v_invoice.tenant_id and purchase_invoice_id=v_invoice.id and payment_type='payment';
 select coalesce(sum(subtotal),0) into v_credits from public.purchase_debit_notes where tenant_id=v_invoice.tenant_id and goods_receipt_id=v_invoice.goods_receipt_id and status='posted';
 v_outstanding:=greatest(v_invoice.grand_total-v_paid-v_credits,0);
 if p_amount<=0 or p_amount>v_outstanding+0.005 then raise exception 'Payment exceeds the supplier invoice outstanding balance. Outstanding amount: %',v_outstanding;end if;
 v_result:=public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);
 v_payment:=(v_result->>'payment_id')::uuid;
 update public.payments set purchase_invoice_id=v_invoice.id where id=v_payment and tenant_id=v_invoice.tenant_id;
 return v_result||jsonb_build_object('purchase_invoice_id',v_invoice.id,'allocated_amount',p_amount,'outstanding',greatest(0,v_outstanding-p_amount));
end $$;
revoke all on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) from public;
grant execute on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) to authenticated;
