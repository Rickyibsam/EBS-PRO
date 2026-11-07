-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.dispatch_van_delivery(uuid,text,jsonb)'::regprocedure) into d;
 d:=replace(d,'v_line public.delivery_lines%rowtype;x record;v_available numeric;v_count integer;','v_line public.delivery_lines%rowtype;x record;v_available numeric;v_count integer;v_product public.products%rowtype;');
 d:=replace(d,'if x.picked_quantity_base>0 then\n   perform pg_advisory_xact_lock','if x.picked_quantity_base>0 then\n   select * into v_product from public.products where id=v_line.product_id and tenant_id=v_delivery.tenant_id;\n   perform pg_advisory_xact_lock');
 d:=replace(d,'and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date);','and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date) and (not v_product.track_expiry or expiry_date is not null) and (not v_product.track_batch or batch_number is not null);');
 execute d;

 select pg_get_functiondef('public.record_van_delivery_visit(uuid,text,jsonb,text,text)'::regprocedure) into d;
 d:=replace(d,'and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date)','and product_id=v_line.product_id and (expiry_date is null or expiry_date>=current_date) and (not v_product.track_expiry or expiry_date is not null) and (not v_product.track_batch or batch_number is not null)');
 execute d;
end;
$$;
