-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
select o.id,'4100','Sales Returns','income',false,true
from public.organizations o
where not exists(select 1 from public.chart_of_accounts c where c.tenant_id=o.id and c.account_code='4100');
CREATE OR REPLACE FUNCTION public.create_tenant(p_name text, p_slug text, p_city text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare v_tenant_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Business name is required'; end if;
 if p_slug !~ '^[a-z0-9][a-z0-9-]{2,49}$' then raise exception 'Use a valid 3-50 character lowercase slug'; end if;
 insert into public.organizations(name,slug,city,phone) values(trim(p_name),lower(p_slug),nullif(trim(p_city),''),nullif(trim(p_phone),'')) returning id into v_tenant_id;
 insert into public.tenant_memberships(tenant_id,user_id,role) values(v_tenant_id,auth.uid(),'owner');
 insert into public.branches(tenant_id,name,code,is_default) values(v_tenant_id,'Main Branch','MAIN',true);
 insert into public.chart_of_accounts(tenant_id,account_code,account_name,account_type,is_control_account,is_active)
 values
 (v_tenant_id,'1000','Cash on Hand','asset',false,true),
 (v_tenant_id,'1010','Bank Accounts','asset',false,true),
 (v_tenant_id,'1100','Accounts Receivable','asset',true,true),
 (v_tenant_id,'1200','Inventory','asset',false,true),
 (v_tenant_id,'2000','Accounts Payable','liability',true,true),
 (v_tenant_id,'2100','Goods Received Not Invoiced','liability',false,true),
 (v_tenant_id,'2200','Sales Tax Payable','liability',false,true),
 (v_tenant_id,'3000','Owner Capital','equity',false,true),
 (v_tenant_id,'4000','Sales Revenue','income',false,true),
 (v_tenant_id,'4100','Sales Returns','income',false,true),
 (v_tenant_id,'5000','Cost of Goods Sold','expense',false,true),
 (v_tenant_id,'5100','Operating Expenses','expense',false,true);
 return v_tenant_id;
end;
$function$
;
