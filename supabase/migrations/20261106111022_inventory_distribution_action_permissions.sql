-- Restore the physical stock-take register and its RPCs before applying
-- the inventory custom-action authorization replacements below.

create table if not exists public.stock_takes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id),
  stock_take_number text not null,
  count_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','posted','cancelled')),
  notes text,
  created_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint stock_takes_tenant_stock_take_number_key unique (tenant_id,stock_take_number)
);

create table if not exists public.stock_take_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  stock_take_id uuid not null references public.stock_takes(id) on delete cascade,
  product_id uuid not null references public.products(id),
  batch_number text,
  expiry_date date,
  expected_quantity numeric not null default 0 check (expected_quantity >= 0),
  counted_quantity numeric not null default 0 check (counted_quantity >= 0),
  variance_quantity numeric not null default 0,
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now()
);

create index if not exists stock_takes_warehouse_idx on public.stock_takes(warehouse_id);
create index if not exists stock_takes_created_by_idx on public.stock_takes(created_by);
create index if not exists stock_takes_posted_by_idx on public.stock_takes(posted_by);
create index if not exists stock_takes_tenant_status_date_idx on public.stock_takes(tenant_id,status,count_date desc);
create index if not exists stock_take_lines_product_idx on public.stock_take_lines(product_id);
create index if not exists stock_take_lines_parent_idx on public.stock_take_lines(tenant_id,stock_take_id);
create unique index if not exists stock_take_lines_lot_uidx
  on public.stock_take_lines(tenant_id,stock_take_id,product_id,coalesce(batch_number,''),coalesce(expiry_date,date '0001-01-01'));

alter table public.stock_takes enable row level security;
drop policy if exists stock_takes_select on public.stock_takes;
create policy stock_takes_select on public.stock_takes
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));
drop policy if exists stock_takes_insert on public.stock_takes;
create policy stock_takes_insert on public.stock_takes
  for insert to authenticated
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));
drop policy if exists stock_takes_update on public.stock_takes;
create policy stock_takes_update on public.stock_takes
  for update to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));

alter table public.stock_take_lines enable row level security;
drop policy if exists stock_take_lines_select on public.stock_take_lines;
create policy stock_take_lines_select on public.stock_take_lines
  for select to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));
drop policy if exists stock_take_lines_insert on public.stock_take_lines;
create policy stock_take_lines_insert on public.stock_take_lines
  for insert to authenticated
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));
drop policy if exists stock_take_lines_update on public.stock_take_lines;
create policy stock_take_lines_update on public.stock_take_lines
  for update to authenticated
  using (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]))
  with check (private.has_tenant_role_internal(tenant_id,array['owner','admin','manager','warehouse']::text[]));

grant all on table public.stock_takes,public.stock_take_lines to authenticated;
revoke all on table public.stock_takes,public.stock_take_lines from anon;

