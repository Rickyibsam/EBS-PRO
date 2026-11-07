-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.prevent_posted_voucher_mutation()'::regprocedure) into d;
 d:=replace(d,
  'if lower(coalesce(to_jsonb(old)->>''status'',''''))=''posted'' then raise exception ''Posted vouchers are immutable. Use a reversal or adjustment voucher.'' using errcode=''55000''; end if;',
  'if lower(coalesce(to_jsonb(old)->>''status'',''''))=''posted'' then
    if tg_table_name=''sales_invoices'' and coalesce((to_jsonb(old)->>''grand_total'')::numeric,0)=0 and coalesce((to_jsonb(new)->>''grand_total'')::numeric,0)>0 and lower(coalesce(to_jsonb(new)->>''status'',''''))=''posted'' and (to_jsonb(new)-array[''subtotal'',''tax_total'',''discount_total'',''grand_total''])=(to_jsonb(old)-array[''subtotal'',''tax_total'',''discount_total'',''grand_total'']) then return new; end if;
    raise exception ''Posted vouchers are immutable. Use a reversal or adjustment voucher.'' using errcode=''55000'';
   end if;');
 execute d;
end;
$$;
