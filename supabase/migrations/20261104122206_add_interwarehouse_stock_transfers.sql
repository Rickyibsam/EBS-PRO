-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create table if not exists public.stock_transfers(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 transfer_number text not null,
 from_warehouse_id uuid not null,
 to_warehouse_id uuid not null,
 transfer_date date not null default current_date,
 status text not null default 'draft' check(status in ('draft','posted','cancelled')),
 notes text,
 created_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 posted_at timestamptz,
 created_at timestamptz not null default now(),
 unique(tenant_id,transfer_number),
 unique(id,tenant_id),
 check(from_warehouse_id<>to_warehouse_id),
 foreign key(from_warehouse_id,tenant_id) references public.warehouses(id,tenant_id),
 foreign key(to_warehouse_id,tenant_id) references public.warehouses(id,tenant_id)
);
create table if not exists public.stock_transfer_lines(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.organizations(id) on delete cascade,
 stock_transfer_id uuid not null,
 product_id uuid not null,
 quantity_base numeric not null check(quantity_base>0),
 unit_cost numeric not null default 0,
 created_at timestamptz not null default now(),
 foreign key(stock_transfer_id,tenant_id) references public.stock_transfers(id,tenant_id) on delete cascade,
 foreign key(product_id,tenant_id) references public.products(id,tenant_id)
);
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_lines enable row level security;
create policy stock_transfers_read on public.stock_transfers for select to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse','accounts']));
create policy stock_transfers_insert on public.stock_transfers for insert to authenticated
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
create policy stock_transfers_update on public.stock_transfers for update to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']))
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
create policy stock_transfers_delete on public.stock_transfers for delete to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin']));
create policy stock_transfer_lines_read on public.stock_transfer_lines for select to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse','accounts']));
create policy stock_transfer_lines_insert on public.stock_transfer_lines for insert to authenticated
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
create policy stock_transfer_lines_update on public.stock_transfer_lines for update to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']))
 with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
create policy stock_transfer_lines_delete on public.stock_transfer_lines for delete to authenticated
 using(public.has_tenant_role(tenant_id,array['owner','admin']));

create or replace function public.post_stock_transfer(p_transfer_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_transfer public.stock_transfers%rowtype;
 v_line record;
 v_user uuid:=auth.uid();
 v_balance numeric;
 v_value numeric;
 v_cost numeric;
 v_count integer:=0;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_transfer from public.stock_transfers where id=p_transfer_id for update;
 if not found then raise exception 'Stock transfer not found'; end if;
 if not public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You do not have permission to post stock transfers'; end if;
 if v_transfer.status<>'draft' then raise exception 'Only draft stock transfers can be posted'; end if;
 if v_transfer.from_warehouse_id=v_transfer.to_warehouse_id then raise exception 'Source and destination warehouses must be different'; end if;
 if not exists(select 1 from public.stock_transfer_lines where tenant_id=v_transfer.tenant_id and stock_transfer_id=v_transfer.id) then raise exception 'Add at least one transfer line'; end if;
 for v_line in select * from public.stock_transfer_lines where tenant_id=v_transfer.tenant_id and stock_transfer_id=v_transfer.id for update loop
  if v_transfer.from_warehouse_id::text < v_transfer.to_warehouse_id::text then
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.from_warehouse_id::text||':'||v_line.product_id::text,0));
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.to_warehouse_id::text||':'||v_line.product_id::text,0));
  else
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.to_warehouse_id::text||':'||v_line.product_id::text,0));
   perform pg_advisory_xact_lock(hashtextextended(v_transfer.tenant_id::text||':'||v_transfer.from_warehouse_id::text||':'||v_line.product_id::text,0));
  end if;
  select coalesce(sum(quantity_in-quantity_out),0),
         coalesce(sum(quantity_in*unit_cost)-sum(quantity_out*unit_cost),0)
   into v_balance,v_value from public.stock_movements
   where tenant_id=v_transfer.tenant_id and warehouse_id=v_transfer.from_warehouse_id and product_id=v_line.product_id;
  if v_balance<v_line.quantity_base then raise exception 'Insufficient source stock for product %. Available %, requested %',v_line.product_id,v_balance,v_line.quantity_base; end if;
  v_cost:=case when v_balance>0 then greatest(v_value/v_balance,0) else 0 end;
  update public.stock_transfer_lines set unit_cost=v_cost where id=v_line.id and tenant_id=v_transfer.tenant_id;
  insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,movement_at,created_by,notes)
  values
   (v_transfer.tenant_id,v_transfer.from_warehouse_id,v_line.product_id,'transfer_out','stock_transfer',v_transfer.id,0,v_line.quantity_base,v_cost,now(),v_user,'Transfer out '||v_transfer.transfer_number),
   (v_transfer.tenant_id,v_transfer.to_warehouse_id,v_line.product_id,'transfer_in','stock_transfer',v_transfer.id,v_line.quantity_base,0,v_cost,now(),v_user,'Transfer in '||v_transfer.transfer_number);
  v_count:=v_count+1;
 end loop;
 update public.stock_transfers set status='posted',posted_by=v_user,posted_at=now() where id=v_transfer.id and tenant_id=v_transfer.tenant_id;
 return jsonb_build_object('success',true,'transfer_id',v_transfer.id,'lines_posted',v_count,'status','posted');
end;
$$;
revoke all on function public.post_stock_transfer(uuid) from public,anon;
grant execute on function public.post_stock_transfer(uuid) to authenticated;
create index if not exists stock_transfers_tenant_date_idx on public.stock_transfers(tenant_id,transfer_date desc);
create index if not exists stock_transfer_lines_tenant_transfer_idx on public.stock_transfer_lines(tenant_id,stock_transfer_id);
