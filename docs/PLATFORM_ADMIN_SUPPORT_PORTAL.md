# EBS PRO V.01 — Platform Super Admin & Customer Support

## Separate portal

The platform staff workspace is served at:

- Local: `http://localhost:5173/super-admin`
- Hosted: `https://ebs-pro.onrender.com/super-admin`

It is a separate route from the tenant ERP. A normal company owner, manager, booker or delivery user cannot enter it. The portal checks the authenticated account against `public.platform_admins` through the server-side `platform_admin_me()` RPC.

## Roles

- `super_admin`: platform-level company directory and customer support operations.
- `support_admin`: company directory and customer support operations, without database-level access to tenant financial records.

The portal displays organization identity, city, account status, registration date, active membership count, branch count and open support case count. It does not expose tenant invoices, customer ledgers, payroll, stock or bank data.

Support staff can create a ticket for a company, set category and priority, assign it to themselves, update status and record conversation messages. Ticket and message access is protected by RLS and the platform-staff role table.

## First Super Admin provisioning

The migration intentionally does **not** grant platform access to any account automatically. This prevents a tenant owner or a newly registered user from elevating themselves to platform staff.

After the migration is approved and applied, the project owner must first sign up / sign in with the exact account that should own platform administration. Verify the Auth user ID and email in Supabase Authentication, then run this one-time statement in the Supabase SQL Editor, replacing the email with the verified account:

```sql
insert into public.platform_admins (user_id, role, is_active, created_by)
select id, 'super_admin', true, id
from auth.users
where lower(email) = lower('REPLACE_WITH_VERIFIED_OWNER_EMAIL')
on conflict (user_id) do update
set role = 'super_admin', is_active = true;
```

Check that exactly one row is returned by:

```sql
select pa.user_id, pa.role, pa.is_active, u.email
from public.platform_admins pa
join auth.users u on u.id = pa.user_id;
```

Only an existing Super Admin should provision additional Support Admins. Do not expose a public signup, query parameter, user metadata field or client-side switch for platform roles.

## Security boundaries

- Platform access is separate from `tenant_memberships`; tenant roles never imply platform access.
- `platform_admins` has RLS enabled and no direct Data API grants. Role lookup is through a narrowly scoped authenticated RPC.
- The company directory RPC checks the active platform role before returning tenant-level summary data.
- Support tickets and messages have RLS policies that allow only active platform staff.
- No service-role key is shipped to the browser.
- No tenant suspension, deletion, payment mutation, password setting or arbitrary tenant impersonation is exposed in this first release.
- Every future support action that changes a tenant's data must use explicit customer consent, least-privilege authorization and an immutable audit trail.

## Acceptance checklist

- [ ] Apply the migration in an isolated database replay.
- [ ] Confirm anonymous and ordinary authenticated users cannot read platform tables or execute platform RPCs.
- [ ] Confirm a tenant owner cannot access `/super-admin`.
- [ ] Provision one verified platform owner using the one-time SQL above.
- [ ] Verify company directory counts against source tables.
- [ ] Create a ticket, assign it, update its status and add a conversation message.
- [ ] Confirm a non-platform account cannot read or alter tickets/messages.
- [ ] Confirm tenant business data is not exposed through the portal.
- [ ] Run production deployment only after separate owner approval.
