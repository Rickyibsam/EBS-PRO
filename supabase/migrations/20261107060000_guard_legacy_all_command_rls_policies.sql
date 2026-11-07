-- Enforce explicit per-user module denials on legacy FOR ALL RLS policies.
-- Existing role/tenant policies remain the permissive baseline. These restrictive
-- command policies only veto access when a user's custom permission explicitly denies it.
do $migration$
declare
  v_table text;
  v_module text;
  v_action text;
  v_policy text;
  v_using text;
  v_check text;
  v_item record;
begin
  for v_item in
    select * from (values
      ('asset_depreciation_entries','accounts_finance'),
      ('booker_product_visibility','order_booking'),
      ('budget_lines','accounts_finance'),
      ('budgets','accounts_finance'),
      ('delivery_charge_account_mappings','distribution_delivery'),
      ('delivery_charge_rules','distribution_delivery'),
      ('departments','hr_payroll'),
      ('designations','hr_payroll'),
      ('employee_advance_account_mappings','accounts_finance'),
      ('fixed_assets','accounts_finance'),
      ('payroll_incentive_accruals','hr_payroll'),
      ('van_stock_movements','distribution_delivery')
    ) as modules(table_name,module_key)
  loop
    v_table := v_item.table_name;
    v_module := v_item.module_key;

    foreach v_action in array array['select','insert','update','delete'] loop
      v_policy := 'module_override_guard_' || v_action;
      v_using := null;
      v_check := null;

      if v_action in ('select','update','delete') then
        v_using := format(
          'private.module_permission_guard_internal(tenant_id,%L,%L)',
          v_module,
          case when v_action='select' then 'view' else v_action end
        );
      end if;
      if v_action in ('insert','update') then
        v_check := format(
          'private.module_permission_guard_internal(tenant_id,%L,%L)',
          v_module,
          case when v_action='insert' then 'create' else 'update' end
        );
      end if;

      execute format('drop policy if exists %I on public.%I',v_policy,v_table);
      if v_action='insert' then
        execute format(
          'create policy %I on public.%I as restrictive for insert to authenticated with check (%s)',
          v_policy,v_table,v_check
        );
      elsif v_action='update' then
        execute format(
          'create policy %I on public.%I as restrictive for update to authenticated using (%s) with check (%s)',
          v_policy,v_table,v_using,v_check
        );
      else
        execute format(
          'create policy %I on public.%I as restrictive for %s to authenticated using (%s)',
          v_policy,v_table,v_action,v_using
        );
      end if;
    end loop;
  end loop;
end
$migration$;