create or replace function public.create_stock_take(
  p_tenant_id uuid,p_warehouse_id uuid,p_count_date date,p_lines jsonb,p_notes text default null
)
returns uuid
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare v_user uuid:=auth.uid();v_id uuid;v_number text;v_product public.products%rowtype;x record;v_expected numeric;v_cost numeric;v_count integer;
begin
 if v_user is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot create a physical stock take.' using errcode='42501'; end if;
 if p_count_date is null or p_count_date>current_date then raise exception 'Stock take date cannot be in the future.'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and tenant_id=p_tenant_id and is_active) then raise exception 'Select an active warehouse in this company.'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Load the warehouse stock snapshot before creating a count.'; end if;
 select count(*),count(distinct (z.product_id,coalesce(z.batch_number,''),coalesce(z.expiry_date,date '0001-01-01')))
 into v_count,v_expected
 from jsonb_to_recordset(p_lines) z(product_id uuid,batch_number text,expiry_date date,counted_quantity numeric);
 if v_count=0 or v_count<>v_expected then raise exception 'Duplicate or missing product batch lines in stock take.'; end if;
 v_number:='ST-'||to_char(p_count_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.stock_takes(tenant_id,warehouse_id,stock_take_number,count_date,status,notes,created_by)
 values(p_tenant_id,p_warehouse_id,v_number,p_count_date,'draft',p_notes,v_user) returning id into v_id;
 for x in select * from jsonb_to_recordset(p_lines) z(product_id uuid,batch_number text,expiry_date date,counted_quantity numeric,expected_quantity numeric) loop
  if x.counted_quantity is null or x.counted_quantity<0 then raise exception 'Counted stock cannot be negative.'; end if;
  select * into v_product from public.products where id=x.product_id and tenant_id=p_tenant_id and is_active;
  if not found then raise exception 'A counted product is not active in this company.'; end if;
  if v_product.track_batch and nullif(btrim(x.batch_number),'') is null then raise exception 'Batch number is required for %.',v_product.name; end if;
  if v_product.track_expiry and x.expiry_date is null then raise exception 'Expiry date is required for %.',v_product.name; end if;
  select coalesce(sum(quantity_in-quantity_out),0),
   case when sum(quantity_in)>0 then sum(quantity_in*unit_cost)/sum(quantity_in) else coalesce(v_product.cost_price,0) end
  into v_expected,v_cost from public.stock_movements
  where tenant_id=p_tenant_id and warehouse_id=p_warehouse_id and product_id=x.product_id
   and batch_number is not distinct from nullif(btrim(x.batch_number),'') and expiry_date is not distinct from x.expiry_date;
  if v_expected<0 then raise exception 'Negative ledger stock found for product % batch %.',v_product.name,x.batch_number; end if;
  if x.expected_quantity is not null and abs(v_expected-x.expected_quantity)>0.000001 then raise exception 'Stock changed after the snapshot for product %. Refresh the snapshot and recount.',v_product.name; end if;
  insert into public.stock_take_lines(tenant_id,stock_take_id,product_id,batch_number,expiry_date,expected_quantity,counted_quantity,unit_cost)
  values(p_tenant_id,v_id,x.product_id,nullif(btrim(x.batch_number),''),x.expiry_date,v_expected,x.counted_quantity,greatest(v_cost,0));
 end loop;
 return v_id;
end;
$function$;

create or replace function public.update_stock_take_counts(p_stock_take_id uuid,p_lines jsonb)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare v_take public.stock_takes%rowtype;x record;v_count integer;v_expected integer;v_updated integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select * into v_take from public.stock_takes where id=p_stock_take_id for update;
 if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot edit this stock take.' using errcode='42501'; end if;
 if v_take.status<>'draft' then raise exception 'Only draft stock takes can be edited.'; end if;
 if jsonb_typeof(p_lines)<>'array' then raise exception 'Stock take count lines must be an array.'; end if;
 select count(*),count(distinct z.id) into v_count,v_expected from jsonb_to_recordset(p_lines) z(id uuid,counted_quantity numeric);
 if v_count=0 or v_count<>v_expected or v_count<>(select count(*) from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id) then raise exception 'Submit every stock take line exactly once.'; end if;
 for x in select * from jsonb_to_recordset(p_lines) z(id uuid,counted_quantity numeric) loop
  if x.counted_quantity is null or x.counted_quantity<0 then raise exception 'Counted quantity cannot be negative.'; end if;
  update public.stock_take_lines set counted_quantity=x.counted_quantity where id=x.id and tenant_id=v_take.tenant_id and stock_take_id=v_take.id;
  get diagnostics v_updated=row_count;if v_updated<>1 then raise exception 'A stock take line does not belong to this count.'; end if;
 end loop;
 return jsonb_build_object('success',true,'lines_saved',v_count);
end;
$function$;

create or replace function public.post_stock_take(p_stock_take_id uuid)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare v_take public.stock_takes%rowtype;x record;v_current numeric;v_variance numeric;v_count integer:=0;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select * into v_take from public.stock_takes where id=p_stock_take_id for update;
 if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot post this stock take.' using errcode='42501'; end if;
 if v_take.status<>'draft' then raise exception 'Only draft stock takes can be posted.'; end if;
 if not exists(select 1 from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id) then raise exception 'Stock take has no count lines.'; end if;
 for x in select * from public.stock_take_lines where tenant_id=v_take.tenant_id and stock_take_id=v_take.id order by product_id,batch_number,expiry_date for update loop
  perform pg_advisory_xact_lock(hashtextextended(v_take.tenant_id::text||'|'||v_take.warehouse_id::text||'|'||x.product_id::text,0));
  select coalesce(sum(quantity_in-quantity_out),0) into v_current from public.stock_movements
  where tenant_id=v_take.tenant_id and warehouse_id=v_take.warehouse_id and product_id=x.product_id
   and batch_number is not distinct from x.batch_number and expiry_date is not distinct from x.expiry_date;
  if abs(v_current-x.expected_quantity)>0.000001 then raise exception 'Stock changed after count began for product %. Refresh and recount before posting.',x.product_id; end if;
  v_variance:=x.counted_quantity-x.expected_quantity;
  if v_variance>0 then
   if x.expiry_date is not null and x.expiry_date<current_date then raise exception 'Expired stock cannot be added to available inventory. Record it through the damage/write-off workflow.'; end if;
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_take.tenant_id,v_take.warehouse_id,x.product_id,'adjustment','stock_take',v_take.id,v_variance,0,x.unit_cost,x.batch_number,x.expiry_date,now(),auth.uid(),'Physical stock count variance increase · '||v_take.stock_take_number);
  elsif v_variance<0 then
   insert into public.stock_movements(tenant_id,warehouse_id,product_id,movement_type,reference_type,reference_id,quantity_in,quantity_out,unit_cost,batch_number,expiry_date,movement_at,created_by,notes)
   values(v_take.tenant_id,v_take.warehouse_id,x.product_id,'adjustment','stock_take',v_take.id,0,abs(v_variance),x.unit_cost,x.batch_number,x.expiry_date,now(),auth.uid(),'Physical stock count variance decrease · '||v_take.stock_take_number);
  end if;
  if v_variance<>0 then v_count:=v_count+1; end if;
 end loop;
 update public.stock_takes set status='posted',posted_by=auth.uid(),posted_at=now() where id=v_take.id and tenant_id=v_take.tenant_id;
 return jsonb_build_object('success',true,'stock_take_number',v_take.stock_take_number,'adjusted_lines',v_count,'status','posted');
