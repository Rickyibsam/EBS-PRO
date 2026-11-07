# EBS PRO V.01

A multi-tenant wholesale and distribution ERP built with React, TypeScript, Vite and Supabase. The hosted frontend is deployed as a free Render static site.

- **Live app:** https://ebs-pro.onrender.com
- **Source:** https://github.com/Rickyibsam/EBS-PRO
- **Database:** Supabase project managed separately from the frontend
- **Hosting target:** Render Static Site (free tier)
- **Runtime:** React 19 + TypeScript + Vite

## Modules

1. **Dashboard & Management** — sales, purchases, stock and profit indicators; daily/weekly/monthly sales; low-stock signals; persistent read/unread notification inbox; recent audit activity.
2. **Sales & Customer Management** — customer/supplier master data, credit limits and terms, orders, invoices, returns/credit notes, pricing and ledgers.
3. **Order Booking App** — role-based Booker PWA, assigned routes/customers, product/SKU/barcode input (handheld scanners and supported phone-camera BarcodeDetector), free items, customer pricing, GPS visits, offline queue and idempotent synchronization.
4. **Inventory & Warehouse** — products, categories, brands, units and conversions, stock ledger, multiple warehouses, batch/expiry, transfers, physical stock takes and low-stock alerts.
5. **Purchase & Supplier Management** — suppliers, purchase orders, goods receipts, supplier invoices, purchase returns/debit notes and supplier payments.
6. **Accounts & Finance** — chart of accounts, double-entry journals, cash/bank book, receipts/payments, AR/AP ledgers, trial balance, P&L and balance-sheet summaries.
7. **Distribution & Delivery** — route and delivery assignment, driver/vehicle, delivery status, mandatory customer signature for delivered/short-delivered outcomes, van stock, partial delivery/returns and configurable delivery charges.
8. **HR & Payroll** — employees, departments/designations, attendance, leave, payroll, advances and sales incentives/commission adjustments.
9. **Reports & Analytics** — date/customer/product/brand/booker/area sales, supplier purchases, stock, profitability, outstanding/recovery, CSV and print/PDF.
10. **Administration & Security** — tenant onboarding, companies/branches/warehouses, staff invitations, roles, owner-managed per-user module/action permissions, audit/login history, company settings, voucher revision history and tenant backup/restore.

## Local development

Requirements: Node.js and npm.

```bash
npm install
npm run dev
```

Production build:

```bash
npm run build
npm run preview
```

`npm test` runs the automated Node test suite. The current suite covers role and action permissions, barcode matching, Booker/Delivery offline queues, transient network retries, delivery/POD guards, accounting and transactional workflow invariants. `npm run build` runs TypeScript checks and Vite production compilation. Unit tests do not replace authenticated browser workflows or physical-device testing.

## Environment variables

Configure these in the hosting environment (never commit secrets):

- `VITE_SUPABASE_URL` — Supabase project URL.
- `VITE_SUPABASE_PUBLISHABLE_KEY` — Supabase publishable key (legacy anon key only if the project still uses it).

Never put a Supabase service-role key, database password, or private API secret in a `VITE_*` variable or browser code.

## Deployment

The Render static site is connected to the `main` branch and automatically deploys on commits. Build command:

```bash
npm install --no-audit --no-fund && npm run build
```

Publish directory: `dist`.

The project is intended to remain on free hosting/database tiers. Do not enable paid add-ons or upgrade plans without explicit owner approval.

## Database and security notes

- All 82 public base tables have RLS enabled. Public-schema RPC execution is restricted to signed-in users; future public functions/tables/sequences require explicit grants.
- Owner-configured per-user module/action overrides are enforced by restrictive and permissive RLS policies on 77 tenant-scoped business tables. Permission administration and personal notifications use their own RLS rules.
- Privileged staff invitations run through the authenticated `invite-tenant-member` Edge Function; its service-role key stays server-side.
- Tenant backup is a manual JSON export and additive same-tenant restore. It is not a substitute for provider-managed point-in-time recovery and does not export Supabase Auth credentials or tenant memberships.
- Existing business data must be preserved. Never reset, truncate, or drop production tables as a troubleshooting shortcut.

See [the module and database notes](docs/MODULES_AND_DATABASE_SETUP.md) for the current implementation status and migration cautions.

## Verification status

The latest main-branch CI run (7 November 2026) passed **71/71 automated tests**, the TypeScript/Vite production build, and **10 production browser/mobile-emulation checks** (2 desktop-only skips). The Playwright checks currently cover the public sign-in/signup/password-recovery screens, mobile viewport, and simulated GPS/camera permissions; they do not yet exercise every authenticated ERP screen.

Rollback-only database workflow smoke tests cover sales order → delivery → invoice → receipt → credit note/stock return; purchase order → GRN → supplier invoice → payment and supplier debit note; payroll posting/payment and commission clawback; fixed-asset depreciation/disposal and budget controls; Booker and Delivery PWA idempotent offline synchronization; mandatory atomic POD signature; backup export/additive restore/idempotency; custom permissions; and tenant isolation. These fixture transactions were rolled back and did not leave test business records.

Remaining external acceptance gates are a full authenticated UI run using a dedicated test tenant, a physical Android handset test (camera/GPS/offline/reload/sync/POD), real signup/reset email delivery to a test inbox, and a separate clean-room restore rehearsal. Do not run destructive restore tests against production business data.
