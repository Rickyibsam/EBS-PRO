const TRANSIENT_NETWORK_ERROR = /fetch|network|offline|connection|timeout|timed out|failed to load|load failed|networkerror/i;

export function isTransientNetworkError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error ?? "");
  return TRANSIENT_NETWORK_ERROR.test(message);
}
