# iMessage iPhone Handoff (ClaudeDraft Shortcut)

When the bot drafts an iMessage and a recipient resolves, the relay drops the
draft into an iCloud file on this Mac and replies with a `shortcuts://` link.
Tap that link on the iPhone and the iOS `ClaudeDraft` Shortcut reads the file
and opens a pre-filled Messages compose sheet for review. **The shortcut never
sends — only William's manual tap on the compose Send button does.**

```
Telegram draft request  ─►  relay resolves recipient
                            └► writes latest.json to Shortcuts iCloud container
                            └► Telegram reply ends with the shortcuts:// link
iPhone (tap link)       ─►  ClaudeDraft reads latest.json
                            └► Messages compose sheet appears, body pre-filled
                            └► William reviews → taps Send (or cancels)
```

## Runtime contract

Path (atomic write, `wx` + rename, mode `0600`, parent dir `0700`):

```
~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/claude-relay-drafts/latest.json
```

Source: [`src/icloud-drive-draft.ts`](../src/icloud-drive-draft.ts) (writer)
and [`src/relay.ts`](../src/relay.ts) (placement block, ~line 770).

Payload (always overwritten; no append, no history):

```json
{
  "recipient": "+15198545324",           // phone (E.164) OR email
  "recipient_label": "William",          // display name, used in relay logs only
  "body": "draft text",                  // plaintext; iPhone needs to read it
  "ts": "2026-05-13T13:30:00.000Z",      // ISO 8601 UTC
  "body_sha256": "..."                   // hex SHA-256 of body, for log correlation
}
```

`recipient` accepts either a phone number or an email — Messages picks the
right transport. `body_sha256` lets `decision-log.jsonl` rows correlate
to the exact draft a Shortcut run consumed without ever storing the body.

## Build the Shortcut (do this once on the Mac)

The macOS Shortcut iCloud-syncs to the iPhone automatically — **Shortcuts →
Settings → iCloud Sync must be ON on both devices.** Build it on the Mac, not
the phone (Mac editor is easier and you can test before the iPhone copy lands).

Name it **exactly** `ClaudeDraft` (case-sensitive). The relay's URL is
hardcoded: `shortcuts://run-shortcut?name=ClaudeDraft`. Override only by
setting `RELAY_IMESSAGE_SHORTCUT_NAME` in the relay env (see below).

The chain is **5 actions** — no more, no less:

| # | UI action name (action identifier) | Settings that matter |
|---|---|---|
| 1 | **Get File** (`is.workflow.actions.documentpicker.open`) | File: `claude-relay-drafts/latest.json` · Show File Picker **OFF** · Error If Not Found **ON**. The editor will display this as "Get file from **Shortcuts** at path..." — "Shortcuts" is the Files-app provider name for the Shortcuts iCloud container, which is exactly where the relay writes. |
| 2 | **Get Dictionary from Input** (`is.workflow.actions.detect.dictionary`) | Defaults. Parses the JSON file contents. |
| 3 | **Get Dictionary Value** (`is.workflow.actions.getvalueforkey`) | Key: `recipient` |
| 4 | **Get Dictionary Value** (`is.workflow.actions.getvalueforkey`) | Key: `body` |
| 5 | **Send Message** (`is.workflow.actions.sendmessage`) | Recipient: the magic var from step 3 · Message: the magic var from step 4 · **"Show When Run" toggle: ON** (under "Show More"). |

> ### ⚠ The one rule that ships drafts vs. real messages
>
> Step 5's **"Show When Run"** toggle is the entire safety contract. When
> **ON**, the OS shows the compose sheet for manual review. When **OFF**, the
> shortcut auto-sends the iMessage with no confirmation. There is no other
> action, wrapper, or setting that prevents auto-send. **Never** wrap Send
> Message in a "Wait → Send", "Run Shortcut", or any auto-confirm step.

You do not need a separate "Get Contents of File" action between steps 1 and 2
— `Get File` with picker off returns the file content directly as the
downstream input for `Get Dictionary from Input`.

## First run (Mac verification — do this before iPhone)

Run from Terminal so you can observe failures without consuming the iPhone
link. Make sure a fixture exists first:

```bash
ls -la "$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/claude-relay-drafts/latest.json"
# If absent, send a draft via Telegram with a self-safe recipient
# (e.g. "Draft a message to William saying handoff-test"); the relay writes
# a fresh latest.json on every placement.

shortcuts run ClaudeDraft
```

First run only — macOS shows an OS-level prompt:

