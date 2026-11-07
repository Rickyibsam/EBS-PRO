# EBS PRO automatic entry-code policy

New product and party records receive their codes from PostgreSQL before the row is saved. The UI no longer asks staff to invent these identifiers.

| Record | Generated format | Scope |
|---|---|---|
| Product / SKU | `SKU-000001` | Per company |
| Customer | `CUS-000001` | Per company |
| Supplier | `SUP-000001` | Per company |
| Combined customer/supplier | `PTY-000001` | Per company |

The sequence allocator is transaction-safe and tenant-scoped. Concurrent inserts do not receive the same sequence value. Existing non-empty codes are preserved, including codes on existing records and explicit legacy imports. The database's existing tenant-scoped unique indexes remain the final duplicate guard.

The ERP already allocates selected operational document numbers through the branch-aware `next_document_number` RPC (sales orders, purchase orders, GRNs, credit memos, deliveries, sales invoices and receipts). This policy does not replace supplier invoice numbers, barcodes printed by manufacturers, cheque numbers, tax IDs, vehicle registrations or other externally assigned references.

The database integration test inserts temporary test records and rolls the transaction back. It must never be changed to commit test fixtures into the live company.
