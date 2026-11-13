# EBS PRO V.01 — Windows Offline ERP Master Specification

**Status:** Approved master scope / implementation blueprint  
**Business model:** FMCG manufacturing + wholesale distribution  
**Jurisdiction:** Pakistan  
**Base currency:** PKR  
**Deployment target:** On-premises Windows Server + Windows desktop clients over LAN  
**Source repository:** Rickyibsam/EBS-PRO

## 1. Executive architecture decision

EBS PRO will support two connected business lines:
1. FMCG manufacturing: raw materials, packaging, BOM/formulas, MRP, production, quality, batch traceability, yield, wastage, finished goods and production costing.
2. FMCG wholesale/distribution: vendor procurement, warehouses, customer order booking, trade schemes, delivery, van stock, collections, returns, commissions and finance.

The target deployment is an internet-independent, on-premises LAN system. Internet is not required for ordinary local ERP transactions. Internet is required for optional external integrations such as FBR digital invoicing, email, remote access and cloud replication.

### Recommended deployment components

- Windows Server: hosts the local API/service, PostgreSQL database, report service, scheduler and backup service.
- Windows desktop client: reuse the existing React/TypeScript/Vite UI and package it as a Windows desktop application (Electron shell is the preferred first implementation path to preserve the current frontend).
- Local API: authenticated application service; clients must not connect directly to PostgreSQL.
- Central database: PostgreSQL on the server, with migrations, constraints, indexes, backup and restore procedures.
- Client offline queue: SQLite/IndexedDB-backed durable outbox for drafts and permitted field operations; each command has a UUID/idempotency key, device ID, user ID, company ID, timestamp and sync status.
- Reporting: server-side report queries with PDF, Excel and CSV output; local printing through installed Windows printers.
- Installation: separate Server Setup and Client Setup packages. A client EXE is not the database. The server installer provisions the database and service; client installer configures the LAN server address.

A single EXE can package the desktop client, but the complete multi-user system must be delivered as a signed installer bundle with server services, PostgreSQL installation/configuration, migrations, initial owner setup and client installer. Do not embed the live multi-user database inside each client executable.

## 2. Existing project preservation and migration

The current repository is React 19, TypeScript, Vite and Supabase. It already contains business screens and workflows, role/action permissions, tenant-aware data access, audit history, accounting, inventory, procurement, sales, delivery, HR/payroll and PWA offline queues. The current README reports automated tests and successful transactional smoke tests, but it also states that these do not equal full production acceptance certification.

Migration rules:
- Preserve existing working modules, UI, business rules and tests.
- Do not delete, truncate, reset or overwrite existing production data.
- Do not change the current main branch as part of the initial architecture work.
- Create a dedicated Windows/offline development branch and use reviewed pull requests.
- Inventory every Supabase table, RPC, trigger, RLS policy, Edge Function and storage dependency before replacing it.
- Build a compatibility/data-access layer and migrate one bounded domain at a time.
- Replace Supabase Auth with local server authentication, password hashing, account lockout, session/token expiry, reset workflow and audit history.
- Translate tenant/company/branch isolation and per-user module/action permissions into server-side authorization and PostgreSQL constraints/policies.
- Preserve idempotency, transaction boundaries and audit semantics for every offline sync operation.
- Keep cloud/Render deployment as a separate optional build profile until the on-premises version passes acceptance.

## 3. Functional module catalogue

### A. Governance and master data
1. Multi-company, branches, financial years, periods and cost centres.
2. Users, employees, departments, roles, custom per-user permissions and approval delegation.
3. Products, SKUs, barcodes, brands, categories, units, pack conversions, tax classes and price lists.
4. Vendors, customers, territories, routes, vehicles, warehouses, bins and contacts.
5. Document numbering, currencies, exchange-rate history (PKR base), system settings and audit logs.

