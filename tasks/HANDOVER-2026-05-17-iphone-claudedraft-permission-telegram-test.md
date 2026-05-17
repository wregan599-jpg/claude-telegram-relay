# Claude Telegram Relay Handover - iPhone ClaudeDraft Permission + Telegram UI Test

Date: 2026-05-17  
Repo: `/Users/williamregan/Projects/claude-telegram-relay`  
Branch: `relay/anesthesia-corpus-portability`  
Latest pushed commit: `dd487f1 relay: surface pending iPhone shortcut install`

## Executive Summary

The relay code is now correctly writing iMessage draft handoff data for Dad, and this was verified by sending a real command through the Mac Telegram app UI.

The remaining failure is iPhone-side:

- `ClaudeDraft.shortcut` still exists in iCloud Drive as a pending install/replace artifact.
- The iPhone showed the real prompt:
  `Allow "ClaudeDraft" to access your "claude-relay-drafts" folder?`
- Before Codex could tap `OK`, iPhone Mirroring disconnected and became stuck at:
  `Connecting to iPhone 14`

Do not treat this as a TypeScript relay failure anymore. The relay produced the correct handoff. The current blocker is completing the iPhone Shortcuts permission/install flow and then deleting the pending install artifact.

## What Was Changed In Code

Commit:

```text
dd487f1 relay: surface pending iPhone shortcut install
```

Files changed:

```text
src/relay.ts
src/telegram-response.test.ts
tasks/lessons.md
```

### Why

Before this patch, if the relay successfully wrote `latest.json`, it replied as if the iPhone shortcut was ready:

```text
Drafting to dad (+16048092405). Run ClaudeDraft in Shortcuts on your iPhone.
```

That was misleading while this file still existed:

```text
/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/ClaudeDraft.shortcut
```

That file means the fixed shortcut still needs to be installed/replaced on the iPhone.

### New Behavior

When the pending install artifact exists, the relay now returns a truthful pending-install status:

```text
heading to London

ClaudeDraft is not installed on your iPhone yet. Open Files > iCloud Drive > ClaudeDraft.shortcut, tap Replace or Add Shortcut, then run ClaudeDraft. Draft target: dad (+16048092405).
```

Decision log now records:

```text
imessage_draft_status: phone_shortcut_install_pending
imessage_draft_mode: icloud_drive_file
```

This prevents another false-success loop.

## Mirroir / iPhone Work Performed

The user explicitly authorized:

```text
replace ClaudeDraft
allow folder
```

Codex used Mirroir MCP through the existing repo scripts.

### Attempt 1 - Install/Replace Shortcut

Command:

```bash
node scripts/iphone-final-install.cjs
```

Observed iPhone state:

```text
All Shortcuts
ClaudeDraft
Pipewrench
SearchMyFiles-final
SearchMyFiles-signed
...
```

The script tapped `ClaudeDraft`.

The iPhone then displayed this permission prompt:

```text
Allow "ClaudeDraft" to access your "claude-relay-drafts" folder?
OK
Cancel
```

That prompt is expected. It is the missing iPhone-side permission required for `ClaudeDraft` to read:

```text
/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/claude-relay-drafts/latest.json
```

The existing install script did not recognize `OK` as an install/permission button, so it stopped without tapping it.

### Attempt 2 - Tap OK

After the user authorized `allow folder`, Codex tried to tap `OK`.

However, iPhone Mirroring had disconnected. Mirroir repeatedly saw only:

```text
Connecting to
iPhone 14
```

Codex restarted iPhone Mirroring:

```bash
osascript -e 'tell application "iPhone Mirroring" to quit' || true
sleep 3
open -a "iPhone Mirroring"
```

Then rechecked through Mirroir. The screen still showed:

```text
Connecting to
iPhone 14
```

Therefore, the phone-side compose verification could not be completed in this run. Do not mark iPhone Shortcuts as fixed until a real phone compose-body check is observed.

## Real Telegram UI Test Performed

Codex used the Mac Telegram app, not a fake API call, to send a real command into the Telegram bot chat.

Command used to open the bot:

```bash
open -a Telegram 'tg://resolve?domain=wr_claude_20260427_bot'
```

Then Codex typed and sent through Telegram UI:

```text
Text dad saying Codex relay verification test - do not send
```

### Relay Log Evidence

Log tail showed:

```text
Message: Text dad saying Codex relay verification test - do...
[imessage-context] contact=dad status=found messages=10 render_context=false placement=true
[imessage-draft] icloud_drive_file for dad (+16048092405) path=/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/claude-relay-drafts/latest.json sha256=10ab455d614b37edd187b174f9f045164d8ee7637d66176335e83194c0597829
```

### latest.json Evidence

After the Telegram UI test, the relay wrote:

