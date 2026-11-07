-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.bank_reconciliations(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.organizations(id) on delete cascade,
 account_id uuid not null references public.chart_of_accounts(id),statement_date date not null,
 statement_balance numeric(18,2) not null,book_balance numeric(18,2) not null,difference numeric(18,2) not null,
 notes text,created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 constraint bank_reconciliations_tenant_account_date_uq unique(tenant_id,account_id,statement_date)
);
create index if not exists bank_reconciliations_tenant_date_idx on public.bank_reconciliations(tenant_id,statement_date desc);
alter table public.bank_reconciliations enable row level security;
grant select,insert on public.bank_reconciliations to authenticated;
drop policy if exists bank_reconciliations_select on public.bank_reconciliations;
drop policy if exists bank_reconciliations_insert on public.bank_reconciliations;
create policy bank_reconciliations_select on public.bank_reconciliations for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
create policy bank_reconciliations_insert on public.bank_reconciliations for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']));