### B. Manufacturing
1. Raw material and packaging procurement.
2. BOM/formula/recipe versioning with effective dates and yield.
3. Production planning, demand forecast and material requirements planning (MRP).
4. Production requisition, order approval, work centres and production scheduling.
5. Material reservation, issue, return and substitution approval.
6. Batch/lot production, labour and machine time, output, by-products, scrap and wastage.
7. In-process and final quality inspection; quarantine, release and rejection.
8. Finished goods receipt into warehouse with batch, manufacture date and expiry date.
9. Standard, actual and weighted production costing; material/labour/overhead variance.
10. Rework, subcontract production, maintenance and traceability/recall.

### C. Procurement and vendor accounts
1. Purchase requisition, RFQ, vendor quotation comparison and purchase order.
2. PO approval, goods receipt, QC, batch capture and discrepancy recording.
3. Supplier invoice matching (PO/GRN/invoice), landed cost and AP posting.
4. Purchase return, debit note, vendor claim, rebate and payment allocation.
5. Vendor ledger, ageing, balance confirmation and reconciliation.

### D. Inventory and warehouse
1. Multi-warehouse/bin stock ledger, reservations and available-to-promise.
2. Batch/serial/expiry, FEFO picking, shelf-life rules and blocked stock.
3. Inter-warehouse and manufacturing-to-distribution transfers in transit.
4. Stock count, cycle count, variance approval and controlled adjustments.
5. Damage, expiry, quarantine, scrap, recall and write-off.
6. FIFO/weighted-average valuation policy, cost layers and inventory-to-GL reconciliation.
7. Reorder points, min/max, safety stock and replenishment suggestions.

### E. Sales, trade and distribution
1. Customer onboarding, credit profile, limits, terms, territory and route.
2. Quotations, sales orders, credit checks, price validation and approvals.
3. Trade schemes: buy-X-get-Y, free goods, slabs, vendor-funded offers and claims.
4. Booker PWA, customer visit/GPS, camera/USB barcode scanning, order capture and offline sync.
5. Allocation, FEFO picking, packing, dispatch, delivery challan and invoice.
6. Van loading/unloading, route manifest, deliveryman app, partial/failed delivery and POD.
7. Cash/cheque collection, receipt allocation, market returns, credit notes and reconciliation.
8. Booker, brand, vendor, SKU and delivery incentives with return clawbacks.

### F. Finance, HR and enterprise control
1. Chart of Accounts, GL, journals, AR, AP, cash, bank, cheques and reconciliation.
2. Tax registers, configurable Pakistan tax rules, withholding, tax invoices and FBR integration adapter.
3. Payroll, attendance, leave, loans, advances, deductions and commission settlement.
4. Fixed assets, depreciation, transfer, maintenance and disposal.
5. Budgets, cost centres, cash-flow forecasts and budget-vs-actual controls.
6. CRM, complaints, fleet/fuel/maintenance, SOP/document control and training acknowledgements.
7. Management dashboards, financial statements, operational reports, exports and alerts.
8. Security, audit, backup/restore, data retention, disaster recovery and monitoring.

## 4. End-to-end workflows

### Procure-to-pay
Purchase requisition → RFQ/quotation comparison → PO → approval → goods receipt → QC/batch capture → put-away → supplier invoice match → AP posting → payment approval → payment → vendor reconciliation.

### Plan-to-produce
Demand/forecast → MRP → material availability → production order → BOM version validation → material reservation/issue → production execution → labour/overhead capture → in-process QC → finished goods QC → batch receipt → cost roll-up/variance → inventory and GL posting.

### Order-to-cash
Customer order → pricing/scheme validation → credit check → approval → stock reservation → FEFO pick/pack → dispatch/van load → delivery/POD → invoice → AR and COGS posting → receipt/collection → bank reconciliation.

### Return-to-credit
Return request → authorization → physical receipt → good/damaged/expired classification → QC → stock/quarantine movement → credit note → AR adjustment → sales/commission clawback → vendor claim where applicable.

### Record-to-report
Subledger posting → daily cash/bank reconciliation → AR/AP reconciliation → inventory/GL reconciliation → payroll and depreciation → accruals → trial balance → P&L/balance sheet/cash flow → period lock → audit pack.

