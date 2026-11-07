-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.record_van_delivery_visit(uuid,text,jsonb,text,text)'::regprocedure) into d;
 d:=replace(d,
  'select coalesce((select avg(unit_cost) from public.van_stock_movements',
  'select coalesce((select sum(unit_cost*(quantity_in+quantity_out))/nullif(sum(quantity_in+quantity_out),0) from public.van_stock_movements');
 execute d;
end;
$$;
