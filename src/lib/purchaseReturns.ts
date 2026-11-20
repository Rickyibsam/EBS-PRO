export function getPurchaseReturnNoteStatus(relation: unknown): string | null {
  const related = Array.isArray(relation) ? relation[0] : relation;
  if (!related || typeof related !== "object") return null;
  const status = (related as Record<string, unknown>).status;
  return typeof status === "string" ? status : null;
}