### Offline synchronization
Client creates a local draft/command → durable outbox assigns UUID and sequence → connection restored → authenticated API validates user/company/permissions and version → server processes idempotently in a database transaction → server returns canonical ID/status/version → client marks synced. Conflicts must be visible and resolved; never silently overwrite posted transactions. Posted financial transactions require reversal/adjustment vouchers, not edits.

## 5. SOP register

Each SOP must contain owner, purpose, scope, roles, inputs, numbered steps, system validations, approval matrix, exception path, evidence/attachments, records retained, KPI, revision and staff acknowledgement.

- SOP-001 Company/branch/financial-year setup
- SOP-002 User onboarding, access and offboarding
- SOP-003 Product, SKU, barcode and unit setup
- SOP-004 Vendor onboarding and due diligence
- SOP-005 Customer onboarding and credit assessment
- SOP-006 Purchase requisition and RFQ
- SOP-007 PO approval and amendment
- SOP-008 Goods receiving and QC
- SOP-009 Supplier invoice matching and payment
- SOP-010 BOM/formula creation and revision
- SOP-011 Production planning and MRP
- SOP-012 Material issue/return and substitution
- SOP-013 Production execution and batch recording
- SOP-014 In-process/final QC and quarantine
- SOP-015 Finished goods receipt and costing
- SOP-016 Warehouse put-away, picking and FEFO
- SOP-017 Stock transfer and in-transit reconciliation
- SOP-018 Stock count and adjustment
- SOP-019 Customer order booking and pricing
- SOP-020 Credit control and override
- SOP-021 Trade schemes and free goods
- SOP-022 Dispatch, van loading and route manifest
- SOP-023 Delivery, POD, cash and failed delivery
- SOP-024 Customer returns and credit notes
- SOP-025 Purchase returns and vendor claims
- SOP-026 Booker/delivery incentive and clawback
- SOP-027 Cash receipt, payment and bank reconciliation
- SOP-028 Journal approval and period closing
- SOP-029 Payroll and salary settlement
- SOP-030 Fixed assets and depreciation
- SOP-031 Budget creation and variance approval
- SOP-032 Tax invoice and statutory reporting
- SOP-033 Customer/vendor ledger reconciliation
- SOP-034 Backup, restore and disaster recovery
- SOP-035 Security incident and audit review
- SOP-036 SOP revision, training and acknowledgement

## 6. Chart of Accounts (PKR base)

Use a configurable hierarchical five-digit COA. The codes below are a recommended starter template; accountants must validate the final statutory mapping and tax treatment.

### 10000 Assets
- 11000 Current assets
  - 11100 Cash in hand; 11200 Bank accounts; 11300 Petty cash
  - 11400 Trade receivables; 11500 Customer advances
  - 11600 Inventory control
    - 11610 Raw materials; 11620 Packaging materials; 11630 WIP
    - 11640 Finished goods; 11650 Distribution inventory
    - 11660 Goods in transit; 11670 Quality hold; 11680 Damaged/expired stock
  - 11700 Input sales tax receivable; 11800 Prepayments; 11900 Deposits
- 12000 Non-current assets
  - 12100 Land/buildings; 12200 Plant and machinery; 12300 Vehicles
  - 12400 Furniture; 12500 Computers; 12600 Warehouse equipment
  - 12900 Accumulated depreciation (contra-asset)

### 20000 Liabilities
- 21000 Current liabilities
  - 21100 Trade payables; 21200 Vendor advances/clearing
  - 21300 Output sales tax payable; 21400 Withholding tax payable
  - 21500 Salaries payable; 21600 Commission payable
  - 21700 Accrued expenses; 21800 Customer refunds payable
  - 21900 Short-term loans and current lease liabilities
- 22000 Long-term liabilities
  - 22100 Bank loans; 22200 Lease liabilities; 22300 Other long-term provisions

### 30000 Equity
- 31000 Owner/share capital; 31100 Additional capital
- 31200 Retained earnings; 31300 Current-year earnings
- 31400 Drawings/dividends; 31500 Reserves