end;
$function$;

revoke all on function public.create_stock_take(uuid,uuid,date,jsonb,text) from public,anon;
revoke all on function public.update_stock_take_counts(uuid,jsonb) from public,anon;
revoke all on function public.post_stock_take(uuid) from public,anon;
grant execute on function public.create_stock_take(uuid,uuid,date,jsonb,text) to authenticated;
grant execute on function public.update_stock_take_counts(uuid,jsonb) to authenticated;
grant execute on function public.post_stock_take(uuid) to authenticated;


-- Finish custom inventory/distribution action checks for stock take and van stock workflows.
do $$
declare v_item record;v_oid oid;v_definition text;
begin
 for v_item in select * from (values
 ('public.create_stock_take(uuid,uuid,date,jsonb,text)',
  $old$if v_user is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot create a physical stock take.' using errcode='42501'; end if;$old$,
  $new$if v_user is null or not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'inventory','create')) then raise exception 'You cannot create a physical stock take.' using errcode='42501'; end if;$new$),
 ('public.update_stock_take_counts(uuid,jsonb)',
  $old$if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot edit this stock take.' using errcode='42501'; end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_take.tenant_id,'inventory','update')) then raise exception 'You cannot edit this stock take.' using errcode='42501'; end if;$new$),
 ('public.post_stock_take(uuid)',
  $old$if not found or not public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You cannot post this stock take.' using errcode='42501'; end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_take.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_take.tenant_id,'inventory','update')) then raise exception 'You cannot post this stock take.' using errcode='42501'; end if;$new$),
 ('public.record_van_stock_transfer(uuid,uuid,text,uuid,uuid,text,numeric,text,date,text,text)',
  $old$if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
  raise exception 'You do not have permission to transfer van stock.' using errcode='42501';
 end if;$old$,
  $new$if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','create')) then
  raise exception 'You do not have permission to transfer van stock.' using errcode='42501';
 end if;$new$),
 ('public.dispatch_van_delivery(uuid,text,jsonb)',
  $old$if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only warehouse/management can dispatch a van delivery.' using errcode='42501'; end if;$old$,
  $new$if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only authorized distribution/warehouse users can dispatch a van delivery.' using errcode='42501'; end if;$new$)
 ) as x(signature,old_text,new_text)
 loop
  v_oid:=to_regprocedure(v_item.signature);
  if v_oid is null then raise exception 'Required workflow RPC % not found.',v_item.signature; end if;
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_item.old_text in v_definition)=0 then raise exception 'Expected action guard not found in %.',v_item.signature; end if;
  execute replace(v_definition,v_item.old_text,v_item.new_text);
 end loop;

 select pg_get_functiondef('public.post_journal_entry(uuid)'::regprocedure) into v_definition;
 if position('when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'') then' in v_definition)=0 then
  raise exception 'Expected inventory journal source mapping not found.';
 end if;
 execute replace(v_definition,
  'when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'') then',
  'when v_entry.source_type in (''stock_transfer'',''stock_adjustment'',''inventory_adjustment'',''stock_take'') then');

 select pg_get_functiondef('private.assign_journal_entry_branch()'::regprocedure) into v_definition;
 if position('when ''stock_transfer'' then' in v_definition)=0 then raise exception 'Expected branch inference stock transfer block not found.'; end if;
 execute replace(v_definition,
  'when ''stock_transfer'' then',
  'when ''stock_take'' then select w.branch_id into v_branch from public.stock_takes t join public.warehouses w on w.id=t.warehouse_id and w.tenant_id=t.tenant_id where t.id=new.source_id and t.tenant_id=new.tenant_id;' || chr(10) || '  when ''stock_transfer'' then');
end $$;
