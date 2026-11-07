-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.goods_receipt_lines add constraint goods_receipt_lines_id_tenant_uq unique(id,tenant_id);
insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
select id,'1300','Input Tax Recoverable','asset',true,true from public.organizations on conflict do nothing;
create table if not exists public.purchase_invoices(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id) on delete cascade,
 goods_receipt_id uuid not null,supplier_id uuid not null,supplier_invoice_no text not null,invoice_date date not null,due_date date,
 subtotal numeric(18,2) not null default 0 check(subtotal>=0),tax_amount numeric(18,2) not null default 0 check(tax_amount>=0),
 grand_total numeric(18,2) not null default 0 check(grand_total>=0),status text not null default 'draft' check(status in ('draft','posted','void')),
 notes text,created_by uuid references auth.users(id),posted_by uuid references auth.users(id),posted_at timestamptz,created_at timestamptz not null default now(),
 constraint purchase_invoices_grn_fk foreign key(goods_receipt_id,tenant_id) references public.goods_receipts(id,tenant_id),
 constraint purchase_invoices_supplier_fk foreign key(supplier_id,tenant_id) references public.parties(id,tenant_id),
 constraint purchase_invoices_tenant_invoice_uq unique(tenant_id,supplier_id,supplier_invoice_no),
 constraint purchase_invoices_grn_uq unique(tenant_id,goods_receipt_id),
 constraint purchase_invoices_id_tenant_uq unique(id,tenant_id)
);
create table if not exists public.purchase_invoice_lines(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id) on delete cascade,
 purchase_invoice_id uuid not null,goods_receipt_line_id uuid not null,product_id uuid not null,unit_id uuid not null,
 quantity numeric(18,4) not null check(quantity>0),unit_cost numeric(18,4) not null check(unit_cost>=0),line_total numeric(18,2) not null check(line_total>=0),
 constraint purchase_invoice_lines_invoice_fk foreign key(purchase_invoice_id,tenant_id) references public.purchase_invoices(id,tenant_id) on delete cascade,
 constraint purchase_invoice_lines_grn_line_fk foreign key(goods_receipt_line_id,tenant_id) references public.goods_receipt_lines(id,tenant_id),
 constraint purchase_invoice_lines_product_fk foreign key(product_id,tenant_id) references public.products(id,tenant_id),
 constraint purchase_invoice_lines_unit_fk foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id),
 constraint purchase_invoice_lines_grn_line_uq unique(tenant_id,goods_receipt_line_id)
);
create index if not exists purchase_invoices_tenant_date_idx on public.purchase_invoices(tenant_id,invoice_date desc);
create index if not exists purchase_invoice_lines_tenant_invoice_idx on public.purchase_invoice_lines(tenant_id,purchase_invoice_id);
alter table public.purchase_invoices enable row level security;alter table public.purchase_invoice_lines enable row level security;
grant select,insert,update on public.purchase_invoices,public.purchase_invoice_lines to authenticated;
drop policy if exists purchase_invoices_select on public.purchase_invoices;drop policy if exists purchase_invoices_insert on public.purchase_invoices;drop policy if exists purchase_invoices_update on public.purchase_invoices;drop policy if exists purchase_invoice_lines_select on public.purchase_invoice_lines;drop policy if exists purchase_invoice_lines_insert on public.purchase_invoice_lines;
create policy purchase_invoices_select on public.purchase_invoices for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase']));
create policy purchase_invoices_insert on public.purchase_invoices for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy purchase_invoices_update on public.purchase_invoices for update to authenticated using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy purchase_invoice_lines_select on public.purchase_invoice_lines for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase']));
create policy purchase_invoice_lines_insert on public.purchase_invoice_lines for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create or replace function public.create_purchase_invoice(p_goods_receipt_id uuid,p_supplier_invoice_no text,p_invoice_date date,p_due_date date,p_tax_amount numeric,p_notes text default null)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_grn public.goods_receipts%rowtype;v_supplier uuid;v_user uuid:=auth.uid();v_subtotal numeric;v_id uuid;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found or v_grn.status<>'posted' then raise exception 'Select a posted goods receipt';end if;
 if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase invoice creation permission required';end if;
 if nullif(trim(p_supplier_invoice_no),'') is null then raise exception 'Supplier invoice number is required';end if;
 if p_tax_amount is null or p_tax_amount<0 then raise exception 'Tax amount cannot be negative';end if;
 select supplier_id into v_supplier from public.purchase_orders where id=v_grn.purchase_order_id and tenant_id=v_grn.tenant_id;
 if v_supplier is null then raise exception 'Supplier could not be resolved from the purchase order';end if;
 select coalesce(sum(accepted_quantity*unit_cost),0) into v_subtotal from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0;
 if v_subtotal<=0 then raise exception 'Goods receipt has no accepted value to invoice';end if;
 insert into public.purchase_invoices(tenant_id,goods_receipt_id,supplier_id,supplier_invoice_no,invoice_date,due_date,subtotal,tax_amount,grand_total,status,notes,created_by)
 values(v_grn.tenant_id,v_grn.id,v_supplier,trim(p_supplier_invoice_no),coalesce(p_invoice_date,current_date),p_due_date,v_subtotal,p_tax_amount,v_subtotal+p_tax_amount,'draft',nullif(trim(p_notes),''),v_user)
 returning id into v_id;
 insert into public.purchase_invoice_lines(tenant_id,purchase_invoice_id,goods_receipt_line_id,product_id,unit_id,quantity,unit_cost,line_total)
 select v_grn.tenant_id,v_id,id,product_id,unit_id,accepted_quantity,unit_cost,round(accepted_quantity*unit_cost,2)
 from public.goods_receipt_lines where tenant_id=v_grn.tenant_id and goods_receipt_id=v_grn.id and accepted_quantity>0;
 return jsonb_build_object('success',true,'purchase_invoice_id',v_id,'supplier_invoice_no',trim(p_supplier_invoice_no),'subtotal',v_subtotal,'grand_total',v_subtotal+p_tax_amount);