### 40000 Revenue and contra-revenue
- 41000 Gross sales; 41100 Manufacturing sales; 41200 Distribution sales
- 41300 Export/other sales; 42000 Sales returns
- 42100 Sales discounts; 42200 Sales allowances
- 43000 Other operating revenue

### 50000 Cost of sales and production
- 51000 Cost of goods sold—distribution
- 51100 Raw material consumption; 51200 Packaging consumption
- 51300 Direct production labour; 51400 Factory overhead absorbed
- 51500 Production wastage/scrap; 51600 Inventory write-off
- 51700 Freight inward/landed cost; 51800 Purchase price variance
- 51900 Manufacturing cost variance; 52000 Stock loss/gain

### 60000 Operating expenses
- 61000 Salaries/admin; 61100 Rent; 61200 Utilities
- 61300 Fuel/transport; 61400 Vehicle maintenance
- 61500 Warehouse expense; 61600 Sales commission/booker incentives
- 61700 Delivery incentives; 61800 Marketing
- 61900 IT/software; 62000 Depreciation
- 62100 Bank charges; 62200 Bad debts; 62300 QC expense
- 62400 Factory maintenance; 62500 R&D; 62600 Insurance

### 70000 Other income
- 71000 Vendor rebates; 71100 Discounts received
- 71200 Scrap sales; 71300 Interest/other income

### 80000 Other expenses
- 81000 Finance/interest expense; 81100 Asset disposal loss
- 81200 Foreign exchange loss; 81300 Penalties and other non-operating expense

### Mandatory accounting configuration
- Every posted journal balances: total debit = total credit.
- Subledgers (AR, AP, inventory, fixed assets, payroll) reconcile to GL control accounts.
- Define posting profiles for purchase, GRN, invoice, return, production consumption/output, sales, COGS, receipt, payment, payroll, depreciation, tax and stock adjustment.
- Use dimensions for company, branch, warehouse, department, cost centre, product/brand, route and production batch.
- Do not hardcode tax rates or assume all registered businesses have the same tax treatment.
- Prevent posting into closed periods; corrections use approved reversal/adjustment vouchers.

## 7. Database schema blueprint

All business tables require UUID primary keys, company/tenant ownership, created_at/updated_at, created_by/updated_by, and status where appropriate. Use foreign keys, check constraints, unique document numbers per company/branch/fiscal year, indexes on common filters, and server-enforced authorization. Money uses NUMERIC(19,4) (or an agreed precision); quantities use NUMERIC(20,6); currency code is stored explicitly. Dates use date/timestamptz consistently.

### Organization/security
- companies, branches, warehouses, warehouse_bins, financial_years, accounting_periods
- users, user_credentials, user_sessions, employees, departments, designations
- roles, permissions, user_roles, user_permission_overrides, role_permissions
- approval_workflows, approval_steps, approval_requests, approval_actions
- audit_events, login_events, device_registry, app_settings, document_sequences

### Masters
- products, product_variants, product_barcodes, product_categories, brands
- units, unit_conversions, tax_codes, tax_rates, price_lists, price_list_lines
- vendors, vendor_contacts, vendor_tax_profiles, customers, customer_contacts
- customer_credit_profiles, territories, routes, vehicles, drivers
- warehouses, warehouse_bins, cost_centres, departments

### Procurement
- purchase_requisitions, purchase_requisition_lines
- vendor_quotations, vendor_quotation_lines
- purchase_orders, purchase_order_lines
- goods_receipts, goods_receipt_lines, quality_inspections
- supplier_invoices, supplier_invoice_lines
- purchase_returns, purchase_return_lines, vendor_claims
- vendor_payments, vendor_payment_allocations

### Manufacturing
- bom_headers, bom_versions, bom_lines, work_centres
- production_plans, mrp_runs, material_requirements
- production_orders, production_order_materials, material_issues, material_returns
- production_operations, production_labor_entries, machine_time_entries
- production_outputs, production_scrap, production_batches
- qc_plans, qc_samples, qc_results, batch_genealogy
- production_cost_sheets, production_variances, maintenance_orders

