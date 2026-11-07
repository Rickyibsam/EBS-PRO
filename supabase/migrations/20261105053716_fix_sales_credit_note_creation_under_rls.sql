-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists sales_credit_notes_update on public.sales_credit_notes;
create policy sales_credit_notes_update on public.sales_credit_notes for update to authenticated
using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']))
with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
create or replace function public.guard_sales_credit_note_mutation()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status='draft' and new.status='draft'
   and (to_jsonb(new)-array['subtotal','tax_total','discount_total','grand_total'])=(to_jsonb(old)-array['subtotal','tax_total','discount_total','grand_total'])
 then return new;end if;
 if old.status='draft' and new.status='posted'
   and (to_jsonb(new)-array['status','posted_by','posted_at'])=(to_jsonb(old)-array['status','posted_by','posted_at'])
 then return new;end if;
 raise exception 'Sales credit notes are immutable except for controlled totals and posting';
end $$;
revoke all on function public.guard_sales_credit_note_mutation() from public,anon,authenticated;
drop trigger if exists sales_credit_note_mutation_guard on public.sales_credit_notes;
create trigger sales_credit_note_mutation_guard before update on public.sales_credit_notes for each row execute function public.guard_sales_credit_note_mutation();

create or replace function public.create_sales_credit_note(p_invoice_id uuid,p_lines jsonb,p_reason text,p_credit_note_date date default current_date)
returns uuid language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid();v_invoice public.sales_invoices%rowtype;v_line record;v_input record;v_note_id uuid;v_note_no text;v_subtotal numeric:=0;v_tax numeric:=0;v_discount numeric:=0;v_line_subtotal numeric;v_line_tax numeric;v_line_discount numeric;v_line_total numeric;v_returned numeric;v_count integer;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text,0));
 select * into v_invoice from public.sales_invoices where id=p_invoice_id;
 if not found then raise exception 'Sales invoice not found';end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) then raise exception 'You do not have permission to create a sales credit note';end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted invoices can be credited';end if;
 if p_reason is null or length(trim(p_reason))<3 then raise exception 'Enter a reason for this credit note';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Add at least one returned invoice line';end if;
 select count(*) into v_count from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean);
 if v_count=0 or (select count(distinct x.invoice_line_id) from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean))<>v_count then raise exception 'Credit note lines must contain unique invoice line IDs';end if;
 v_note_no:='EBS-CN-'||to_char(coalesce(p_credit_note_date,current_date),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.sales_credit_notes(tenant_id,sales_invoice_id,customer_id,credit_note_number,credit_note_date,reason,status,created_by)
 values(v_invoice.tenant_id,v_invoice.id,v_invoice.customer_id,v_note_no,coalesce(p_credit_note_date,current_date),trim(p_reason),'draft',v_user) returning id into v_note_id;
 for v_input in select * from jsonb_to_recordset(p_lines) as x(invoice_line_id uuid,quantity numeric,return_to_stock boolean) loop
  if v_input.quantity is null or v_input.quantity<=0 then raise exception 'Returned quantity must be greater than zero';end if;
  select * into v_line from public.sales_invoice_lines where id=v_input.invoice_line_id and tenant_id=v_invoice.tenant_id and sales_invoice_id=v_invoice.id;
  if not found then raise exception 'A selected line does not belong to this invoice';end if;
  select coalesce(sum(cnl.quantity),0) into v_returned from public.sales_credit_note_lines cnl join public.sales_credit_notes cn on cn.id=cnl.credit_note_id and cn.tenant_id=cnl.tenant_id where cnl.tenant_id=v_invoice.tenant_id and cnl.sales_invoice_line_id=v_line.id and cn.status='posted';
  if v_returned+v_input.quantity>v_line.quantity+0.000001 then raise exception 'Returned quantity exceeds the invoice quantity remaining for product %',v_line.product_id;end if;
  v_line_subtotal:=v_input.quantity*v_line.unit_price;v_line_tax:=v_line_subtotal*v_line.tax_rate/100;
  v_line_discount:=case when v_line.quantity>0 then v_line.discount_amount*(v_input.quantity/v_line.quantity) else 0 end;
  v_line_total:=v_line_subtotal+v_line_tax-v_line_discount;
  insert into public.sales_credit_note_lines(tenant_id,credit_note_id,sales_invoice_line_id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total,return_to_stock)
  values(v_invoice.tenant_id,v_note_id,v_line.id,v_line.product_id,v_line.unit_id,v_input.quantity,v_line.conversion_to_base,v_line.unit_price,v_line.tax_rate,v_line_discount,v_line_total,coalesce(v_input.return_to_stock,true));
  v_subtotal:=v_subtotal+v_line_subtotal;v_tax:=v_tax+v_line_tax;v_discount:=v_discount+v_line_discount;
 end loop;
 if v_subtotal-v_discount+v_tax<=0 then raise exception 'Credit note total must be positive';end if;
 update public.sales_credit_notes set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount where id=v_note_id and tenant_id=v_invoice.tenant_id;
 return v_note_id;
end $$;
revoke all on function public.create_sales_credit_note(uuid,jsonb,text,date) from public;
grant execute on function public.create_sales_credit_note(uuid,jsonb,text,date) to authenticated;
