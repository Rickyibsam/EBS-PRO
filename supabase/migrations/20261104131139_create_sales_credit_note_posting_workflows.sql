-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.create_sales_credit_note(
 p_invoice_id uuid,
 p_lines jsonb,
 p_reason text,
 p_credit_note_date date default current_date
) returns uuid
language plpgsql
set search_path = pg_catalog, public, auth
as $$
declare
 v_user uuid:=auth.uid();
 v_invoice public.sales_invoices%rowtype;
 v_line record;
 v_input record;
 v_note_id uuid;
 v_note_no text;
 v_subtotal numeric:=0;
 v_tax numeric:=0;
 v_discount numeric:=0;
 v_line_subtotal numeric;
 v_line_tax numeric;
 v_line_discount numeric;
 v_line_total numeric;
 v_returned numeric;
 v_count integer;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_invoice from public.sales_invoices where id=p_invoice_id for update;
 if not found then raise exception 'Sales invoice not found'; end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) then
  raise exception 'You do not have permission to create a sales credit note';
 end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted invoices can be credited'; end if;
 if p_reason is null or length(trim(p_reason))<3 then raise exception 'Enter a reason for this credit note'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Add at least one returned invoice line'; end if;
 select count(*) into v_count from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean);
 if v_count=0 or (select count(distinct x.invoice_line_id) from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean))<>v_count then
  raise exception 'Credit note lines must contain unique invoice line IDs';
 end if;

 v_note_no:='EBS-CN-'||to_char(coalesce(p_credit_note_date,current_date),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.sales_credit_notes(tenant_id,sales_invoice_id,customer_id,credit_note_number,credit_note_date,reason,status,created_by)
 values(v_invoice.tenant_id,v_invoice.id,v_invoice.customer_id,v_note_no,coalesce(p_credit_note_date,current_date),trim(p_reason),'draft',v_user)
 returning id into v_note_id;

 for v_input in select * from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean) loop
  if v_input.quantity is null or v_input.quantity<=0 then raise exception 'Returned quantity must be greater than zero'; end if;
  select * into v_line from public.sales_invoice_lines
   where id=v_input.invoice_line_id and tenant_id=v_invoice.tenant_id and sales_invoice_id=v_invoice.id for update;
  if not found then raise exception 'A selected line does not belong to this invoice'; end if;
  select coalesce(sum(cnl.quantity),0) into v_returned
   from public.sales_credit_note_lines cnl
   join public.sales_credit_notes cn on cn.id=cnl.credit_note_id and cn.tenant_id=cnl.tenant_id
   where cnl.tenant_id=v_invoice.tenant_id and cnl.sales_invoice_line_id=v_line.id and cn.status='posted';
  if v_returned+v_input.quantity>v_line.quantity+0.000001 then
   raise exception 'Returned quantity exceeds the invoice quantity remaining for product %',v_line.product_id;
  end if;
  v_line_subtotal:=v_input.quantity*v_line.unit_price;
  v_line_tax:=v_line_subtotal*v_line.tax_rate/100;
  v_line_discount:=case when v_line.quantity>0 then v_line.discount_amount*(v_input.quantity/v_line.quantity) else 0 end;
  v_line_total:=v_line_subtotal+v_line_tax-v_line_discount;
  insert into public.sales_credit_note_lines(tenant_id,credit_note_id,sales_invoice_line_id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total,return_to_stock)
  values(v_invoice.tenant_id,v_note_id,v_line.id,v_line.product_id,v_line.unit_id,v_input.quantity,v_line.conversion_to_base,v_line.unit_price,v_line.tax_rate,v_line_discount,v_line_total,coalesce(v_input.return_to_stock,true));
  v_subtotal:=v_subtotal+v_line_subtotal;
  v_tax:=v_tax+v_line_tax;
  v_discount:=v_discount+v_line_discount;
 end loop;
 if v_subtotal-v_discount+v_tax<=0 then raise exception 'Credit note total must be positive'; end if;
 update public.sales_credit_notes set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount
 where id=v_note_id and tenant_id=v_invoice.tenant_id;
 return v_note_id;
end;
$$;

create or replace function public.post_sales_credit_note(p_credit_note_id uuid)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, auth
as $$
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
$$;

create or replace function private.protect_sales_credit_note_header()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
 if tg_op='DELETE' then
  if old.status='posted' then raise exception 'Posted credit notes cannot be deleted'; end if;
  return old;
 end if;
 if old.status='posted' then raise exception 'Posted credit notes cannot be modified'; end if;
 if new.status='posted' and current_setting('ebs.credit_note_posting',true) is distinct from old.id::text then
  raise exception 'Use the controlled credit note posting workflow';
 end if;
 return new;
end;
$$;

create or replace function private.protect_sales_credit_note_line()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare v_status text;
begin
 if tg_op='INSERT' then
  select status into v_status from public.sales_credit_notes where id=new.credit_note_id and tenant_id=new.tenant_id;
  if v_status is distinct from 'draft' then raise exception 'Credit note lines can only be added to draft notes'; end if;
  return new;
 end if;
 select status into v_status from public.sales_credit_notes where id=old.credit_note_id and tenant_id=old.tenant_id;
 if v_status='posted' then raise exception 'Posted credit note lines cannot be modified'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$$;

drop trigger if exists sales_credit_note_header_protection on public.sales_credit_notes;
create trigger sales_credit_note_header_protection before update or delete on public.sales_credit_notes for each row execute function private.protect_sales_credit_note_header();
drop trigger if exists sales_credit_note_line_protection on public.sales_credit_note_lines;
create trigger sales_credit_note_line_protection before insert or update or delete on public.sales_credit_note_lines for each row execute function private.protect_sales_credit_note_line();

grant execute on function public.create_sales_credit_note(uuid,jsonb,text,date) to authenticated;
grant execute on function public.post_sales_credit_note(uuid) to authenticated;