### Inventory/distribution
- inventory_batches, stock_ledger, stock_reservations
- stock_transfers, stock_transfer_lines, stock_counts, stock_count_lines
- stock_adjustments, stock_adjustment_lines, warehouse_receipts
- sales_orders, sales_order_lines, sales_approvals
- schemes, scheme_conditions, scheme_rewards, scheme_claims
- delivery_plans, delivery_runs, delivery_stops, van_loads, van_load_lines
- delivery_events, proof_of_delivery, van_stock_ledger
- sales_invoices, sales_invoice_lines, sales_returns, sales_return_lines
- customer_credit_notes, customer_receipts, receipt_allocations

### Finance/HR/assets/reporting
- chart_of_accounts, account_groups, posting_profiles
- journal_entries, journal_lines, fiscal_period_locks
- bank_accounts, bank_transactions, bank_reconciliations, cheques
- tax_transactions, withholding_transactions, fbr_invoice_queue, fbr_invoice_responses
- employees, attendance, leave_requests, payroll_runs, payroll_lines
- incentive_rules, incentive_targets, incentive_calculations, incentive_settlements
- fixed_assets, asset_depreciation, asset_disposals
- budgets, budget_lines, expense_vouchers, expense_lines
- notifications, notification_reads, attachments, sop_documents, sop_acknowledgements
- report_definitions, export_jobs, backup_runs, restore_runs, migration_history

### Critical database invariants
1. Posted vouchers and posted ledger rows are immutable.
2. All posting occurs inside one database transaction.
3. Journal batches balance before posting.
4. Inventory movements are append-only and reference their source voucher/line.
5. Stock cannot go negative unless a specifically approved policy allows it.
6. Batch/expiry rules block expired stock and enforce FEFO.
7. Document number allocation is concurrency-safe.
8. Idempotency keys prevent duplicate offline replay.
9. Company/branch authorization is checked on every API request and database operation.
10. Backup/restore is tested against counts, checksums and ledger reconciliation.

## 8. Pakistan tax and FBR integration

- PKR is the base currency; foreign currency may be enabled with dated exchange rates and realized/unrealized FX handling.
- Configure taxpayer NTN/STRN, tax profile, product tax category, customer/vendor tax status, effective-dated rates, exemptions and withholding rules.
- Separate federal sales tax, provincial service tax and withholding mappings where applicable; do not hardcode one generic GST percentage.
- Maintain tax invoice, debit/credit note, tax register and reconciliation outputs.
- FBR digital invoicing must be implemented through an applicable FBR-licensed integrator/approved integration route where the taxpayer is required to integrate. Offline local operations may continue, but electronic transmission/validation needs connectivity. Queue status, retries, acknowledgements and rejection handling must be auditable. Confirm the taxpayer's actual category and current legal obligations with its tax adviser/FBR before go-live.

## 9. Reporting catalogue

### Management
- Daily/weekly/monthly sales, purchases, gross margin and net profit
- Company/branch/warehouse/department profitability
- Cash position, bank position, receivables, payables and cash-flow forecast
- Budget vs actual, expense trend and working capital

### Manufacturing
- Production plan vs actual, BOM variance, material consumption
- Yield, scrap, rework, downtime, labour and overhead
- Batch genealogy, QC rejection, expiry and recall exposure
- Standard vs actual unit cost

### Distribution
- Sales by customer, SKU, brand, vendor, route, booker and deliveryman
- Sales returns, discounts, free goods, scheme profitability
- Stock ageing, FEFO exposure, batch expiry, stock valuation
- Van load vs delivery vs returns vs cash reconciliation
- Customer/vendor ageing and collection performance

### Accounting
- General ledger, journal register, cashbook, bankbook
- Trial balance, P&L, balance sheet, cash flow
- AR/AP ageing, customer/vendor statements
- Tax register, withholding register, fixed asset register
- Payroll, incentive and commission statements

All reports must support date range, company, branch, warehouse, department and export to PDF/XLSX/CSV where relevant. Report totals must reconcile to posted source transactions.

