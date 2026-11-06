-- Honor explicit module/action permissions inside posting RPCs and correct the straight-line useful-life end date.
do $$
declare
 v_item record;
 v_oid oid;
 v_definition text;
begin
 for v_item in
  select * from (values
   ('public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid)',
    $old$if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot post asset depreciation.' using errcode='42501';end if;$old$,
    $new$if not (public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_asset.tenant_id,'accounts_finance','update')) then raise exception 'You cannot post asset depreciation.' using errcode='42501';end if;$new$),
   ('public.post_asset_monthly_depreciation(uuid,date,date,uuid,uuid)',
    $old$least(p_period_end,v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months-1))$old$,
    $new$least(p_period_end,(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months))::date-1)$new$),
   ('public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid)',
    $old$if not public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot dispose this asset.' using errcode='42501'; end if;$old$,
    $new$if not (public.has_tenant_role(v_asset.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_asset.tenant_id,'accounts_finance','update')) then raise exception 'You cannot dispose this asset.' using errcode='42501'; end if;$new$),
   ('public.dispose_fixed_asset(uuid,date,numeric,uuid,uuid,uuid,uuid,uuid)',
    $old$v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months-1)$old$,
    $new$(v_asset.acquisition_date+make_interval(months=>v_asset.useful_life_months))::date-1$new$),
   ('public.post_purchase_debit_note(uuid)',
    $old$if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts','warehouse']) then raise exception 'Purchase return posting permission required';end if;$old$,
    $new$if not (public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts','warehouse','purchase']) or private.module_permission_grant_internal(v_note.tenant_id,'purchase_supplier','update')) then raise exception 'Purchase return posting permission required';end if;$new$),
   ('public.post_payroll_run(uuid)',
    $old$IF NOT public.has_tenant_role(v_run.tenant_id,ARRAY['owner','admin','manager','accounts']) THEN RAISE EXCEPTION 'Payroll posting permission required'; END IF;$old$,
    $new$IF NOT (public.has_tenant_role(v_run.tenant_id,ARRAY['owner','admin','manager','accounts']) OR private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update')) THEN RAISE EXCEPTION 'Payroll posting permission required'; END IF;$new$),
   ('public.pay_payroll_line(uuid,text,text)',
    $old$if not public.has_tenant_role(v_line.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Payroll payment permission required';end if;$old$,
    $new$if not (public.has_tenant_role(v_line.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_line.tenant_id,'hr_payroll','update')) then raise exception 'Payroll payment permission required';end if;$new$),
   ('public.apply_commission_return_adjustments(uuid)',
    $old$if not found or not public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot adjust this payroll run.' using errcode='42501';end if;$old$,
    $new$if not found or not (public.has_tenant_role(v_run.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update')) then raise exception 'You cannot adjust this payroll run.' using errcode='42501';end if;$new$),
   ('public.apply_sales_commission_return_adjustment(uuid)',
    $old$if not public.has_tenant_role(v_accrual.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'You cannot apply commission adjustments.' using errcode='42501'; end if;$old$,
    $new$if not (public.has_tenant_role(v_accrual.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_accrual.tenant_id,'hr_payroll','update')) then raise exception 'You cannot apply commission adjustments.' using errcode='42501'; end if;$new$),
   ('public.import_employee_incentives_to_payroll(uuid,jsonb)',
    $old$if not public.has_tenant_role(v_run.tenant_id, array['owner','admin','manager','accounts']) then
    raise exception 'Payroll incentive import permission required.' using errcode = '42501';
  end if;$old$,
    $new$if not (public.has_tenant_role(v_run.tenant_id, array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_run.tenant_id,'hr_payroll','update')) then
    raise exception 'Payroll incentive import permission required.' using errcode = '42501';
  end if;$new$)
  ) as x(signature,old_text,new_text)
 loop
  v_oid:=to_regprocedure(v_item.signature);
  if v_oid is null then raise exception 'Required ERP RPC % was not found.',v_item.signature; end if;
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_item.old_text in v_definition)=0 then
    raise exception 'Expected authorization or useful-life block not found in %; no further functions were changed.',v_item.signature;
  end if;
  execute replace(v_definition,v_item.old_text,v_item.new_text);
 end loop;
end $$;
