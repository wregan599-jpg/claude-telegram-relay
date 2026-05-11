#!/usr/bin/env bash
# imessage-thread.sh — print the most recent iMessages with a given contact
# as JSON. Used by the bot to gather context before drafting a reply.
#
# Usage:
#   scripts/imessage-thread.sh +16043154583 [LIMIT]
#
# Output (stdout, JSON array, one object per row):
#   [{"id":<int>,"sender":"me"|"them","ts":"<localtime>","text":"<message>"}, ...]
#
# Requires:
#   Full Disk Access on the process that ends up running sqlite3. When the
#   bot invokes this via the Claude CLI's Bash tool, that means FDA must be
#   granted to the resolved Claude binary at
#     /Users/williamregan/.local/share/claude/versions/<vN>
#   See docs/IMESSAGE-SETUP.md for the one-time setup.
#
# Output goes to the relay's local short-term context, never to a remote
# service. Read-only access to chat.db is enforced via -readonly.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 RECIPIENT [LIMIT] (RECIPIENT: phone like +16043154583, or email)" >&2
  exit 64
fi

RECIPIENT="$1"
LIMIT="${2:-20}"

# Normalize: strip a leading + so we can match both '+16045555555' and
# '16045555555' shapes in chat_identifier.
NAKED="${RECIPIENT#+}"

DB="$HOME/Library/Messages/chat.db"

if [[ ! -r "$DB" ]]; then
  cat <<EOF >&2
error: cannot read $DB
Full Disk Access is not granted for the current process. See
docs/IMESSAGE-SETUP.md for the one-time setup.
EOF
  exit 77
fi

sqlite3 -readonly "$DB" <<SQL
.mode json
SELECT
  m.ROWID AS id,
  CASE WHEN m.is_from_me = 1 THEN 'me' ELSE 'them' END AS sender,
  datetime(m.date / 1000000000 + 978307200, 'unixepoch', 'localtime') AS ts,
  m.text
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c ON c.ROWID = cmj.chat_id
WHERE c.chat_identifier IN ('$RECIPIENT', '+$NAKED', '$NAKED', '+1$NAKED')
  AND m.text IS NOT NULL
  AND m.text != ''
ORDER BY m.date DESC
LIMIT $LIMIT;
SQL
