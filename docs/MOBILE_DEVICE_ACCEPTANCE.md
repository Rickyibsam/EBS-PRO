# EBS PRO physical-device acceptance checklist

This checklist is for a real Android Chrome or iPhone Safari/PWA session. The GitHub Actions Playwright mobile project uses simulated GPS and camera devices; it does not replace these checks.

## Safe test setup

- Use a dedicated test company/tenant with test customer, product, route, delivery and employee records.
- Do not use live customer orders, real deliveries, payroll or accounting periods.
- Confirm the test user has the Booker and Delivery roles needed for the scenarios.
- Open the HTTPS production URL on the handset and sign in.

## Booker PWA

1. Open Booker App and grant location permission while using the app.
2. Record a visit; verify the displayed GPS point/time and that a visit record is saved once.
3. Open barcode scan and grant camera permission; scan a test SKU and verify the matching product is selected.
4. Switch the phone to airplane mode. Create one small test order and confirm it appears in the pending/offline queue.
5. Close and reopen the PWA while still offline; confirm the queued order remains.
6. Restore network connectivity; wait for automatic retry and confirm the queue clears.
7. Verify in the test tenant that exactly one order exists for the request/idempotency key, with server-calculated price, tax and quantity.

## Delivery PWA

1. Sign in as the test delivery user and open the assigned test delivery.
2. Grant location permission and record a visit.
3. Record delivered/partial/failed quantities and capture the proof-of-delivery signature.
4. Switch to airplane mode before submitting; confirm the visit/POD remains queued.
5. Reload the PWA while offline and confirm the queued visit and signature are retained.
6. Restore connectivity; confirm retry completes and the queue clears.
7. Verify the test delivery has exactly one visit/POD record and that delivered quantities and signature match the submitted values.

## Evidence and pass criteria

- Record handset model, OS version, browser version, test date/time and network type.
- Capture screenshots of GPS permission, barcode scan, offline queue, retry completion and final test records. Do not capture customer personal data.
- Pass only if all steps complete on the real device, no duplicate order/visit is created, no queued data is lost, and the server-side quantities/signature match.
- If any step fails, record the exact error and do not repeat a financial posting against live business records.
