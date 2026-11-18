export type PartyLedgerParty = Record<string, any> & { id: string; party_type: string; opening_balance?: number | string | null };
export type PartyLedgerRow = Record<string, any> & {
  party_id: string | null;
  account_code: string;
  debit: number;
  credit: number;
  is_opening_balance?: boolean;
};

/** Add each selected party's opening balance before its posted ledger activity. */
export function buildPartyLedgerRows(
  ledgerRows: Array<Record<string, any>>,
  parties: PartyLedgerParty[],
  ledgerType: "customer" | "supplier",
  selectedParty = ""
): PartyLedgerRow[] {
  const code = ledgerType === "customer" ? "1100" : "2000";
  const allowedTypes = ledgerType === "customer" ? ["customer", "both"] : ["supplier", "both"];
  const selectedParties = parties.filter(p => allowedTypes.includes(p.party_type) && (!selectedParty || p.id === selectedParty));
  const openingRows: PartyLedgerRow[] = selectedParties.flatMap(p => {
    const amount = Number(p.opening_balance ?? 0);
    if (!Number.isFinite(amount) || amount === 0) return [];
    const normalDebit = ledgerType === "customer";
    return [{
      id: "opening:" + p.id,
      party_id: p.id,
      account_code: code,
      entry_date: "Opening balance",
      journal_number: "—",
      narration: "Opening balance",
      debit: normalDebit ? Math.max(amount, 0) : Math.max(-amount, 0),
      credit: normalDebit ? Math.max(-amount, 0) : Math.max(amount, 0),
      is_opening_balance: true
    }];
  });
  const transactions: PartyLedgerRow[] = ledgerRows
    .filter(row => row.account_code === code && (!selectedParty || row.party_id === selectedParty))
    .map(row => ({ ...row, party_id: row.party_id ?? null, account_code: code, debit: Number(row.debit || 0), credit: Number(row.credit || 0) }));
  return [...openingRows, ...transactions].sort((a, b) => {
    if (!!a.is_opening_balance !== !!b.is_opening_balance) return a.is_opening_balance ? -1 : 1;
    return String(a.entry_date ?? "").localeCompare(String(b.entry_date ?? "")) || String(a.journal_number ?? "").localeCompare(String(b.journal_number ?? ""));
  });
}
