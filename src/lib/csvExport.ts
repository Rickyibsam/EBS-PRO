export function buildCsvWithBom(rows: Array<Record<string, unknown>>, columns: string[]): string {
  const escapeCell = (value: unknown) => '"' + String(value ?? "").replace(/"/g, '""') + '"';
  const lines = [
    columns.map(escapeCell).join(","),
    ...rows.map((row) => columns.map((column) => escapeCell(row[column])).join(","))
  ];
  return "\uFEFF" + lines.join("\r\n");
}
