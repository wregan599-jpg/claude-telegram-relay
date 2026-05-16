import { expect, test } from "bun:test";
import {
  TELEGRAM_POLLING_CONFLICT_RETRY_DELAY_MS,
  isTelegramPollingConflictError,
} from "./telegram-polling";

test("detects Telegram getUpdates 409 conflict objects", () => {
  expect(
    isTelegramPollingConflictError({
      method: "getUpdates",
      error_code: 409,
      description: "Conflict: terminated by other getUpdates request",
    }),
  ).toBe(true);
});

test("detects Telegram getUpdates 409 conflict messages", () => {
  expect(
    isTelegramPollingConflictError(
      new Error("Call to 'getUpdates' failed! (409: Conflict: terminated by other getUpdates request)"),
    ),
  ).toBe(true);
});

test("does not classify unrelated Telegram errors as polling conflicts", () => {
  expect(
    isTelegramPollingConflictError({
      method: "sendMessage",
      error_code: 400,
      description: "Bad Request",
    }),
  ).toBe(false);
});

test("polling conflict retry delay is short and fixed", () => {
  expect(TELEGRAM_POLLING_CONFLICT_RETRY_DELAY_MS).toBe(1_000);
});
