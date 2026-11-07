-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('ebs-company-assets','ebs-company-assets',true,2097152,array['image/png','image/jpeg','image/webp','image/svg+xml'])
on conflict(id) do update set public=true,file_size_limit=2097152,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists ebs_company_assets_public_read on storage.objects;
create policy ebs_company_assets_public_read on storage.objects for select to public using(bucket_id='ebs-company-assets');
drop policy if exists ebs_company_assets_management_insert on storage.objects;
create policy ebs_company_assets_management_insert on storage.objects for insert to authenticated with check(bucket_id='ebs-company-assets' and (storage.foldername(name))[1] in (select tm.tenant_id::text from public.tenant_memberships tm where tm.user_id=(select auth.uid()) and tm.is_active and tm.role in ('owner','admin','manager')));
drop policy if exists ebs_company_assets_management_update on storage.objects;
create policy ebs_company_assets_management_update on storage.objects for update to authenticated using(bucket_id='ebs-company-assets' and (storage.foldername(name))[1] in (select tm.tenant_id::text from public.tenant_memberships tm where tm.user_id=(select auth.uid()) and tm.is_active and tm.role in ('owner','admin','manager'))) with check(bucket_id='ebs-company-assets' and (storage.foldername(name))[1] in (select tm.tenant_id::text from public.tenant_memberships tm where tm.user_id=(select auth.uid()) and tm.is_active and tm.role in ('owner','admin','manager')));
drop policy if exists ebs_company_assets_management_delete on storage.objects;
create policy ebs_company_assets_management_delete on storage.objects for delete to authenticated using(bucket_id='ebs-company-assets' and (storage.foldername(name))[1] in (select tm.tenant_id::text from public.tenant_memberships tm where tm.user_id=(select auth.uid()) and tm.is_active and tm.role in ('owner','admin','manager')));
