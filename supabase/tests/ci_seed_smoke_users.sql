-- CI-only bootstrap identities for the rollback-only transactional workflow test.
-- NEVER execute this fixture against a production database.

begin;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
(
  '00000000-0000-4000-8000-000000000071',
  'authenticated', 'authenticated', 'ci-smoke-owner@example.invalid', '',
  now(), '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"CI Smoke Owner"}'::jsonb, now(), now()
),
(
  '00000000-0000-4000-8000-000000000072',
  'authenticated', 'authenticated', 'ci-smoke-admin@example.invalid', '',
  now(), '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"CI Smoke Admin"}'::jsonb, now(), now()
)
on conflict do nothing;

insert into public.organizations (id, name, slug)
values (
  '00000000-0000-4000-8000-000000000073',
  'EBS CI Smoke Bootstrap',
  'ebs-ci-smoke-bootstrap'
)
on conflict do nothing;

insert into public.tenant_memberships (tenant_id, user_id, role, is_active)
values
(
  '00000000-0000-4000-8000-000000000073',
  '00000000-0000-4000-8000-000000000071',
  'owner', true
),
(
  '00000000-0000-4000-8000-000000000073',
  '00000000-0000-4000-8000-000000000072',
  'admin', true
)
on conflict do nothing;

commit;
