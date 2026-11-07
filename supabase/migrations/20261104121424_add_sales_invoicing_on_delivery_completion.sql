-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.sales_order_lines
 add column if not exists invoice_note text;

create unique index if not exists sales_order_lines_id_tenant_uidx
 on public.sales_order_lines(id,tenant_id);

alter table public.delivery_lines
 add column if not exists sales_order_line_id uuid;

do $$
begin
 if not exists(select 1 from pg_constraint where conname='delivery_lines_sales_line_tenant_fkey' and conrelid='public.delivery_lines'::regclass) then
  alter table public.delivery_lines add constraint delivery_lines_sales_line_tenant_fkey
   foreign key(sales_order_line_id,tenant_id) references public.sales_order_lines(id,tenant_id);
 end if;
end $$;

create table if not exists public.sales_invoices(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 sales_order_id uuid not null,
 delivery_id uuid not null,
 customer_id uuid not null,
 invoice_number text not null,
 invoice_date date not null default current_date,
 due_date date,
 subtotal numeric not null default 0,
 tax_total numeric not null default 0,
 discount_total numeric not null default 0,
 grand_total numeric not null default 0,
 status text not null default 'posted' check(status in ('posted','cancelled')),
 created_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 created_at timestamptz not null default now(),
 unique(tenant_id,invoice_number),
 unique(tenant_id,delivery_id),
 unique(id,tenant_id),
 foreign key(sales_order_id,tenant_id) references public.sales_orders(id,tenant_id),
 foreign key(delivery_id,tenant_id) references public.deliveries(id,tenant_id),
 foreign key(customer_id,tenant_id) references public.parties(id,tenant_id)
);
create table if not exists public.sales_invoice_lines(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 sales_invoice_id uuid not null,
 sales_order_line_id uuid,
 product_id uuid not null,
 unit_id uuid not null,
 quantity numeric not null check(quantity>0),
 conversion_to_base numeric not null check(conversion_to_base>0),
 unit_price numeric not null check(unit_price>=0),
 tax_rate numeric not null default 0,
 discount_amount numeric not null default 0,
 line_total numeric not null,
 created_at timestamptz not null default now(),
 foreign key(sales_invoice_id,tenant_id) references public.sales_invoices(id,tenant_id) on delete cascade,
 foreign key(sales_order_line_id,tenant_id) references public.sales_order_lines(id,tenant_id),
 foreign key(product_id,tenant_id) references public.products(id,tenant_id),
 foreign key(unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);
alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_lines enable row level security;
drop policy if exists sales_invoices_read on public.sales_invoices;
create policy sales_invoices_read on public.sales_invoices for select to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','cashier']));
drop policy if exists sales_invoices_insert on public.sales_invoices;
create policy sales_invoices_insert on public.sales_invoices for insert to authenticated
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager']));
drop policy if exists sales_invoice_lines_read on public.sales_invoice_lines;
create policy sales_invoice_lines_read on public.sales_invoice_lines for select to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','cashier']));
drop policy if exists sales_invoice_lines_insert on public.sales_invoice_lines;
create policy sales_invoice_lines_insert on public.sales_invoice_lines for insert to authenticated
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager']));

create index if not exists sales_invoices_tenant_date_idx on public.sales_invoices(tenant_id,invoice_date desc);
create index if not exists sales_invoice_lines_tenant_invoice_idx on public.sales_invoice_lines(tenant_id,sales_invoice_id);

create or replace function public.complete_delivery(p_delivery_id uuid,p_lines jsonb)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_delivery public.deliveries%rowtype;
 v_line public.delivery_lines%rowtype;
 v_input record;
 v_order_line public.sales_order_lines%rowtype;
 v_count integer;
 v_all_delivered boolean;
 v_full_order boolean;
 v_user uuid:=auth.uid();
 v_invoice_id uuid;
 v_invoice_no text;
 v_subtotal numeric:=0;
 v_tax numeric:=0;
 v_discount numeric:=0;
 v_line_subtotal numeric;
 v_line_tax numeric;
 v_line_discount numeric;
 v_line_total numeric;
 v_ar uuid;
 v_revenue uuid;
 v_tax_account uuid;
 v_journal_id uuid;
 v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found'; end if;
 if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager']) then raise exception 'Only an owner, admin or manager can confirm delivery'; end if;
 if v_delivery.status<>'dispatched' then raise exception 'Only dispatched deliveries can be completed'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Delivery confirmation lines must be an array'; end if;
 select count(*) into v_count from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if v_count=0 or jsonb_array_length(p_lines)<>v_count then raise exception 'Provide a delivered quantity for every delivery line'; end if;
 if (select count(distinct x.line_id) from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric))<>v_count then raise exception 'Duplicate or missing delivery line IDs'; end if;
 for v_input in select * from jsonb_to_recordset(p_lines) as x(line_id uuid,delivered_quantity_base numeric) loop
  select * into v_line from public.delivery_lines where id=v_input.line_id and tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update;
  if not found then raise exception 'A delivery line does not belong to this delivery'; end if;
  if v_input.delivered_quantity_base is null or v_input.delivered_quantity_base<0 or v_input.delivered_quantity_base>v_line.picked_quantity_base then raise exception 'Delivered quantity must be between zero and picked quantity'; end if;
  update public.delivery_lines set delivered_quantity_base=v_input.delivered_quantity_base where id=v_line.id and tenant_id=v_delivery.tenant_id;
 end loop;
 select coalesce(bool_and(delivered_quantity_base=picked_quantity_base),false) into v_all_delivered
  from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 if not v_all_delivered then
  return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','dispatched','message','Delivery quantities saved; complete all picked quantities to issue the invoice.');
 end if;

 if exists(select 1 from public.sales_invoices where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id) then
  raise exception 'An invoice already exists for this delivery';
 end if;

 v_invoice_no:='EBS-INV-'||right(replace(v_delivery.id::text,'-',''),10);
 insert into public.sales_invoices(tenant_id,sales_order_id,delivery_id,customer_id,invoice_number,invoice_date,subtotal,tax_total,discount_total,grand_total,status,created_by,posted_by,posted_at)
 select v_delivery.tenant_id,so.id,v_delivery.id,so.customer_id,v_invoice_no,current_date,0,0,0,0,'posted',v_user,v_user,now()
 from public.sales_orders so where so.id=v_delivery.sales_order_id and so.tenant_id=v_delivery.tenant_id
 returning id into v_invoice_id;

 for v_line in select * from public.delivery_lines where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id for update loop
  if v_line.sales_order_line_id is null then raise exception 'Delivery line is not linked to its sales order line. Recreate the delivery with current version.'; end if;
  select * into v_order_line from public.sales_order_lines
   where id=v_line.sales_order_line_id and tenant_id=v_delivery.tenant_id and sales_order_id=v_delivery.sales_order_id;
  if not found then raise exception 'Delivery line does not match its sales order'; end if;
  if v_order_line.conversion_to_base<=0 then raise exception 'Invalid sales unit conversion'; end if;
  v_line_subtotal:=(v_line.delivered_quantity_base/v_order_line.conversion_to_base)*v_order_line.unit_price;
  v_line_tax:=v_line_subtotal*v_order_line.tax_rate/100;
  v_line_discount:=case when v_order_line.quantity>0 then v_order_line.discount_amount*(v_line.delivered_quantity_base/(v_order_line.quantity*v_order_line.conversion_to_base)) else 0 end;
  v_line_total:=v_line_subtotal+v_line_tax-v_line_discount;
  if v_line.delivered_quantity_base>0 then
   insert into public.sales_invoice_lines(tenant_id,sales_invoice_id,sales_order_line_id,product_id,unit_id,quantity,conversion_to_base,unit_price,tax_rate,discount_amount,line_total)
   values(v_delivery.tenant_id,v_invoice_id,v_order_line.id,v_order_line.product_id,v_order_line.unit_id,
    v_line.delivered_quantity_base/v_order_line.conversion_to_base,v_order_line.conversion_to_base,v_order_line.unit_price,
    v_order_line.tax_rate,v_line_discount,v_line_total);
   v_subtotal:=v_subtotal+v_line_subtotal;
   v_tax:=v_tax+v_line_tax;
   v_discount:=v_discount+v_line_discount;
  end if;
 end loop;
 if v_subtotal<=0 then raise exception 'Invoice must contain a positive delivered value'; end if;
 update public.sales_invoices set subtotal=v_subtotal,tax_total=v_tax,discount_total=v_discount,grand_total=v_subtotal+v_tax-v_discount
  where id=v_invoice_id and tenant_id=v_delivery.tenant_id;

 select id into v_ar from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='1100' and is_active;
 select id into v_revenue from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='4000' and is_active;
 select id into v_tax_account from public.chart_of_accounts where tenant_id=v_delivery.tenant_id and account_code='2200' and is_active;
 if v_ar is null or v_revenue is null or (v_tax>0 and v_tax_account is null) then raise exception 'Default Accounts Receivable, Sales Revenue or Sales Tax accounts are missing'; end if;
 v_journal_no:='EBS-INV-JV-'||right(replace(v_invoice_id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_delivery.tenant_id,v_journal_no,current_date,'sales_invoice',v_invoice_id,'Sales invoice '||v_invoice_no,'posted',v_user,v_user,now())
 returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_delivery.tenant_id,v_journal_id,v_ar,v_subtotal+v_tax-v_discount,0,'Customer receivable'),
       (v_delivery.tenant_id,v_journal_id,v_revenue,0,v_subtotal-v_discount,'Sales revenue');
 if v_tax>0 then
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_delivery.tenant_id,v_journal_id,v_tax_account,0,v_tax,'Sales tax payable');
 end if;

 update public.deliveries set status='delivered',delivered_at=now() where id=v_delivery.id and tenant_id=v_delivery.tenant_id;
 select coalesce(bool_and(coalesce(done.delivered,0)>=so_line.quantity*so_line.conversion_to_base),false)
  into v_full_order
  from public.sales_order_lines so_line
  left join lateral (
   select sum(dl.delivered_quantity_base) as delivered
   from public.delivery_lines dl join public.deliveries d on d.id=dl.delivery_id and d.tenant_id=dl.tenant_id
   where dl.tenant_id=so_line.tenant_id and dl.sales_order_line_id=so_line.id and d.status='delivered'
  ) done on true
  where so_line.tenant_id=v_delivery.tenant_id and so_line.sales_order_id=v_delivery.sales_order_id;
 update public.sales_orders set status=case when v_full_order then 'delivered' else 'dispatched' end,updated_at=now()
  where id=v_delivery.sales_order_id and tenant_id=v_delivery.tenant_id and status in ('dispatched','allocated');
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'status','delivered','invoice_id',v_invoice_id,'invoice_number',v_invoice_no,'invoice_total',v_subtotal+v_tax-v_discount);
end;
$$;
