// Retry interval when another poller holds the bot token.
// Short and fixed — no exponential backoff. The relay must reclaim the token
// within one second of the competing poller dying, not after a multi-minute wait.
export const TELEGRAM_POLLING_CONFLICT_RETRY_DELAY_MS = 1_000;

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function errorRecords(error: unknown): Record<string, unknown>[] {
  const root = asRecord(error);
  const nested = root ? [root.error, root.cause].map(asRecord).filter(Boolean) : [];
  return root ? [root, ...nested] : [];
}

export function isTelegramPollingConflictError(error: unknown): boolean {
  if (
    errorRecords(error).some((record) => {
      return record.error_code === 409 ||
        record.code === 409 ||
        record.status === 409;
    })
  ) {
    return true;
  }

  const msg = errorMessage(error);
  return /\b409\b/.test(msg) &&
    /getUpdates|terminated by other getUpdates|long polling|Conflict/i.test(msg);
}
