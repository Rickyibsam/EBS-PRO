-- Permit a same-tenant owner/admin backup restore to preserve legacy batch
-- metadata, while continuing to enforce all intake checks for normal writes.
-- Recreate the function directly instead of fragile source-text substitution.
create or replace function public.enforce_stock_batch_expiry_rules()
returns trigger
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
  v_track_batch boolean;
  v_track_expiry boolean;
  v_received_date date;
  v_restore boolean;
begin
  v_restore:=current_setting('app.ebs_backup_restore',true)='on'
    and public.has_tenant_role(new.tenant_id,array['owner','admin']::text[]);

  select p.track_batch,p.track_expiry
    into v_track_batch,v_track_expiry
  from public.products p
  where p.id=new.product_id and p.tenant_id=new.tenant_id;

  if not found then
    raise exception 'Product does not belong to this tenant.' using errcode='23503';
  end if;

  if not v_restore then
    if v_track_batch and nullif(btrim(new.batch_number),'') is null then
      raise exception 'Batch number is required for this batch-tracked product.' using errcode='23514';
    end if;
    if v_track_expiry and new.expiry_date is null then
      raise exception 'Expiry date is required for this expiry-tracked product.' using errcode='23514';
    end if;
  end if;

  if new.expiry_date is not null and not v_restore then
    if tg_table_name='goods_receipt_lines' then
      select gr.received_date into v_received_date
      from public.goods_receipts gr
      where gr.id=new.goods_receipt_id and gr.tenant_id=new.tenant_id;
      if v_received_date is null then
        raise exception 'Goods receipt was not found for this tenant.' using errcode='23503';
      end if;
      if new.expiry_date<greatest(v_received_date,current_date) then
        raise exception 'Expired stock cannot be received into available inventory.' using errcode='23514';
      end if;
    elsif tg_table_name='stock_movements' and coalesce(new.quantity_in,0)>0 then
      if new.expiry_date<current_date then
        raise exception 'Expired stock cannot be added to available inventory.' using errcode='23514';
      end if;
    end if;
  end if;

  return new;
end;
$function$;
