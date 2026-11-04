# EBS-PRO — Module Map and Database Setup

## Current database foundation
Run `migrations/001_initial_erp_core.sql` in Supabase SQL Editor after confirming the target project. It creates the initial multi-tenant foundation with organization membership, branches, warehouses, products, parties, staff, routes, sales orders, purchase orders, stock movements, payments and audit logs. Tenant-scoped tables have RLS enabled.

## Planned application modules
1. **Company & Access:** organization onboarding, branch setup, user profiles, roles, memberships, permissions and audit history.
2. **Master Data:** product groups, SKU/barcode, units, pack sizes, product images, customers, suppliers, sales routes and price lists.
3. **Purchasing:** purchase requisitions, purchase orders, goods received notes, supplier returns and supplier ledger.
4. **Sales:** quotations, sales orders, approval, invoices, credit/debit notes, customer-specific pricing and discounts.
5. **Inventory:** warehouse stock, opening balances, receipts, issues, transfers, adjustments, batch/expiry tracking and stock valuation.
6. **Booker PWA:** Android-installable web app, assigned routes/customers, GPS visit check-in, offline order drafts, queued sync, customer balance and previous orders.
7. **Dispatch & Delivery:** pick/pack, delivery challan, driver/vehicle, delivery status, proof of delivery and returns.
8. **Finance:** cash/bank accounts, receipts, payments, expenses, chart of accounts, journals, customer/supplier ledgers and day closing.
9. **HR:** employees, attendance, leave, payroll and user access.
10. **Customer Ordering Portal:** product catalogue, repeat orders, order tracking, statements and outstanding balance.
11. **Reports & Controls:** sales/purchase/stock/profit reports, route performance, overdue/credit-limit alerts, approvals, audit trail and backups.

## Run steps
1. Open the EBS-PRO Supabase project dashboard.
2. Go to SQL Editor → New query.
3. Open `supabase/migrations/001_initial_erp_core.sql` in this repository, copy the complete SQL, paste it into SQL Editor and run.
4. Verify using Table Editor: organizations, tenant_memberships, products, parties, sales_orders, purchase_orders, stock_movements, payments and audit_logs.
5. Do not insert service-role keys or database passwords into browser code. Use the Supabase publishable/anon key with RLS. Keep privileged onboarding and admin operations server-side.

**Important:** The migration is a database foundation, not a finished ERP. Do not create production users or load business data until the app's secure organization-onboarding flow is implemented and tested. The database setup is intentionally tenant-isolated; do not disable RLS to make the app work.
