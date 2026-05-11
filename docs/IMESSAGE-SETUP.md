# iMessage and email draft setup

This relay can do two things with iMessages and email:

1. **Read iMessage context** (recent thread with a contact) so the bot can draft a reply that matches your actual conversation history.
2. **Drop a draft into your native compose surface** (Messages.app or Mail.app) addressed to the right recipient, ready for you to review and send manually.

The bot will never send a message for you. That is a hard rule.

These two capabilities have different macOS permission requirements. Setup is one-time per machine.

## Capability 1: drop a draft (no permission grant needed)

These work out of the box:

```bash
# iMessage
echo "Hey Peggy, ..." | scripts/draft-imessage.sh +16043154583

# Email
echo "Body text" | scripts/draft-email.sh wregan599@gmail.com "Subject line"
```

Mechanism:

- iMessage draft: the body is copied to your clipboard, then `open imessage://+RECIPIENT` focuses Messages.app on the thread with that contact. You paste with Cmd+V and click send.
- Email draft: the body is URL-encoded into a `mailto:` URL, which opens your default mail client with a new draft pre-filled. The body is also copied to the clipboard as a safety net in case the URL was truncated.

No Full Disk Access, no Automation permission, no Accessibility permission. The bot can call these via its Bash tool at any time.

## Capability 2: read iMessage context (requires Full Disk Access)

The bot needs to read `~/Library/Messages/chat.db` to pull recent messages with a contact. macOS protects this file behind Full Disk Access (FDA).

### One-time setup

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click the **+** button.
3. Press **Cmd+Shift+G** to open the path picker.
4. Paste this path and press Return:

   ```
   /Users/williamregan/.local/share/claude/versions
   ```

5. Select the most recent versioned binary in there (e.g. `2.1.138`). Click Open.
6. Make sure the toggle next to that entry is **on**.
7. Restart the relay so the running Claude subprocesses pick up the new permission:

   ```bash
   launchctl kickstart -k gui/$(id -u)/com.claude.telegram-relay
   ```

8. (Optional) Verify by running the read helper directly with one of your contacts:

   ```bash
   ~/Projects/claude-telegram-relay/scripts/imessage-thread.sh +16043154583 5
   ```

   If FDA is correctly granted you will see JSON rows for the last 5 messages. If you see `error: cannot read /Users/.../chat.db`, FDA is not granted to the binary that ran sqlite3.

### Why this exact binary

The relay does not run from a terminal. It runs as a launchd service that spawns `bun` (the relay process) which then spawns the Claude CLI as a child. macOS TCC (Transparency, Consent, Control) tracks FDA per executable. The Claude CLI is the process that actually invokes the Bash tool that ends up calling `sqlite3`, so granting FDA to the Claude CLI binary covers the whole chain.

If you upgrade the Claude CLI later, a new versioned folder appears under `~/.local/share/claude/versions/`. macOS will block reads again until you grant FDA to the new versioned binary. Re-run the grant if that happens.

### What does NOT work

- Granting FDA to Terminal.app, iTerm, Warp, Ghostty, or any GUI shell. The relay does not run inside any of them.
- Granting FDA to `bun` at `/usr/local/bin/bun`. That covers the relay parent process but not the Claude subprocess that runs the Bash tool.
- Granting FDA only to the symlink at `~/.local/bin/claude`. macOS resolves the symlink and grants the underlying binary; toggling the symlink in System Settings sometimes works but is fragile across upgrades.

### Privacy note

When FDA is granted, the bot reads `chat.db` directly. Messages stay on this machine and never leave the bot's local context unless you tell it to forward them somewhere. The helper script enforces read-only mode (`sqlite3 -readonly`) so the bot cannot accidentally modify your message history.

## When this is unavailable

If the user has not granted FDA, the bot should not pretend it read iMessages. It should draft from the description the user gives and say explicitly that it had no real conversation history to draw on.
