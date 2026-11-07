-- Add tenant-scoped automatic stock-transfer document numbers.
alter table public.document_sequences drop constraint if exists document_sequences_document_type_check;
alter table public.document_sequences add constraint document_sequences_document_type_check
check(document_type in ('sales_order','purchase_order','grn','credit_memo','delivery','sales_invoice','receipt','journal_entry','payroll_run','stock_transfer'));
create or replace function public.next_document_number(p_tenant_id uuid,p_document_type text)
returns text language plpgsql set search_path='pg_catalog','public','auth' as $$
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
 when 'journal_entry' then v_prefix:='EBS-JV-';v_width:=9;
 when 'payroll_run' then v_prefix:='EBS-PR-';v_width:=10;
 when 'stock_transfer' then v_prefix:='EBS-ST-';v_width:=9;
 else raise exception 'Unsupported document type';end case;
 insert into public.document_sequences(tenant_id,document_type,next_value) values(p_tenant_id,p_document_type,2)
 on conflict(tenant_id,document_type) do update set next_value=public.document_sequences.next_value+1,updated_at=now()
 returning next_value-1 into v_n;
 return v_prefix||lpad(v_n::text,v_width,'0');
end $$;
revoke all on function public.next_document_number(uuid,text) from public,anon;
grant execute on function public.next_document_number(uuid,text) to authenticated;
