-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.sales_credit_notes (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 sales_invoice_id uuid not null,
 customer_id uuid not null,
 credit_note_number text not null,
 credit_note_date date not null default current_date,
 reason text not null,
 status text not null default 'draft' check (status in ('draft','posted','cancelled')),
 subtotal numeric not null default 0 check (subtotal>=0),
 tax_total numeric not null default 0 check (tax_total>=0),
 discount_total numeric not null default 0 check (discount_total>=0),
 grand_total numeric not null default 0 check (grand_total>=0),
 created_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 created_at timestamptz not null default now(),
 unique (id,tenant_id),
 unique (tenant_id,credit_note_number),
 foreign key (sales_invoice_id,tenant_id) references public.sales_invoices(id,tenant_id),
 foreign key (customer_id,tenant_id) references public.parties(id,tenant_id)
);
create table if not exists public.sales_credit_note_lines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 credit_note_id uuid not null,
 sales_invoice_line_id uuid not null,
 product_id uuid not null,
 unit_id uuid not null,
 quantity numeric not null check (quantity>0),
 conversion_to_base numeric not null check (conversion_to_base>0),
 unit_price numeric not null check (unit_price>=0),
 tax_rate numeric not null default 0 check (tax_rate>=0),
 discount_amount numeric not null default 0 check (discount_amount>=0),
 line_total numeric not null check (line_total>=0),
 return_to_stock boolean not null default true,
 created_at timestamptz not null default now(),
 foreign key (credit_note_id,tenant_id) references public.sales_credit_notes(id,tenant_id) on delete cascade,
 foreign key (sales_invoice_line_id) references public.sales_invoice_lines(id),
 foreign key (product_id,tenant_id) references public.products(id,tenant_id),
 foreign key (unit_id,tenant_id) references public.units_of_measure(id,tenant_id)
);
create index if not exists sales_credit_notes_tenant_invoice_idx on public.sales_credit_notes(tenant_id,sales_invoice_id,status);
create index if not exists sales_credit_note_lines_tenant_note_idx on public.sales_credit_note_lines(tenant_id,credit_note_id);
create index if not exists sales_credit_note_lines_invoice_line_idx on public.sales_credit_note_lines(sales_invoice_line_id);
alter table public.sales_credit_notes enable row level security;
alter table public.sales_credit_note_lines enable row level security;
create policy sales_credit_notes_read on public.sales_credit_notes for select to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
create policy sales_credit_notes_insert on public.sales_credit_notes for insert to authenticated with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
create policy sales_credit_notes_update on public.sales_credit_notes for update to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy sales_credit_notes_delete on public.sales_credit_notes for delete to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin']) and status='draft');
create policy sales_credit_note_lines_read on public.sales_credit_note_lines for select to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
create policy sales_credit_note_lines_insert on public.sales_credit_note_lines for insert to authenticated with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales']));
create policy sales_credit_note_lines_update on public.sales_credit_note_lines for update to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts'])) with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy sales_credit_note_lines_delete on public.sales_credit_note_lines for delete to authenticated using (public.has_tenant_role(tenant_id,array['owner','admin']) and exists(select 1 from public.sales_credit_notes n where n.id=credit_note_id and n.tenant_id=tenant_id and n.status='draft'));
create trigger audit_erp_changes after insert or update or delete on public.sales_credit_notes for each row execute function private.audit_erp_changes();
create trigger audit_erp_changes after insert or update or delete on public.sales_credit_note_lines for each row execute function private.audit_erp_changes();
