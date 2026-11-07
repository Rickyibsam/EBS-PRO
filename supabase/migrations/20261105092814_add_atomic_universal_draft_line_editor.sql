-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.update_draft_voucher_lines(
 p_tenant_id uuid,p_voucher_table text,p_voucher_id uuid,p_lines jsonb
) returns jsonb
language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_status text;v_count integer;v_updated integer;v_debit numeric;v_credit numeric;v_subtotal numeric;v_tax numeric;v_discount numeric;v_grand numeric;v_tax_amount numeric;
 x record;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts','sales','warehouse']) then raise exception 'You do not have permission to edit draft voucher lines.' using errcode='42501'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Voucher lines must be submitted as an array.'; end if;

 if p_voucher_table='sales_orders' then
  select status into v_status from public.sales_orders where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft sales orders can be edited.'; end if;
  select count(*) into v_count from public.sales_order_lines where tenant_id=p_tenant_id and sales_order_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every sales order line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_price numeric,tax_rate numeric,discount_amount numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_price is null or x.unit_price<0 or coalesce(x.tax_rate,0)<0 or coalesce(x.discount_amount,0)<0 or x.discount_amount>x.quantity*x.unit_price then raise exception 'Invalid sales order quantity, price, tax or discount.'; end if;
   update public.sales_order_lines set quantity=x.quantity,unit_price=x.unit_price,tax_rate=coalesce(x.tax_rate,0),discount_amount=coalesce(x.discount_amount,0),line_total=x.quantity*x.unit_price+greatest(0,x.quantity*x.unit_price-coalesce(x.discount_amount,0))*coalesce(x.tax_rate,0)/100-coalesce(x.discount_amount,0)
    where id=x.id and tenant_id=p_tenant_id and sales_order_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A sales order line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(quantity*unit_price),0),coalesce(sum(greatest(0,quantity*unit_price-discount_amount)*tax_rate/100),0),coalesce(sum(discount_amount),0)
   into v_subtotal,v_tax,v_discount from public.sales_order_lines where tenant_id=p_tenant_id and sales_order_id=p_voucher_id;
  update public.sales_orders set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount,updated_at=now() where id=p_voucher_id and tenant_id=p_tenant_id;

 elsif p_voucher_table='purchase_orders' then
  select status into v_status from public.purchase_orders where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft purchase orders can be edited.'; end if;
  select count(*) into v_count from public.purchase_order_lines where tenant_id=p_tenant_id and purchase_order_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every purchase order line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_cost numeric,tax_rate numeric,discount_amount numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_cost is null or x.unit_cost<0 or coalesce(x.tax_rate,0)<0 or coalesce(x.discount_amount,0)<0 or x.discount_amount>x.quantity*x.unit_cost then raise exception 'Invalid purchase order quantity, cost, tax or discount.'; end if;
   update public.purchase_order_lines set quantity=x.quantity,unit_cost=x.unit_cost,tax_rate=coalesce(x.tax_rate,0),discount_amount=coalesce(x.discount_amount,0),line_total=x.quantity*x.unit_cost+greatest(0,x.quantity*x.unit_cost-coalesce(x.discount_amount,0))*coalesce(x.tax_rate,0)/100-coalesce(x.discount_amount,0)
    where id=x.id and tenant_id=p_tenant_id and purchase_order_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A purchase order line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(quantity*unit_cost),0),coalesce(sum(greatest(0,quantity*unit_cost-discount_amount)*tax_rate/100),0),coalesce(sum(discount_amount),0)
   into v_subtotal,v_tax,v_discount from public.purchase_order_lines where tenant_id=p_tenant_id and purchase_order_id=p_voucher_id;
  update public.purchase_orders set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount,updated_at=now() where id=p_voucher_id and tenant_id=p_tenant_id;

 elsif p_voucher_table='journal_entries' then
  select status into v_status from public.journal_entries where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft journal vouchers can be edited.'; end if;
  select count(*) into v_count from public.journal_lines where tenant_id=p_tenant_id and journal_entry_id=p_voucher_id;
  if v_count<2 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every journal line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,debit numeric,credit numeric,memo text) loop
   if coalesce(x.debit,0)<0 or coalesce(x.credit,0)<0 or (coalesce(x.debit,0)>0 and coalesce(x.credit,0)>0) then raise exception 'Journal line must have a non-negative debit or credit on one side only.'; end if;
   update public.journal_lines set debit=coalesce(x.debit,0),credit=coalesce(x.credit,0),memo=x.memo where id=x.id and tenant_id=p_tenant_id and journal_entry_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A journal line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(debit),0),coalesce(sum(credit),0),count(*) into v_debit,v_credit,v_count from public.journal_lines where tenant_id=p_tenant_id and journal_entry_id=p_voucher_id;
  if v_count<2 or v_debit<=0 or abs(v_debit-v_credit)>0.005 then raise exception 'Journal lines must remain balanced with equal positive debit and credit totals.'; end if;

 elsif p_voucher_table='goods_receipts' then
  select status into v_status from public.goods_receipts where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft goods receipts can be edited.'; end if;
  select count(*) into v_count from public.goods_receipt_lines where tenant_id=p_tenant_id and goods_receipt_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every goods receipt line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,accepted_quantity numeric,rejected_quantity numeric,unit_cost numeric,batch_number text,expiry_date date) loop
   if x.quantity is null or x.quantity<=0 or coalesce(x.accepted_quantity,0)<0 or coalesce(x.rejected_quantity,0)<0 or coalesce(x.accepted_quantity,0)+coalesce(x.rejected_quantity,0)>x.quantity or coalesce(x.unit_cost,0)<0 then raise exception 'Invalid received, accepted, rejected quantity or cost.'; end if;
   update public.goods_receipt_lines set quantity=x.quantity,accepted_quantity=coalesce(x.accepted_quantity,0),rejected_quantity=coalesce(x.rejected_quantity,0),unit_cost=coalesce(x.unit_cost,0),batch_number=nullif(btrim(x.batch_number),''),expiry_date=x.expiry_date where id=x.id and tenant_id=p_tenant_id and goods_receipt_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A goods receipt line does not belong to this voucher.';end if;
  end loop;

 elsif p_voucher_table='purchase_invoices' then
  select status,tax_amount into v_status,v_tax_amount from public.purchase_invoices where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft purchase invoices can be edited.'; end if;
  select count(*) into v_count from public.purchase_invoice_lines where tenant_id=p_tenant_id and purchase_invoice_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every purchase invoice line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_cost numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_cost is null or x.unit_cost<0 then raise exception 'Invalid purchase invoice quantity or cost.'; end if;
   update public.purchase_invoice_lines set quantity=x.quantity,unit_cost=x.unit_cost,line_total=x.quantity*x.unit_cost where id=x.id and tenant_id=p_tenant_id and purchase_invoice_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A purchase invoice line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(line_total),0) into v_subtotal from public.purchase_invoice_lines where tenant_id=p_tenant_id and purchase_invoice_id=p_voucher_id;
  update public.purchase_invoices set subtotal=v_subtotal,grand_total=v_subtotal+coalesce(v_tax_amount,0) where id=p_voucher_id and tenant_id=p_tenant_id;

 elsif p_voucher_table='sales_invoices' then
  select status into v_status from public.sales_invoices where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft sales invoices can be edited.'; end if;
  select count(*) into v_count from public.sales_invoice_lines where tenant_id=p_tenant_id and sales_invoice_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every sales invoice line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_price numeric,tax_rate numeric,discount_amount numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_price is null or x.unit_price<0 or coalesce(x.tax_rate,0)<0 or coalesce(x.discount_amount,0)<0 or x.discount_amount>x.quantity*x.unit_price then raise exception 'Invalid sales invoice quantity, price, tax or discount.'; end if;
   update public.sales_invoice_lines set quantity=x.quantity,unit_price=x.unit_price,tax_rate=coalesce(x.tax_rate,0),discount_amount=coalesce(x.discount_amount,0),line_total=x.quantity*x.unit_price+greatest(0,x.quantity*x.unit_price-coalesce(x.discount_amount,0))*coalesce(x.tax_rate,0)/100-coalesce(x.discount_amount,0)
    where id=x.id and tenant_id=p_tenant_id and sales_invoice_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A sales invoice line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(quantity*unit_price),0),coalesce(sum(greatest(0,quantity*unit_price-discount_amount)*tax_rate/100),0),coalesce(sum(discount_amount),0)
   into v_subtotal,v_tax,v_discount from public.sales_invoice_lines where tenant_id=p_tenant_id and sales_invoice_id=p_voucher_id;
  update public.sales_invoices set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount where id=p_voucher_id and tenant_id=p_tenant_id;

 elsif p_voucher_table='sales_credit_notes' then
  select status into v_status from public.sales_credit_notes where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft sales credit notes can be edited.'; end if;
  select count(*) into v_count from public.sales_credit_note_lines where tenant_id=p_tenant_id and credit_note_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every sales credit note line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_price numeric,tax_rate numeric,discount_amount numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_price is null or x.unit_price<0 or coalesce(x.tax_rate,0)<0 or coalesce(x.discount_amount,0)<0 or x.discount_amount>x.quantity*x.unit_price then raise exception 'Invalid credit note quantity, price, tax or discount.'; end if;
   update public.sales_credit_note_lines set quantity=x.quantity,unit_price=x.unit_price,tax_rate=coalesce(x.tax_rate,0),discount_amount=coalesce(x.discount_amount,0),line_total=x.quantity*x.unit_price+greatest(0,x.quantity*x.unit_price-coalesce(x.discount_amount,0))*coalesce(x.tax_rate,0)/100-coalesce(x.discount_amount,0)
    where id=x.id and tenant_id=p_tenant_id and credit_note_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A credit note line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(quantity*unit_price),0),coalesce(sum(greatest(0,quantity*unit_price-discount_amount)*tax_rate/100),0),coalesce(sum(discount_amount),0)
   into v_subtotal,v_tax,v_discount from public.sales_credit_note_lines where tenant_id=p_tenant_id and credit_note_id=p_voucher_id;
  update public.sales_credit_notes set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount where id=p_voucher_id and tenant_id=p_tenant_id;

 elsif p_voucher_table='purchase_debit_notes' then
  select status into v_status from public.purchase_debit_notes where id=p_voucher_id and tenant_id=p_tenant_id for update;
  if v_status is distinct from 'draft' then raise exception 'Only draft purchase debit notes can be edited.'; end if;
  select count(*) into v_count from public.purchase_debit_note_lines where tenant_id=p_tenant_id and debit_note_id=p_voucher_id;
  if v_count=0 or jsonb_array_length(p_lines)<>v_count or (select count(distinct z.id) from jsonb_to_recordset(p_lines) as z(id uuid))<>v_count then raise exception 'Submit every purchase debit note line exactly once.'; end if;
  for x in select * from jsonb_to_recordset(p_lines) as z(id uuid,quantity numeric,unit_cost numeric) loop
   if x.quantity is null or x.quantity<=0 or x.unit_cost is null or x.unit_cost<0 then raise exception 'Invalid purchase debit note quantity or cost.'; end if;
   update public.purchase_debit_note_lines set quantity=x.quantity,unit_cost=x.unit_cost,line_total=x.quantity*x.unit_cost where id=x.id and tenant_id=p_tenant_id and debit_note_id=p_voucher_id;
   get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A purchase debit note line does not belong to this voucher.';end if;
  end loop;
  select coalesce(sum(line_total),0) into v_subtotal from public.purchase_debit_note_lines where tenant_id=p_tenant_id and debit_note_id=p_voucher_id;
  update public.purchase_debit_notes set subtotal=v_subtotal where id=p_voucher_id and tenant_id=p_tenant_id;
 else
  raise exception 'Unsupported voucher type.';
 end if;
 return jsonb_build_object('success',true,'voucher_type',p_voucher_table,'voucher_id',p_voucher_id,'lines_updated',v_count);
end;
$$;
revoke all on function public.update_draft_voucher_lines(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.update_draft_voucher_lines(uuid,text,uuid,jsonb) to authenticated;
