export type PageResult<T> = { data: T[] | null; error: unknown | null };

export async function fetchAllRows<T>(
  fetchPage: (from: number, to: number) => PromiseLike<PageResult<T>>,
  pageSize = 500
): Promise<T[]> {
  if (!Number.isSafeInteger(pageSize) || pageSize < 1) {
    throw new Error("Page size must be a positive safe integer.");
  }

  const rows: T[] = [];
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await fetchPage(from, from + pageSize - 1);
    if (error) {
      throw error;
    }

    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) {
      return rows;
    }
  }
}
