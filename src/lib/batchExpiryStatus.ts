export type BatchExpiryProduct = { track_batch?: boolean | null; track_expiry?: boolean | null };
export type BatchExpiryLot = { batch_number?: string | null; expiry_date?: string | null };

export type BatchExpiryStatus = "missing_metadata" | "expired" | "near" | "good" | "no_date";

export function getBatchExpiryStatus(
  product: BatchExpiryProduct | undefined,
  lot: BatchExpiryLot,
  today: string,
  cutoff: string
): BatchExpiryStatus {
  const missingBatch = Boolean(product?.track_batch) && !String(lot.batch_number ?? "").trim();
  const missingExpiry = Boolean(product?.track_expiry) && !lot.expiry_date;
  if (missingBatch || missingExpiry) return "missing_metadata";
  if (lot.expiry_date && lot.expiry_date < today) return "expired";
  if (!lot.expiry_date) return "no_date";
  if (lot.expiry_date <= cutoff) return "near";
  return "good";
}

export function getBatchExpiryIssueLabel(product: BatchExpiryProduct | undefined, lot: BatchExpiryLot): string {
  const missingBatch = Boolean(product?.track_batch) && !String(lot.batch_number ?? "").trim();
  const missingExpiry = Boolean(product?.track_expiry) && !lot.expiry_date;
  if (missingBatch && missingExpiry) return "BATCH & EXPIRY REQUIRED";
  if (missingBatch) return "BATCH REQUIRED";
  if (missingExpiry) return "EXPIRY REQUIRED";
  return "";
}