exception when unique_violation then raise exception 'This GRN or supplier invoice number has already been invoiced';
end $$;
create or replace function public.post_purchase_invoice(p_purchase_invoice_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_inv public.purchase_invoices%rowtype;v_user uuid:=auth.uid();v_grni uuid;v_tax uuid;v_ap uuid;v_journal uuid;v_no text;v_line_total numeric;v_count integer;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_inv from public.purchase_invoices where id=p_purchase_invoice_id for update;
 if not found then raise exception 'Purchase invoice not found';end if;
 if not public.has_tenant_role(v_inv.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only accounts or management can post supplier invoices';end if;
 if v_inv.status<>'draft' then raise exception 'Only draft supplier invoices can be posted';end if;
 if not exists(select 1 from public.goods_receipts where id=v_inv.goods_receipt_id and tenant_id=v_inv.tenant_id and status='posted') then raise exception 'Linked goods receipt is not posted';end if;
 select coalesce(sum(line_total),0),count(*) into v_line_total,v_count from public.purchase_invoice_lines where tenant_id=v_inv.tenant_id and purchase_invoice_id=v_inv.id;
 if v_count=0 or abs(v_line_total-v_inv.subtotal)>0.02 then raise exception 'Invoice lines do not match the received GRN value';end if;
 select id into v_grni from public.chart_of_accounts where tenant_id=v_inv.tenant_id and account_code='2100' and is_active;
 select id into v_tax from public.chart_of_accounts where tenant_id=v_inv.tenant_id and account_code='1300' and is_active;
 select id into v_ap from public.chart_of_accounts where tenant_id=v_inv.tenant_id and account_code='2000' and is_active;
 if v_grni is null or v_tax is null or v_ap is null then raise exception 'GRNI, Input Tax and Accounts Payable accounts are required';end if;
 v_no:='EBS-PINV-JV-'||right(replace(v_inv.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_inv.tenant_id,v_no,v_inv.invoice_date,'purchase_invoice',v_inv.id,'Supplier invoice '||v_inv.supplier_invoice_no,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,party_id,debit,credit,memo)
 values(v_inv.tenant_id,v_journal,v_grni,null,v_inv.subtotal,0,'Clear goods received not invoiced'),
 (v_inv.tenant_id,v_journal,v_ap,v_inv.supplier_id,0,v_inv.grand_total,'Supplier accounts payable');
 if v_inv.tax_amount>0 then insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo) values(v_inv.tenant_id,v_journal,v_tax,v_inv.tax_amount,0,'Recoverable input tax');end if;
 update public.purchase_invoices set status='posted',posted_by=v_user,posted_at=now() where id=v_inv.id and tenant_id=v_inv.tenant_id;
 return jsonb_build_object('success',true,'status','posted','subtotal',v_inv.subtotal,'tax_amount',v_inv.tax_amount,'grand_total',v_inv.grand_total,'journal_entry_id',v_journal);
end $$;
revoke all on function public.create_purchase_invoice(uuid,text,date,date,numeric,text) from public;
revoke all on function public.post_purchase_invoice(uuid) from public;
grant execute on function public.create_purchase_invoice(uuid,text,date,date,numeric,text) to authenticated;
grant execute on function public.post_purchase_invoice(uuid) to authenticated;