> Allow "ClaudeDraft" to send 1 dictionary in a message?
> [Don't Allow] [Allow Once] [Always Allow]

Pick **Allow Once** for testing (or **Always Allow** once you trust it). The
word "dictionary" is the OS describing the upstream data type — only the
extracted `body` string and the `recipient` reach Messages.app.

Expected after Allow Once:

- Messages compose sheet opens, recipient field pre-filled, body pre-filled.
- **No iMessage is sent.** Close the sheet (Cancel or ⌘W).
- Confirm in `~/Library/Messages/chat.db` that no new row appeared for that
  recipient during the test.

If `shortcuts run` instead exits with `Error: ... no such file`, the relay
hasn't written `latest.json` since the last cleanup — send a Telegram draft
request first.

If it exits with `Error: The provided file path must be contained within
the directory`, the Get File action has both a `WFFile` bookmark and a
`WFGetFilePath` set — re-pick the file with the picker so they reconcile, or
remove the path field entirely.

## iPhone verification (once Mac path works)

1. Verify the shortcut synced: Shortcuts.app on iPhone → All Shortcuts →
   `ClaudeDraft` appears. If not, wait ~1 min or toggle iCloud Sync off/on.
2. Send a fresh draft request in Telegram (e.g. "Draft a message to William
   saying iphone-handoff-test").
3. Tap the `shortcuts://run-shortcut?name=ClaudeDraft` link in the bot reply.
4. First run on iPhone repeats the **Allow / Allow Once / Always Allow**
   prompt — same answer.
5. Messages compose sheet appears with the body. Close without sending.

## Self-test fixture

The relay supports a self-addressed test payload by accepting William's own
email/phone as the resolved recipient (e.g. `wregan599@gmail.com`). A draft
with `recipient_label: "ClaudeDraft self-test"` arrives in his own iMessage
inbox if accidentally sent — recoverable. Use this shape for any end-to-end
test that might be tempted to tap Send.

## Environment overrides

Set in the relay environment if defaults don't fit:

```bash
RELAY_ICLOUD_DRAFT_DIR=/custom/abs/path/claude-relay-drafts
RELAY_IMESSAGE_SHORTCUT_NAME=ClaudeDraft
```

`RELAY_ICLOUD_DRAFT_DIR` must point inside an iCloud-synced container that
the iOS Shortcut can read. If you point it at iCloud Drive root
(`~/Library/Mobile Documents/com~apple~CloudDocs/...`), the Shortcut's
`Get File` action also has to be re-pointed at iCloud Drive via a `WFFile`
bookmark — the default "Shortcuts" provider only reads the Shortcuts
container. Keeping both sides on the Shortcuts container is the simpler
configuration and is the default.

`RELAY_IMESSAGE_SHORTCUT_NAME` only matters if you also rename the iOS
Shortcut — the relay just embeds it in the `shortcuts://` URL.

## Verifying the handoff fired (from logs, not the Mac UI)

Each placement appends one row to today's
`~/.claude-relay/logs/decisions-YYYY-MM-DD.jsonl`. Relevant fields:

| field | value when handoff succeeded |
|---|---|
| `imessage_draft_mode` | `"icloud_drive_file"` |
| `imessage_draft_handoff_path` | absolute path to the written `latest.json` |
| `imessage_draft_body_sha256` | hex SHA-256 of the body, never the body itself |
| `imessage_draft_shortcut_url` | the `shortcuts://run-shortcut?name=...` reply embedded in Telegram |

If `imessage_draft_mode` is `"pasted"` or `"new_compose"` instead, the iCloud
write failed and the relay fell back (see next section). If
`imessage_draft_mode` is absent for a draft request that resolved a recipient,
check `relay.err.log` for `[imessage-draft] Shortcuts iCloud handoff failed`
— the message names the root cause (missing iCloud container, permission,
disk).

## Fallback path (kept; do not remove)

If the iCloud write throws (e.g. iCloud daemon offline, container missing
because the user hasn't opened Shortcuts.app once, disk full), the relay
falls through to `placeIMessageDraft()` in `src/relay.ts`, which uses the
existing AppleScript / Messages compose path on the Mac. The Telegram reply
in that case omits the `shortcuts://` URL and the body lands directly in the
Mac Messages compose box. This is the right behaviour for "I'm at my Mac
anyway" — but the iPhone won't get a tappable handoff.

## Anti-patterns (review these before editing)

- Adding any action after Send Message that auto-confirms ("Wait 5 seconds →
  Send", "Run Shortcut: AutoSend"). Show When Run + a human tap is the only
  legal path.
- Renaming the Shortcut without setting `RELAY_IMESSAGE_SHORTCUT_NAME`.
- Hard-coding the recipient or body in the Shortcut — they MUST come from
  `latest.json`. This is what makes the relay → phone hop work at all.
- Pointing the Shortcut at iCloud Drive root without also setting
  `RELAY_ICLOUD_DRAFT_DIR` to match. The relay default and the Shortcut
  default both target the Shortcuts container; keep them aligned.
- Removing the Mac fallback path. The iCloud handoff is best-effort; the
  fallback is what keeps the relay useful when you're at the Mac and the
  cloud round-trip is unnecessary.

## Programmatic rebuild (for future automation)

The macOS `shortcuts` CLI has no `create` subcommand. To rebuild ClaudeDraft
from a script: author a binary plist with the 5 actions above, sign with
`shortcuts sign --mode anyone --input ClaudeDraft.shortcut --output
ClaudeDraft.shortcut` (input MUST have the `.shortcut` extension), then
`open ClaudeDraft.shortcut` and accept the `Add Shortcut` dialog. A working
reference plist generator with the exact magic-variable wiring lives in the
session lessons under
[`tasks/lessons.md` § 2026-05-13 plist+sign route](../tasks/lessons.md).
