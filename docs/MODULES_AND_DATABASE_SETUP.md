# EBS PRO V.01 — Module Map and Database Notes

## Project status

The current application is a React/TypeScript ERP connected to Supabase. The hosted frontend is at https://ebs-pro.onrender.com and the source is https://github.com/Rickyibsam/EBS-PRO.

The application has 10 module groups. The navigation and module screens are present in the current source; this does **not** mean every complete business workflow has passed end-to-end testing.

## Implemented module map

1. **Dashboard & Management**
   - Owner/admin dashboard and daily, weekly and monthly posted-sales indicators.
   - Purchase, stock, profit, open-order and delivery metrics.
   - Low-stock alert and persistent per-user read/unread notification inbox for low stock, pending sales approvals, past-due invoice dates and the delivery queue.
   - Recent audit activity.

2. **Sales & Customer Management**
   - Customer and supplier records, categories/types, credit limits and payment terms.
   - Sales orders, approval, invoices, returns and credit notes.
   - Price lists, customer-specific prices, quantity breaks, discounts and party ledgers.

3. **Order Booking App**
   - Booker login linked to an employee and assigned route.
   - Customer selection and route-scoped customer creation.
   - Product/SKU search, handheld USB/Bluetooth scanner input and supported phone-camera barcode scanning through the browser BarcodeDetector API.
   - Cart, free items, unit conversion and customer price list.
   - GPS visit check-in and offline visit/order queue with idempotent synchronization.

4. **Inventory & Warehouse**
   - Product/SKU, category, brand, unit and alternate-unit management.
   - Multiple branches/warehouses, stock movements, stock valuation and inter-warehouse transfers.
   - Batch and expiry enforcement, FEFO dispatch, stock take and low-stock alerts.

5. **Purchase & Supplier Management**
   - Supplier records, purchase orders, goods receipts, supplier invoices, returns/debit notes, payments and supplier ledger.

6. **Accounts & Finance**
   - Chart of accounts, balanced journal drafts and posting.
   - Cash/bank book, receipts/payments, AR/AP ledgers, trial balance, P&L and balance-sheet summaries.
   - Bank reconciliation, cheque register, tax register, fixed assets, depreciation, disposal, budgets and cash-flow classifications.

7. **Distribution & Delivery**
   - Route, area, driver and vehicle assignment; delivery challans and dispatch.
   - Delivered/partial/failed outcomes, proof-of-delivery signature, shop visits and return quantities.
   - Van stock ledger, warehouse load/unload, reservations and delivery charges.

8. **HR & Payroll**
   - Employee records, departments, designations, attendance, leave, payroll, employee advances and repayments.
   - Sales incentives/commission and return-related payroll adjustment.

9. **Reports & Analytics**
   - Posted-invoice sales reports by date, customer, product, brand, booker and route/area.
   - Purchase-by-supplier and warehouse stock reports, profitability and outstanding/recovery information.
   - CSV export and browser print/Save as PDF.

10. **Administration & Security**
    - Tenant/company onboarding, multiple companies, branches and warehouses.
    - Staff invitations, employee profiles, tenant memberships, role/module access and owner-managed per-user View/Create/Update/Delete overrides.
    - Audit trail, login history, password recovery, company settings and invoice design.
    - Draft voucher revision history and manual tenant backup/additive restore.

## Newly completed gaps and workflow fixes

- **Custom permissions:** the owner can enable per-user overrides for 10 module groups with View/Create/Update/Delete actions. If no override exists, the user's existing role rules remain the default. Owner/admin role access remains protected. Database RLS enforces explicit grants and denials across 77 tenant-scoped business tables and 308 module/action policy commands. A follow-up audit found zero module-grant policy commands without a matching restrictive guard. Twelve legacy `FOR ALL` policy tables now have separate restrictive SELECT/INSERT/UPDATE/DELETE guards, so permissive role policies cannot bypass an explicit user denial. Reports access grants read-only access to underlying report data without granting create/update/delete; budget and fixed-asset tables are governed by Accounts & Finance permissions.
- **Barcode camera:** the Booker order form can use the phone camera on supported secure-context browsers that expose the BarcodeDetector API. Handheld keyboard-wedge scanners and manual SKU/barcode entry remain available as fallbacks.
- **Persistent notifications:** operational alerts are saved per user and tenant with read/unread state, mark-read and mark-all-read actions. Repeated daily alerts update the existing notification instead of creating duplicates.
- **Automated tests:** the current GitHub Actions run passes all 55 automated tests, followed by the TypeScript/Vite production build. The suite covers permission resolution, barcode matching, Booker/Delivery offline queues, workflow invariants, RLS policy coverage and transaction smoke-test assertions.
- **Critical workflow defects found and fixed during transactional testing:**
  - The document-number allocator used obsolete column names and omitted the required branch key; it now uses the current branch-aware sequence schema.
  - Approved sales/purchase vouchers can now progress through controlled fulfilment/receipt status transitions without unlocking their business fields.
  - Voucher line guards now use the correct goods-receipt creator column and allow only the received-quantity increment on approved purchase order lines.

## Transactional verification completed

