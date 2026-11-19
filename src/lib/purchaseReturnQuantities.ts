export type PurchaseDebitNoteRelation = { status?: string | null } | Array<{ status?: string | null }> | null | undefined;

export type PurchaseReturnLineWithNote = {
  goods_receipt_line_id: string;
  quantity: number | string;
  purchase_debit_notes?: PurchaseDebitNoteRelation;
};

/**
 * Sum quantities already reserved by draft or posted vendor debit notes.
 * PostgREST returns a to-one relationship as an object; tolerate arrays too
 * so the UI remains correct if the relationship is represented differently.
 */
export function sumActivePurchaseReturnQuantities(
  rows: PurchaseReturnLineWithNote[]
): Map<string, number> {
  const totals = new Map<string, number>();
  for (const row of rows) {
    const relation = row.purchase_debit_notes;
    const notes = Array.isArray(relation) ? relation : relation ? [relation] : [];
    if (!notes.some(note => note.status === "draft" || note.status === "posted")) continue;
    const quantity = Number(row.quantity);
    if (!Number.isFinite(quantity) || quantity <= 0) continue;
    totals.set(
      row.goods_receipt_line_id,
      (totals.get(row.goods_receipt_line_id) ?? 0) + quantity
    );
  }
  return totals;
}
