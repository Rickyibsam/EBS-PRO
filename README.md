# EBS PRO V.01

A multi-tenant wholesale and distribution ERP built with React, TypeScript, Vite and Supabase. The hosted frontend is deployed as a free Render static site.

- **Live app:** https://ebs-pro.onrender.com
- **Source:** https://github.com/Rickyibsam/EBS-PRO
- **Database:** Supabase project managed separately from the frontend
- **Hosting target:** Render Static Site (free tier)
- **Runtime:** React 19 + TypeScript + Vite

## Modules

1. **Dashboard & Management** — sales, purchases, stock and profit indicators; daily/weekly/monthly sales; low-stock signals; operational notifications; recent audit activity.
2. **Sales & Customer Management** — customer/supplier master data, credit limits and terms, orders, invoices, returns/credit notes, pricing and ledgers.
3. **Order Booking App** — role-based Booker PWA, assigned routes/customers, product/SKU/barcode input (including handheld keyboard-wedge scanners), free items, customer pricing, GPS visits, offline queue and synchronization.
4. **Inventory & Warehouse** — products, categories, brands, units and conversions, stock ledger, multiple warehouses, batch/expiry, transfers, physical stock takes and low-stock alerts.
5. **Purchase & Supplier Management** — suppliers, purchase orders, goods receipts, supplier invoices, purchase returns/debit notes and supplier payments.
6. **Accounts & Finance** — chart of accounts, double-entry journals, cash/bank book, receipts/payments, AR/AP ledgers, trial balance, P&L and balance-sheet summaries.
7. **Distribution & Delivery** — route and delivery assignment, driver/vehicle, delivery status, proof of delivery, van stock, partial delivery/returns and configurable delivery charges.
8. **HR & Payroll** — employees, departments/designations, attendance, leave, payroll, advances and sales incentives/commission adjustments.
9. **Reports & Analytics** — date/customer/product/brand/booker/area sales, supplier purchases, stock, profitability, outstanding/recovery, CSV and print/PDF.
10. **Administration & Security** — tenant onboarding, companies/branches/warehouses, staff invitations, roles/module access, audit/login history, company settings, voucher revision history and tenant backup/restore.

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

The build script runs TypeScript project checks and Vite production compilation. There is currently no automated unit or end-to-end test script in `package.json`; a successful build is not proof that every business workflow has passed.

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

- The hosted database is tenant-scoped and uses Row Level Security on public tables.
- Public-schema RPC execution is restricted to signed-in users; future public functions/tables/sequences require explicit grants.
- Privileged staff invitations run through the authenticated `invite-tenant-member` Edge Function; its service-role key stays server-side.
- Tenant backup is a manual JSON export and additive same-tenant restore. It is not a substitute for provider-managed point-in-time recovery and does not export Supabase Auth credentials or tenant memberships.
- Existing business data must be preserved. Never reset, truncate, or drop production tables as a troubleshooting shortcut.

See [the module and database notes](docs/MODULES_AND_DATABASE_SETUP.md) for the current implementation status and migration cautions.

## Verification status

The latest source has a successful Render production build/deployment. Read-only database smoke checks have been run for the trial balance, stock balance, inventory valuation and low-stock alerts. Full end-to-end testing of complete sales-to-delivery, purchasing-to-payment, payroll, offline synchronization, restore and cross-tenant isolation workflows is still outstanding.
