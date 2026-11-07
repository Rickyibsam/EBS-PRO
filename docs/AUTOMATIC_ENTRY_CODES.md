# EBS PRO automatic entry-code policy

New product and party records receive their codes from PostgreSQL before the row is saved. The UI no longer asks staff to invent these identifiers.

| Record | Generated format | Scope |
|---|---|---|
| Product / SKU | `SKU-000001` | Per company |
| Customer | `CUS-000001` | Per company |
| Supplier | `SUP-000001` | Per company |
| Combined customer/supplier | `PTY-000001` | Per company |
| Branch | `BR-000001` | Per company |
| Warehouse | `WH-000001` | Per company |
| Department | `DEP-000001` | Per company |
| Designation | `DSG-000001` | Per company |
| Employee | `EMP-000001` | Per company |
| Fixed asset | `AST-000001` | Per company |
| Sales route | `RTE-000001` | Per company |

The sequence allocator is transaction-safe and tenant-scoped. Concurrent inserts do not receive the same sequence value. Existing non-empty codes are preserved, including codes on existing records and explicit legacy imports. The database's existing tenant-scoped unique indexes remain the final duplicate guard.

The ERP allocates operational document numbers through the tenant-scoped `next_document_number` RPC (sales orders, purchase orders, GRNs, credit memos, deliveries, sales invoices, receipts, journal entries, payroll runs and stock transfers). Journal entries use `EBS-JV-000000001`, payroll runs use `EBS-PR-0000000001`, and stock transfers use `EBS-ST-000000001`. These sequences are allocated atomically by PostgreSQL; browser timestamps are not used to create document identifiers. This policy does not replace supplier invoice numbers, barcodes printed by manufacturers, cheque numbers, tax IDs, vehicle registrations or other externally assigned references.

The database integration test inserts temporary product, party, warehouse, department, designation, employee, asset and route records and rolls the transaction back. Branch creation has a separate bootstrap trigger that creates the default warehouse with the existing `MAIN-WH` code; that existing setup behavior is preserved. It must never be changed to commit test fixtures into the live company.
