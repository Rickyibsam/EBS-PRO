-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

CREATE OR REPLACE FUNCTION public.post_sales_credit_note(p_credit_note_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_user uuid:=auth.uid();
 v_note public.sales_credit_notes%rowtype;
 v_invoice public.sales_invoices%rowtype;
 v_line record;
 v_returned numeric;
 v_warehouse_id uuid;
 v_cost numeric;
 v_inventory_value numeric:=0;
 v_sales_return_account uuid;
 v_tax_account uuid;
 v_ar_account uuid;
 v_inventory_account uuid;
 v_cogs_account uuid;
 v_journal_id uuid;
 v_journal_no text;
 v_stock_journal_id uuid;
 v_stock_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_note from public.sales_credit_notes where id=p_credit_note_id for update;
 if not found then raise exception 'Sales credit note not found'; end if;
 if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post a sales credit note';
 end if;
 if v_note.status<>'draft' then raise exception 'Only draft credit notes can be posted'; end if;
 select * into v_invoice from public.sales_invoices where id=v_note.sales_invoice_id and tenant_id=v_note.tenant_id for update;
 if not found or v_invoice.status<>'posted' then raise exception 'The source sales invoice is not available for crediting'; end if;

 select id into v_sales_return_account from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='4100' and is_active;
 select id into v_tax_account from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='2200' and is_active;
 select id into v_ar_account from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='1100' and is_active;
 select id into v_inventory_account from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='1200' and is_active;
 select id into v_cogs_account from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='5000' and is_active;
 if v_sales_return_account is null or v_ar_account is null or (v_note.tax_total>0 and v_tax_account is null) then
  raise exception 'Sales Returns, Accounts Receivable and Sales Tax accounts are required';
 end if;

 select d.warehouse_id into v_warehouse_id from public.deliveries d
 where d.id=v_invoice.delivery_id and d.tenant_id=v_note.tenant_id;
 for v_line in
  select cnl.*,sil.quantity as invoiced_quantity
  from public.sales_credit_note_lines cnl
  join public.sales_invoice_lines sil on sil.id=cnl.sales_invoice_line_id and sil.tenant_id=cnl.tenant_id
  where cnl.tenant_id=v_note.tenant_id and cnl.credit_note_id=v_note.id
  for update of cnl
 loop
  select coalesce(sum(other.quantity),0) into v_returned
  from public.sales_credit_note_lines other
  join public.sales_credit_notes parent on parent.id=other.credit_note_id and parent.tenant_id=other.tenant_id
  where other.tenant_id=v_note.tenant_id and other.sales_invoice_line_id=v_line.sales_invoice_line_id
    and parent.status='posted' and parent.id<>v_note.id;
  if v_returned+v_line.quantity>v_line.invoiced_quantity+0.000001 then
   raise exception 'Posted and pending returns exceed invoiced quantity for product %',v_line.product_id;
  end if;
  if v_line.return_to_stock then
   if v_warehouse_id is null then raise exception 'The original delivery warehouse could not be found'; end if;
   select coalesce(sum(sm.quantity_out*sm.unit_cost)/nullif(sum(sm.quantity_out),0),0) into v_cost
   from public.stock_movements sm
   where sm.tenant_id=v_note.tenant_id and sm.warehouse_id=v_warehouse_id
     and sm.product_id=v_line.product_id and sm.reference_type='delivery'
     and sm.reference_id=v_invoice.delivery_id and sm.movement_type='sale_dispatch';
   if v_cost<=0 then raise exception 'Original delivery cost is missing for returned product %. Use price-only credit for this line or correct the delivery cost first.',v_line.product_id; end if;
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,movement_at,created_by,notes)
   values(v_note.tenant_id,v_warehouse_id,v_line.product_id,'sales_return','sales_credit_note',v_note.id,
     v_line.quantity*v_line.conversion_to_base,0,v_cost,now(),v_user,'Customer return under credit note '||v_note.credit_note_number);
   v_inventory_value:=v_inventory_value+(v_line.quantity*v_line.conversion_to_base*v_cost);
  end if;
 end loop;

 v_journal_no:='EBS-CN-JV-'||right(replace(v_note.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_note.tenant_id,v_journal_no,v_note.credit_note_date,'sales_credit_note',v_note.id,'Sales credit note '||v_note.credit_note_number,'posted',v_user,v_user,now())
 returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_note.tenant_id,v_journal_id,v_sales_return_account,v_note.subtotal-v_note.discount_total,0,'Sales returns / customer credit'),
       (v_note.tenant_id,v_journal_id,v_ar_account,0,v_note.grand_total,'Customer receivable credited');
 if v_note.tax_total>0 then
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_note.tenant_id,v_journal_id,v_tax_account,v_note.tax_total,0,'Sales tax reversed');
 end if;

 if v_inventory_value>0 then
  if v_inventory_account is null or v_cogs_account is null then raise exception 'Inventory and Cost of Goods Sold accounts are required for returned stock'; end if;
  v_stock_journal_no:='EBS-CN-STK-JV-'||right(replace(v_note.id::text,'-',''),10);
  insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
  values(v_note.tenant_id,v_stock_journal_no,v_note.credit_note_date,'sales_return_stock',v_note.id,'Returned stock valuation for '||v_note.credit_note_number,'posted',v_user,v_user,now())
  returning id into v_stock_journal_id;
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_note.tenant_id,v_stock_journal_id,v_inventory_account,v_inventory_value,0,'Returned goods added to stock'),
        (v_note.tenant_id,v_stock_journal_id,v_cogs_account,0,v_inventory_value,'Reverse cost of returned goods');
 end if;

 perform set_config('ebs.credit_note_posting',v_note.id::text,true);
 update public.sales_credit_notes set status='posted',posted_by=v_user,posted_at=now()
 where id=v_note.id and tenant_id=v_note.tenant_id;
 return jsonb_build_object('success',true,'credit_note_id',v_note.id,'credit_note_number',v_note.credit_note_number,'grand_total',v_note.grand_total,'inventory_value',v_inventory_value,'journal_entry_id',v_journal_id);
end;
$function$
;
REVOKE ALL ON FUNCTION public.post_sales_credit_note(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.post_sales_credit_note(uuid) TO authenticated;