```json
{
  "recipient": "+16048092405",
  "recipient_label": "dad",
  "body": "Codex relay verification test - do not send",
  "ts": "2026-05-17T19:12:40.212Z",
  "body_sha256": "10ab455d614b37edd187b174f9f045164d8ee7637d66176335e83194c0597829"
}
```

Path:

```text
/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/claude-relay-drafts/latest.json
```

### Decision Log Evidence

Decision log entry:

```json
{
  "ts": "2026-05-17T19:12:39.098Z",
  "message": "Text dad saying Codex relay verification test - do not send",
  "imessage_draft_status": "phone_shortcut_install_pending",
  "imessage_draft_mode": "icloud_drive_file",
  "imessage_draft_handoff_path": "/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/claude-relay-drafts/latest.json",
  "imessage_draft_body_sha256": "10ab455d614b37edd187b174f9f045164d8ee7637d66176335e83194c0597829",
  "response_chars": 228,
  "error": null
}
```

### No-Send Proof

Codex checked the local Messages database for an outgoing send of the exact test body:

```bash
sqlite3 "$HOME/Library/Messages/chat.db" \
  "select count(*) from message where is_from_me=1 and text='Codex relay verification test - do not send' and date > ((strftime('%s','now','-2 hours') - 978307200) * 1000000000);"
```

Result:

```text
0
```

No iMessage was sent.

## Verification Commands And Results

### Unit Tests

Command:

```bash
bun test
```

Result:

```text
302 pass
0 fail
727 expect() calls
```

### Diff Check

Command:

```bash
git diff --check
```

Result:

```text
clean
```

### Relay Restart

Command:

```bash
bun run setup:launchd -- --service relay
```

Result:

```text
com.claude.telegram-relay loaded
Services are running
```

Active process:

```text
PID 81092
com.claude.telegram-relay
```

### Setup Verify

Command:

```bash
bun run setup:verify
```

Result:

```text
33 passed
1 failed
7 warnings
```

The single failure is the expected remaining blocker:

```text
Fixed ClaudeDraft iPhone install file still exists at /Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/ClaudeDraft.shortcut; install it on iPhone, confirm the body appears, then delete the file
```

## Current State

### Good

- Telegram relay is running.
- Telegram bot receives real UI-sent commands.
- Dad resolves to the correct number:

```text
+16048092405
```

- `latest.json` is written correctly.
- The relay no longer claims the iPhone shortcut works while install is pending.
- No iMessage was sent during testing.

### Not Yet Proved

The iPhone `ClaudeDraft` shortcut has not yet been verified to open Messages with the body populated after the folder permission prompt.

Reason:

```text
iPhone Mirroring disconnected and remained stuck at "Connecting to iPhone 14".
```

## Required Next Steps For Claude Code

Do not continue editing relay TypeScript until the iPhone-side verification is completed.

### Step 1 - Reconnect iPhone Mirroring

Get iPhone Mirroring out of:

```text
Connecting to iPhone 14
```

Likely manual actions if needed:

1. Unlock the iPhone physically.
2. Keep it near the Mac.
3. Confirm Wi-Fi/Bluetooth are on.
4. Quit and reopen iPhone Mirroring.

### Step 2 - Grant ClaudeDraft Folder Access

Once Mirroir can see the phone again, handle the prompt:

```text
Allow "ClaudeDraft" to access your "claude-relay-drafts" folder?
```

Tap:

```text
OK
```

### Step 3 - Run ClaudeDraft

On the iPhone:

1. Open Shortcuts.
2. Tap `ClaudeDraft`.
3. If iOS asks for Send Message permission, choose `Allow Once`, not `Always Allow`.
4. Confirm Messages opens with:

```text
To: Dad / +16048092405
Body: Codex relay verification test - do not send
```

Do not tap the send arrow.

### Step 4 - No-Send Check

Run:

```bash
sqlite3 "$HOME/Library/Messages/chat.db" \
  "select count(*) from message where is_from_me=1 and text='Codex relay verification test - do not send' and date > ((strftime('%s','now','-2 hours') - 978307200) * 1000000000);"
```

Expected:

```text
0
```

### Step 5 - Remove Pending Install Artifact

Only after a real iPhone compose-body verification succeeds, delete:

```text
/Users/williamregan/Library/Mobile Documents/com~apple~CloudDocs/ClaudeDraft.shortcut
```

Then rerun:

```bash
bun run setup:verify
```

Expected:

```text
0 failed
```

Warnings about optional Supabase/voice/check-in services may remain and are not blockers.

## Staff-Engineer Assessment

This should not be solved by rewriting the project.

The current state is narrow:

- relay parser: working
- Dad alias: working
- Telegram polling: working
- handoff JSON: working
- iMessage no-send safety: preserved
- iPhone Shortcut permission/install: still blocked

The correct next action is to finish the iPhone Shortcuts permission/installation flow and verify the compose body on the phone. Rewriting the repo would not fix iOS Shortcuts permission state.