## 10. Security, offline operations and disaster recovery

- Server firewall exposes only required LAN API and database administration ports; PostgreSQL is not exposed to client workstations.
- Use TLS on LAN where feasible, secure password hashing, least privilege, account lockout and session expiry.
- Keep secrets out of source control and desktop binaries.
- Use role plus per-user action permissions and company/branch scoping on the server.
- Encrypt backup media; keep at least one offline/offsite copy.
- Define RPO/RTO with the business owner; perform scheduled backup and restore drills.
- Maintain server health, disk-space, database, sync-queue and backup-failure alerts.
- Client offline mode may create drafts and queue permitted field transactions. Posting approvals, shared stock allocation and final GL posting must be confirmed by the central server to avoid conflicting books.
- A server outage stops central posting; clients retain safe drafts until the service returns. Do not claim multi-master database operation.

## 11. Implementation phases and exit gates

### Phase 0 — Discovery and migration inventory
- Map existing 82 public tables, RLS policies, RPCs, triggers, Edge Functions, storage, auth and secrets.
- Produce old-to-new schema mapping and data preservation plan.
- Confirm Windows Server version, client count, hardware, LAN and printer/scanner requirements.
- Exit: signed architecture decision and tested backup of current database.

### Phase 1 — Server foundation
- Local API, PostgreSQL install/configuration, migrations, local authentication, tenant isolation, audit and backup.
- Exit: server installs cleanly, starts after reboot, creates first owner, restores a test backup.

### Phase 2 — Desktop client and sync
- Electron Windows client, server discovery/configuration, login, update process, durable outbox, conflict UI.
- Exit: install on clean Windows client, LAN login, offline draft, reconnect and idempotent sync.

### Phase 3 — Masters and accounting core
- Organization, COA, products, vendors, customers, fiscal periods, GL, AR/AP.
- Exit: opening balances and trial balance reconcile.

### Phase 4 — Procurement, inventory and manufacturing
- PO/GRN, batch ledger, BOM/MRP, production, QC, costing and warehouse transfers.
- Exit: procure-to-pay and plan-to-produce tests reconcile quantity and value.

### Phase 5 — Sales and distribution
- Booker, schemes, order-to-cash, van stock, delivery/POD, returns and collections.
- Exit: order-to-cash and return-to-credit reconcile stock, AR, COGS and incentives.

### Phase 6 — Finance, HR, assets and reporting
- Payroll, tax, bank, assets, budgets, management reports and exports.
- Exit: financial statements reconcile to GL and subledgers.

### Phase 7 — Production hardening and release
- Permission matrix, load tests, security review, recovery drill, printer/scanner tests, Windows clean-install tests and user acceptance.
- Exit: signed release, installer hashes, deployment/runbook, rollback plan and accepted UAT evidence.

## 12. Release deliverables

1. EBS-PRO-Server-Setup-x64 installer.
2. EBS-PRO-Client-Setup-x64 installer and/or self-contained client EXE.
3. PostgreSQL schema migrations and initial COA seed.
4. Local API/service and Windows service configuration.
5. Database backup/restore utility and documented recovery runbook.
6. PDF/Excel/CSV report templates.
7. SOP handbook and user/admin manuals.
8. Test suite, UAT scripts and release verification report.
9. Versioned offline update package and SHA-256 checksums.

A release is not complete merely because the project compiles. The actual installers must be tested on clean Windows Server and client machines, with multi-user concurrency, backup/restore, accounting reconciliation, permissions and offline recovery.

## 13. Initial deployment assumptions to confirm

- Server: Windows Server 2022 or 2025, x64.
- Clients: Windows 10/11 x64.
- Initial LAN: wired Ethernet preferred; Wi-Fi supported.
- Initial deployment size: 5–15 concurrent users until workload/hardware benchmarked.
- PKR base currency; Asia/Karachi timezone; configurable fiscal year.
- Internet optional for local ERP; required for FBR transmission and external integrations.
- No paid cloud dependency required for the on-premises operating mode.
