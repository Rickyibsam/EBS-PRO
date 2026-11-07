-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.document_sequences(
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 document_type text not null check(document_type in ('sales_order','purchase_order','grn','credit_memo','delivery','sales_invoice','receipt')),
 next_value bigint not null default 1 check(next_value>0),
 updated_at timestamptz not null default now(),
 primary key(tenant_id,document_type)
);
alter table public.document_sequences enable row level security;
drop policy if exists document_sequences_access on public.document_sequences;
create policy document_sequences_access on public.document_sequences for all to authenticated
using(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales','purchase','warehouse','accounts']))
with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','sales','purchase','warehouse','accounts']));
create or replace function public.next_document_number(p_tenant_id uuid,p_document_type text)
returns text language plpgsql set search_path='pg_catalog','public','auth'
as $$
declare v_n bigint;v_prefix text;v_width integer;v_user uuid:=auth.uid();
begin
 if v_user is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','sales','purchase','warehouse','accounts']) then raise exception 'Not authorized to allocate a document number';end if;
 case p_document_type
 when 'sales_order' then v_prefix:='SO';v_width:=6;
 when 'purchase_order' then v_prefix:='PO';v_width:=6;
 when 'grn' then v_prefix:='GR';v_width:=5;
 when 'credit_memo' then v_prefix:='CM';v_width:=6;
 when 'delivery' then v_prefix:='DLV-';v_width:=5;
 when 'sales_invoice' then v_prefix:='EBS-INV-';v_width:=6;
 when 'receipt' then v_prefix:='RC';v_width:=6;
 else raise exception 'Unsupported document type';
 end case;
 insert into public.document_sequences(tenant_id,document_type,next_value) values(p_tenant_id,p_document_type,2)
 on conflict(tenant_id,document_type) do update set next_value=public.document_sequences.next_value+1,updated_at=now()
 returning next_value-1 into v_n;
 return v_prefix||lpad(v_n::text,v_width,'0');
end $$;
revoke all on function public.next_document_number(uuid,text) from public,anon;
grant execute on function public.next_document_number(uuid,text) to authenticated;

create or replace function public.create_delivery_for_approved_order(p_sales_order_id uuid,p_delivery_man_employee_id uuid default null)
returns jsonb language plpgsql set search_path='pg_catalog','public','auth'
as $$
declare v_order public.sales_orders%rowtype;v_delivery_id uuid;v_no text;v_user uuid:=auth.uid();v_driver uuid;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_order from public.sales_orders where id=p_sales_order_id for update;
 if not found then raise exception 'Sales order not found';end if;
 if not public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) then raise exception 'Not allowed to allocate delivery';end if;
 if v_order.status not in ('approved','allocated') then raise exception 'Only approved sales orders can be allocated';end if;
 v_driver:=coalesce(p_delivery_man_employee_id,v_order.delivery_man_employee_id);
 if v_driver is not null and not exists(select 1 from public.employees e where e.id=v_driver and e.tenant_id=v_order.tenant_id and e.employment_status='active') then raise exception 'Delivery man must be an active employee of this company';end if;
 if exists(select 1 from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id and status not in ('cancelled')) then
  select id,delivery_number into v_delivery_id,v_no from public.deliveries where tenant_id=v_order.tenant_id and sales_order_id=v_order.id order by created_at desc limit 1;
  return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',true);
 end if;
 v_no:=public.next_document_number(v_order.tenant_id,'delivery');
 insert into public.deliveries(tenant_id,sales_order_id,warehouse_id,delivery_number,delivery_date,driver_name,vehicle_number,status,notes,route_id,delivery_man_employee_id)
 values(v_order.tenant_id,v_order.id,v_order.warehouse_id,v_no,coalesce(v_order.required_delivery_date,current_date),null,null,'pending',v_order.notes,v_order.route_id,v_driver)
 returning id into v_delivery_id;
 insert into public.delivery_lines(tenant_id,delivery_id,product_id,quantity_base,picked_quantity_base,delivered_quantity_base,sales_order_line_id)
 select v_order.tenant_id,v_delivery_id,sol.product_id,sol.quantity*sol.conversion_to_base,0,0,sol.id from public.sales_order_lines sol where sol.tenant_id=v_order.tenant_id and sol.sales_order_id=v_order.id;
 if not exists(select 1 from public.delivery_lines where tenant_id=v_order.tenant_id and delivery_id=v_delivery_id) then raise exception 'Sales order has no lines';end if;
 update public.sales_orders set status='allocated',delivery_man_employee_id=v_driver,updated_at=now() where id=v_order.id and tenant_id=v_order.tenant_id;
 return jsonb_build_object('success',true,'delivery_id',v_delivery_id,'delivery_number',v_no,'existing',false);
end $$;
revoke all on function public.create_delivery_for_approved_order(uuid,uuid) from public,anon;
grant execute on function public.create_delivery_for_approved_order(uuid,uuid) to authenticated;

do $$
declare f text;
begin
 select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='complete_delivery' limit 1;
 if f is not null and position('v_invoice_no:=''EBS-INV-''' in f)>0 then
  f:=replace(f,'v_invoice_no:=''EBS-INV-''||right(replace(v_delivery.id::text,''-'',''''),10);','select public.next_document_number(v_delivery.tenant_id,''sales_invoice'') into v_invoice_no;');
  execute f;
 end if;
 select pg_get_functiondef(p.oid) into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_sales_credit_note' limit 1;
 if f is not null and position('v_note_no:=''EBS-CN-''' in f)>0 then
  f:=replace(f,'v_note_no:=''EBS-CN-''||to_char(coalesce(p_credit_note_date,current_date),''YYYYMMDD'')||''-''||upper(substr(replace(gen_random_uuid()::text,''-'',''''),1,6));','select public.next_document_number(v_invoice.tenant_id,''credit_memo'') into v_note_no;');
  execute f;
 end if;
end $$;
