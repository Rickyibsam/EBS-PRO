-- Permit the one atomic initial totals write used when a posted delivery invoice is created.
do $$
declare d text;
begin
 select pg_get_functiondef('public.prevent_posted_voucher_mutation()'::regprocedure) into d;
 d:=replace(d,array['subtotal','tax_total','discount_total','grand_total']::text[]::text,
   array['subtotal','tax_total','discount_total','grand_total','updated_at']::text[]::text);
 execute d;
end;
$$;
