-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.purchase_debit_notes(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id) on delete cascade,
 goods_receipt_id uuid not null,supplier_id uuid not null,warehouse_id uuid not null,debit_note_number text not null,
 note_date date not null default current_date,reason text not null,status text not null default 'draft' check(status in ('draft','posted','void')),
 subtotal numeric(18,2) not null default 0 check(subtotal>=0),created_by uuid references auth.users(id),posted_by uuid references auth.users(id),
 posted_at timestamptz,created_at timestamptz not null default now(),
 constraint purchase_debit_notes_grn_fk foreign key(goods_receipt_id,tenant_id) references public.goods_receipts(id,tenant_id),
 constraint purchase_debit_notes_supplier_fk foreign key(supplier_id,tenant_id) references public.parties(id,tenant_id),
 constraint purchase_debit_notes_warehouse_fk foreign key(warehouse_id,tenant_id) references public.warehouses(id,tenant_id),
 constraint purchase_debit_notes_no_uq unique(tenant_id,debit_note_number),
 constraint purchase_debit_notes_id_tenant_uq unique(id,tenant_id)
);
create table if not exists public.purchase_debit_note_lines(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id) on delete cascade,
 debit_note_id uuid not null,goods_receipt_line_id uuid not null,product_id uuid not null,quantity numeric(18,4) not null check(quantity>0),
 quantity_base numeric(18,4) not null check(quantity_base>0),unit_cost numeric(18,4) not null check(unit_cost>=0),
 batch_number text,expiry_date date,line_total numeric(18,2) not null check(line_total>=0),
 constraint purchase_debit_note_lines_note_fk foreign key(debit_note_id,tenant_id) references public.purchase_debit_notes(id,tenant_id) on delete cascade,
 constraint purchase_debit_note_lines_grn_line_fk foreign key(goods_receipt_line_id,tenant_id) references public.goods_receipt_lines(id,tenant_id),
 constraint purchase_debit_note_lines_product_fk foreign key(product_id,tenant_id) references public.products(id,tenant_id)
);
create index if not exists purchase_debit_notes_tenant_date_idx on public.purchase_debit_notes(tenant_id,note_date desc);
create index if not exists purchase_debit_note_lines_note_idx on public.purchase_debit_note_lines(tenant_id,debit_note_id);
alter table public.purchase_debit_notes enable row level security;alter table public.purchase_debit_note_lines enable row level security;
grant select,insert,update on public.purchase_debit_notes,public.purchase_debit_note_lines to authenticated;
drop policy if exists purchase_debit_notes_select on public.purchase_debit_notes;drop policy if exists purchase_debit_notes_insert on public.purchase_debit_notes;drop policy if exists purchase_debit_notes_update on public.purchase_debit_notes;
drop policy if exists purchase_debit_note_lines_select on public.purchase_debit_note_lines;drop policy if exists purchase_debit_note_lines_insert on public.purchase_debit_note_lines;
create policy purchase_debit_notes_select on public.purchase_debit_notes for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase','accounts','warehouse']));
create policy purchase_debit_notes_insert on public.purchase_debit_notes for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy purchase_debit_notes_update on public.purchase_debit_notes for update to authenticated using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase'])) with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));
create policy purchase_debit_note_lines_select on public.purchase_debit_note_lines for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase','accounts','warehouse']));
create policy purchase_debit_note_lines_insert on public.purchase_debit_note_lines for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','purchase']));

create or replace function public.create_purchase_debit_note(p_goods_receipt_id uuid,p_lines jsonb,p_reason text,p_note_date date default current_date)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_grn public.goods_receipts%rowtype;v_supplier uuid;v_user uuid:=auth.uid();v_note uuid;v_no text;v_input record;v_grl public.goods_receipt_lines%rowtype;v_prior numeric;v_total numeric:=0;v_count integer:=0;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_grn from public.goods_receipts where id=p_goods_receipt_id for update;
 if not found or v_grn.status<>'posted' then raise exception 'Select a posted goods receipt';end if;
 if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase return creation permission required';end if;
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
end $$;

create or replace function public.post_purchase_debit_note(p_debit_note_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_note public.purchase_debit_notes%rowtype;v_user uuid:=auth.uid();v_line record;v_balance numeric;v_inventory uuid;v_control uuid;v_journal uuid;v_no text;v_is_invoiced boolean;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 select * into v_note from public.purchase_debit_notes where id=p_debit_note_id for update;
 if not found then raise exception 'Purchase debit note not found';end if;
 if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts','warehouse']) then raise exception 'Purchase return posting permission required';end if;
 if v_note.status<>'draft' then raise exception 'Only draft purchase returns can be posted';end if;
 if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id for update loop
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));
  select coalesce(sum(quantity_in-quantity_out),0) into v_balance from public.stock_movements where tenant_id=v_note.tenant_id and warehouse_id=v_note.warehouse_id and product_id=v_line.product_id;
  if v_balance<v_line.quantity_base then raise exception 'Insufficient stock to return product %. Available %, requested %',v_line.product_id,v_balance,v_line.quantity_base;end if;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
  values(v_note.tenant_id,v_note.warehouse_id,v_line.product_id,'purchase_return','purchase_debit_note',v_note.id,0,v_line.quantity_base,v_line.unit_cost,v_line.batch_number,v_line.expiry_date,now(),v_user,'Returned to supplier on debit note '||v_note.debit_note_number);
 end loop;
 select id into v_inventory from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='1200' and is_active;
 select exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and status='posted') into v_is_invoiced;
 if v_is_invoiced then select id into v_control from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='2000' and is_active;
 else select id into v_control from public.chart_of_accounts where tenant_id=v_note.tenant_id and account_code='2100' and is_active;end if;
 if v_inventory is null or v_control is null then raise exception 'Inventory and GRNI/AP control accounts are required';end if;
 v_no:='EBS-PRET-JV-'||right(replace(v_note.id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_note.tenant_id,v_no,v_note.note_date,'purchase_return',v_note.id,'Purchase return '||v_note.debit_note_number,'posted',v_user,v_user,now()) returning id into v_journal;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,party_id,debit,credit,memo)
 values(v_note.tenant_id,v_journal,v_control,case when v_is_invoiced then v_note.supplier_id else null end,v_note.subtotal,0,'Supplier return credit / GRNI reversal'),
 (v_note.tenant_id,v_journal,v_inventory,null,0,v_note.subtotal,'Inventory returned to supplier');
 update public.purchase_debit_notes set status='posted',posted_by=v_user,posted_at=now() where id=v_note.id and tenant_id=v_note.tenant_id;
 return jsonb_build_object('success',true,'status','posted','returned_value',v_note.subtotal,'journal_entry_id',v_journal);
end $$;
revoke all on function public.create_purchase_debit_note(uuid,jsonb,text,date) from public;
revoke all on function public.post_purchase_debit_note(uuid) from public;
grant execute on function public.create_purchase_debit_note(uuid,jsonb,text,date) to authenticated;
grant execute on function public.post_purchase_debit_note(uuid) to authenticated;