The following database smoke workflows were run as authenticated owner/staff contexts inside explicit transactions and rolled back after assertions. The latest run, including the additional legacy `FOR ALL` RLS checks, completed successfully. No test business records were retained:

- Sales: approved order → delivery allocation → dispatch → posted invoice → cash receipt → posted sales credit note and stock return.
- Purchasing: draft PO → approval → GRN creation/posting → PO received status → supplier invoice posting → allocated supplier payment.
- Payroll: temporary payroll run → posting → salary payment.
- Booker: offline order RPC sync and replay idempotency; GPS visit RPC sync and replay idempotency.
- Deliveryman: batch-aware warehouse-to-van load → van dispatch/reservation → offline delivery visit sync → invoice creation and replay idempotency.
- Backup: tenant backup export + no-op additive restore returned zero errors/skipped tables; a separate temporary-tenant restore inserted one missing row, and a second restore inserted zero duplicates. Both test runs were rolled back.
- Security: per-user module denial/grant enforcement, owner-managed permission row access, personal notification inbox access, cross-company customer-record read/write isolation, direct custom-denial checks on app settings/fixed assets/budgets/budget lines, and restrictive guards for all 308 module/action policy commands.
- Client offline storage: all Booker and deliveryman IndexedDB unit tests passed.

The latest GitHub Actions run completed successfully: **58/58 tests passed**, and the TypeScript/Vite production build passed. Main commit `dc1e19d7d50920f21786f36dfe0b9791720a5987` contains the commission-clawback payroll fix and is deploying to Render. The latest code also includes browser-supported BarcodeDetector format detection.

The commission clawback regression workflow now verifies partial recovery capped by available net salary, zero-net payroll posting, duplicate retry prevention, carry-forward into a later payroll, and the resulting payroll GL totals. The payroll posting function omits zero-value journal lines and rejects zero-gross runs. The expanded rollback-only database smoke test passed against the hosted EBS-PRO database; its fixture transaction was rolled back.

## Remaining verification limits

This is stronger coverage than a build-only check, but it is not a claim of complete production certification. Browser-level E2E coverage with real login sessions and user interfaces, physical mobile camera/offline testing, signup/email confirmation, commission clawback edge cases, and exhaustive backup/restore reconciliation in an isolated clean-room tenant are still outstanding. The current tenant has only a small sample dataset, so all business edge cases cannot be proven from its existing records.

## Current hosted database

The hosted Supabase database currently has **82 public base tables**; all 82 have RLS enabled and the audit found zero public base tables without RLS. Public RPC execution is not available to the anonymous role. New public functions, tables and sequences created by the postgres role now require explicit grants. Owner-managed per-user module/action overrides are enforced across **77 tenant-scoped business tables**. The permission configuration and personal notification inbox use separate ownership/user-scoped RLS policies.

The current hosted project has existing organization and sample/test records. Examples at the time of the latest audit include one organization, two tenant memberships, one employee, one sales order, one purchase order, one goods receipt and one journal entry. There were no posted sales invoices or deliveries at that time. This is a small test dataset, not evidence that all workflows have been exercised.

## Important migration caution

Do **not** run only `001_initial_erp_core.sql` against the already configured hosted database. That file is an older bootstrap artifact and is not the complete current schema. The hosted database has a much larger sequence of later migrations.

For a fresh Supabase project, first confirm that every migration required to reproduce the current hosted schema is present in `supabase/migrations` and can be replayed in order. Historical database migrations may predate the current repository migration set; therefore a clean-room rebuild has not been certified. Do not reset or delete the existing project to try it.

Apply future schema changes as versioned migrations, keep the matching SQL file in this repository, and explicitly grant only the API roles that need access. Never expose the service-role key in frontend code.

## Free-tier and operational constraints

- Keep Render and Supabase on free tiers; no paid upgrades, premium add-ons or paid services.
- The frontend uses `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Keep all privileged credentials in server-side secrets only.
- The tenant backup is a manual JSON export and additive restore; it is not automatic point-in-time recovery and excludes Auth credentials and tenant membership/role records.
- Supabase leaked-password protection remains a provider-plan warning; do not upgrade the project to clear it. The app enforces a 12-character mixed-character password rule on new signups and password recovery, but that is not the same as compromised-password checking.

## Verification still required

The latest production build/deploy succeeded. Read-only smoke checks confirmed the trial balance query returned equal debits and credits (PKR 1,200 each in the current test data), and stock-balance, inventory-valuation and low-stock RPCs returned successfully for the owner context.

The remaining verification limits are listed in **Remaining verification limits** above. Do not certify the system as fully production-ready until those are closed.


## Browser and mobile-emulation verification

The CI workflow now runs Playwright against the deployed EBS PRO production URL after unit tests and the production build. It checks the public sign-in page, signup form requirements, password-recovery UI response, mobile viewport layout, and Chromium GPS/camera permission APIs using a simulated device. The simulated camera/GPS checks are browser automation only; they do not certify a physical Android/iOS handset, real camera hardware, background suspension, network transitions, or field-worker end-to-end sync. Those still require a real device and a test tenant.
