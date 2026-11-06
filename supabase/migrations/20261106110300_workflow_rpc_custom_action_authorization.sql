-- Align privileged workflow RPC checks with the same per-module action overrides enforced by RLS.
do $$
declare v_item record; v_oid oid; v_definition text;
begin
 for v_item in select * from (values
 ('public.adjust_stock(uuid,uuid,uuid,text,numeric,numeric,text,date,text)',
  $old$if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) then
   raise exception 'You do not have permission to adjust stock';
 end if;$old$,
  $new$if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(p_tenant_id,'inventory','create')) then
   raise exception 'You do not have permission to adjust stock';
 end if;$new$),
 ('public.post_goods_receipt(uuid)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can post goods receipts'; end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','update')) then raise exception 'Only an authorized purchase/warehouse user can post goods receipts'; end if;$new$),
 ('public.dispatch_delivery(uuid,jsonb)',
  $old$if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'Only an owner, admin, manager or warehouse user can confirm dispatch'; end if;$old$,
  $new$if not (public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')) then raise exception 'Only an authorized distribution/warehouse user can confirm dispatch'; end if;$new$),
 ('public.complete_delivery(uuid,jsonb)',
  $old$if not (
  public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse'])
  OR (public.has_tenant_role(v_delivery.tenant_id,array['delivery_man']) AND EXISTS (
   SELECT 1 FROM public.employees e WHERE e.id=v_delivery.delivery_man_employee_id AND e.tenant_id=v_delivery.tenant_id AND e.user_id=v_user
  ))
 ) then raise exception 'Only an authorized warehouse user or the assigned delivery man can confirm delivery'; end if;$old$,
  $new$if not (
  public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse'])
  OR private.module_permission_grant_internal(v_delivery.tenant_id,'distribution_delivery','update')
  OR (public.has_tenant_role(v_delivery.tenant_id,array['delivery_man']) AND EXISTS (
   SELECT 1 FROM public.employees e WHERE e.id=v_delivery.delivery_man_employee_id AND e.tenant_id=v_delivery.tenant_id AND e.user_id=v_user
  ))
 ) then raise exception 'Only an authorized distribution/warehouse user or assigned delivery man can confirm delivery'; end if;$new$),
 ('public.create_delivery_for_approved_order(uuid,uuid)',
  $old$if not public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) then raise exception 'Not allowed to allocate delivery';end if;$old$,
  $new$if not (public.has_tenant_role(v_order.tenant_id,array['owner','admin','manager','sales']) or (private.module_permission_grant_internal(v_order.tenant_id,'sales_customer','update') and private.module_permission_grant_internal(v_order.tenant_id,'distribution_delivery','create'))) then raise exception 'Not allowed to allocate delivery';end if;$new$),
 ('public.create_purchase_invoice(uuid,text,date,date,numeric,text)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase invoice creation permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create')) then raise exception 'Purchase invoice creation permission required';end if;$new$),
 ('public.create_purchase_debit_note(uuid,jsonb,text,date)',
  $old$if not public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) then raise exception 'Purchase return creation permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_grn.tenant_id,array['owner','admin','manager','purchase']) or private.module_permission_grant_internal(v_grn.tenant_id,'purchase_supplier','create')) then raise exception 'Purchase return creation permission required';end if;$new$),
 ('public.post_purchase_invoice(uuid)',
  $old$if not public.has_tenant_role(v_inv.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only accounts or management can post supplier invoices';end if;$old$,
  $new$if not (public.has_tenant_role(v_inv.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_inv.tenant_id,'purchase_supplier','update')) then raise exception 'Only authorized purchase/accounts users can post supplier invoices';end if;$new$),
 ('public.post_stock_transfer(uuid)',
  $old$if not public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) then raise exception 'You do not have permission to post stock transfers'; end if;$old$,
  $new$if not (public.has_tenant_role(v_transfer.tenant_id,array['owner','admin','manager','warehouse']) or private.module_permission_grant_internal(v_transfer.tenant_id,'inventory','update')) then raise exception 'You do not have permission to post stock transfers'; end if;$new$),
 ('public.create_sales_credit_note(uuid,jsonb,text,date)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) then raise exception 'You do not have permission to create a sales credit note';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts','sales']) or private.module_permission_grant_internal(v_invoice.tenant_id,'sales_customer','create')) then raise exception 'You do not have permission to create a sales credit note';end if;$new$),
 ('private.post_sales_credit_note(uuid)',
  $old$if not public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post a sales credit note';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_note.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_note.tenant_id,'sales_customer','update')) then
  raise exception 'Only authorized sales/accounts users can post a sales credit note';
 end if;$new$),
 ('public.record_invoice_receipt(uuid,numeric,text,text,text)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can allocate invoice receipts';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','create')) then
  raise exception 'Invoice receipt create permission required';
 end if;$new$),
 ('public.record_invoice_receipt(uuid,numeric,text,text,text,date)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only owner, admin, manager or accounts can allocate invoice receipts';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','create')) then raise exception 'Invoice receipt create permission required';end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text)',
  $old$if not public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post party payments';
 end if;$old$,
  $new$if not (public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_party.tenant_id,'accounts_finance','create')) then
  raise exception 'Party payment create permission required';
 end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text,date)',
  $old$if not public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Only owner, admin, manager or accounts can post party payments';end if;$old$,
  $new$if not (public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_party.tenant_id,'accounts_finance','create')) then raise exception 'Party payment create permission required';end if;$new$),
 ('public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid)',
  $old$if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Supplier payment permission required';end if;$old$,
  $new$if not (public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) or private.module_permission_grant_internal(v_invoice.tenant_id,'accounts_finance','update')) then raise exception 'Supplier payment allocation update permission required';end if;$new$),
 ('private.create_employee_advance_internal(uuid,uuid,numeric,date,text)',
  $old$if auth.uid() is null or not public.has_tenant_role(p_tenant_id,array['owner','admin','manager']) then raise exception 'You cannot issue employee advances.' using errcode='42501';end if;$old$,
  $new$if auth.uid() is null or not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager']) or private.module_permission_grant_internal(p_tenant_id,'hr_payroll','create')) then raise exception 'You cannot issue employee advances.' using errcode='42501';end if;$new$),
 ('private.record_employee_advance_repayment_internal(uuid,numeric,date,text,text,text)',
  $old$if not found or not public.has_tenant_role(v_advance.tenant_id,array['owner','admin','manager']) then raise exception 'You cannot record this advance repayment.' using errcode='42501';end if;$old$,
  $new$if not found or not (public.has_tenant_role(v_advance.tenant_id,array['owner','admin','manager']) or private.module_permission_grant_internal(v_advance.tenant_id,'hr_payroll','update')) then raise exception 'You cannot record this advance repayment.' using errcode='42501';end if;$new$),
 ('private.settle_delivery_charge_internal(uuid,numeric,text,text,boolean,text)',
  $old$if not public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts','delivery_man']) then raise exception 'You cannot collect this delivery charge.' using errcode='42501';end if;$old$,
  $new$if not (public.has_tenant_role(v_charge.tenant_id,array['owner','admin','manager','accounts','delivery_man']) or private.module_permission_grant_internal(v_charge.tenant_id,'distribution_delivery','update')) then raise exception 'You cannot collect this delivery charge.' using errcode='42501';end if;$new$),
 ('public.post_journal_entry(uuid)',
  $old$if not public.has_tenant_role(v_entry.tenant_id,array['owner','admin','manager','accounts']) then
    raise exception 'You do not have permission to post journal entries';
  end if;$old$,
  $new$if not (
    public.has_tenant_role(v_entry.tenant_id,array['owner','admin','manager','accounts'])
    or case
      when v_entry.source_type in ('purchase_invoice','purchase_return','goods_receipt','purchase_debit_note') then private.module_permission_grant_internal(v_entry.tenant_id,'purchase_supplier','update')
      when v_entry.source_type in ('sales_credit_note') then private.module_permission_grant_internal(v_entry.tenant_id,'sales_customer','update')
      when v_entry.source_type in ('sales_invoice','delivery_cogs','delivery_return') then (private.module_permission_grant_internal(v_entry.tenant_id,'sales_customer','update') or private.module_permission_grant_internal(v_entry.tenant_id,'distribution_delivery','update'))
      when v_entry.source_type in ('payroll','payroll_payment','employee_advance','employee_advance_repayment') then private.module_permission_grant_internal(v_entry.tenant_id,'hr_payroll','update')
      when v_entry.source_type in ('asset_depreciation','asset_disposal') then private.module_permission_grant_internal(v_entry.tenant_id,'accounts_finance','update')
      when v_entry.source_type in ('stock_transfer','stock_adjustment','inventory_adjustment') then private.module_permission_grant_internal(v_entry.tenant_id,'inventory','update')
      when v_entry.source_type in ('delivery_charge','delivery_charge_collection','delivery_charge_waiver') then private.module_permission_grant_internal(v_entry.tenant_id,'distribution_delivery','update')
      else private.module_permission_grant_internal(v_entry.tenant_id,'accounts_finance','update')
    end
  ) then
    raise exception 'You do not have permission to post this journal entry';
  end if;$new$)
 ) as x(signature,old_text,new_text)
 loop
  v_oid:=to_regprocedure(v_item.signature);
  if v_oid is null then raise exception 'Required workflow RPC % was not found.',v_item.signature; end if;
  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_item.old_text in v_definition)=0 then raise exception 'Expected role guard not found in %.',v_item.signature; end if;
  execute replace(v_definition,v_item.old_text,v_item.new_text);
 end loop;
end $$;
