-- Generate stable, tenant-scoped master codes for every new product and party.
-- Existing non-empty codes are preserved; all sequence changes are transactional.

create table if not exists public.master_code_sequences (
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  entity_type text not null check (entity_type in ('product','customer','supplier','party')),
  next_number bigint not null default 1 check (next_number > 0),
  primary key (tenant_id, entity_type)
);

alter table public.master_code_sequences enable row level security;
revoke all on table public.master_code_sequences from public, anon, authenticated;

create or replace function public.generate_master_entry_code()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_entity text;
  v_prefix text;
  v_number bigint;
begin
  if tg_table_name = 'products' then
    if nullif(btrim(new.sku), '') is not null then
      return new;
    end if;
    v_entity := 'product';
    v_prefix := 'SKU-';
  elsif tg_table_name = 'parties' then
    if nullif(btrim(new.party_code), '') is not null then
      return new;
    end if;
    v_entity := case new.party_type
      when 'customer' then 'customer'
      when 'supplier' then 'supplier'
      else 'party'
    end;
    v_prefix := case v_entity
      when 'customer' then 'CUS-'
      when 'supplier' then 'SUP-'
      else 'PTY-'
    end;
  else
    raise exception 'Unsupported master-code table';
  end if;

  insert into public.master_code_sequences(tenant_id, entity_type, next_number)
  values (new.tenant_id, v_entity, 2)
  on conflict (tenant_id, entity_type)
  do update set next_number = public.master_code_sequences.next_number + 1
  returning next_number - 1 into v_number;

  if tg_table_name = 'products' then
    new.sku := v_prefix || lpad(v_number::text, 6, '0');
  else
    new.party_code := v_prefix || lpad(v_number::text, 6, '0');
  end if;
  return new;
end;
$$;

revoke all on function public.generate_master_entry_code() from public, anon, authenticated;

drop trigger if exists products_generate_master_code on public.products;
create trigger products_generate_master_code
before insert on public.products
for each row execute function public.generate_master_entry_code();

drop trigger if exists parties_generate_master_code on public.parties;
create trigger parties_generate_master_code
before insert on public.parties
for each row execute function public.generate_master_entry_code();
