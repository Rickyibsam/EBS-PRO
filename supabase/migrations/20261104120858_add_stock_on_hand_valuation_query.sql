-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.get_stock_on_hand(p_tenant_id uuid)
returns table(
 product_id uuid,sku text,product_name text,warehouse_id uuid,warehouse_name text,
 quantity_on_hand numeric,reorder_level numeric,average_unit_cost numeric,stock_value numeric
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, auth
as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse','purchase','sales','accounts']) then
   raise exception 'You do not have permission to view stock balances';
 end if;
 return query
 with balances as (
  select sm.product_id,sm.warehouse_id,
         sum(sm.quantity_in-sm.quantity_out)::numeric as qty,
         sum(sm.quantity_in*sm.unit_cost)-sum(sm.quantity_out*sm.unit_cost) as value
    from public.stock_movements sm
   where sm.tenant_id=p_tenant_id
   group by sm.product_id,sm.warehouse_id
 )
 select p.id,p.sku,p.name,w.id,w.name,b.qty,p.reorder_level,
        case when b.qty>0 then greatest(b.value/b.qty,0) else 0 end,
        greatest(b.value,0)
   from balances b
   join public.products p on p.id=b.product_id and p.tenant_id=p_tenant_id
   join public.warehouses w on w.id=b.warehouse_id and w.tenant_id=p_tenant_id
  where b.qty<>0
  order by p.name,w.name;
end;
$$;
revoke all on function public.get_stock_on_hand(uuid) from public,anon;
grant execute on function public.get_stock_on_hand(uuid) to authenticated;
