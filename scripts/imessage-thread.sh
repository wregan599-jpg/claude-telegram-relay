#!/usr/bin/env bash
# imessage-thread.sh — print the most recent iMessages with a given contact
# as JSON. Used by the bot to gather context before drafting a reply.
#
# Usage:
#   scripts/imessage-thread.sh +16043154583 [LIMIT]
#
# Output (stdout, JSON envelope):
#   {"resolved":"<phone-or-email>","messages":[
#     {"id":<int>,"sender":"me"|"them","ts":"<localtime>","text":"<message>"},
#     ...
#   ]}
# When the recipient cannot be resolved, "resolved" is the empty string and
# "messages" is an empty array. The relay reuses the resolved value to address
# Messages.app deterministically when placing a draft.
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

DB="$HOME/Library/Messages/chat.db"
CONTACTS_DB="$HOME/Library/Application Support/AddressBook/AddressBook-v22.abcddb"

if [[ ! -r "$DB" ]]; then
  cat <<EOF >&2
error: cannot read $DB
Full Disk Access is not granted for the current process. See
docs/IMESSAGE-SETUP.md for the one-time setup.
EOF
  exit 77
fi

sql_string() {
  # SQLite single-quoted string escaping.
  printf "%s" "$1" | sed "s/'/''/g"
}

is_direct_identifier() {
  [[ "$1" =~ ^[+0-9][0-9[:space:]().-]{6,}$ || "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

allow_message_text_fallback() {
  local input_lc
  input_lc="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"

  # The message-text fallback is inherently weak: it finds a thread where the
  # word appeared in message text, not a contact whose name is that word. Keep
  # it away from short or relationship-style aliases like "mom", which can
  # otherwise resolve to the wrong one-on-one thread.
  if [[ ${#input_lc} -lt 4 ]]; then
    return 1
  fi

  if [[ "$input_lc" =~ (^|[^[:alpha:]])(me|myself|mom|mum|mother|dad|father|wife|husband|son|daughter|brother|sister|parent|parents)([^[:alpha:]]|$) ]]; then
    return 1
  fi

  return 0
}

resolve_recipient() {
  local input="$1"
  if is_direct_identifier "$input"; then
    printf "%s" "$input"
    return 0
  fi

  # Primary resolver: a Python helper that searches every AddressBook source
  # database (iCloud/Exchange/CardDAV subdirs under
  # ~/Library/Application Support/AddressBook/Sources/*/) and fuzzy-matches
  # the input against name tokens. The top-level AddressBook-v22.abcddb on
  # this Mac holds only the "me" record, which is why the old strict
  # substring query against just that DB always missed real contacts. The
  # helper handles direct identifiers, blocks relationship aliases, and
  # returns an empty string if no good match exists.
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  local resolver="$script_dir/resolve-contact.py"
  if [[ -x "$resolver" ]] && command -v python3 >/dev/null 2>&1; then
    local contact
    contact="$("$resolver" "$input" 2>/dev/null)"
    if [[ -n "$contact" ]]; then
      printf "%s" "$contact"
      return 0
    fi
  fi

  if ! allow_message_text_fallback "$input"; then
    return 0
  fi

  # Last-resort fallback for contacts not saved in any AddressBook source:
  # find a one-on-one thread where the specific name appears in message
  # text, then use that chat identifier. Do not use this for short or
  # relationship-style aliases; those are too ambiguous to place a draft
  # safely.
  local q
  q="$(sql_string "$input")"
  sqlite3 -readonly "$DB" <<SQL
SELECT c.chat_identifier
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c ON c.ROWID = cmj.chat_id
WHERE lower(m.text) LIKE '%' || lower('$q') || '%'
  AND c.chat_identifier NOT LIKE 'chat%'
GROUP BY c.ROWID
ORDER BY MAX(m.date) DESC
LIMIT 1;
SQL
}

RESOLVED_RECIPIENT="$(resolve_recipient "$RECIPIENT")"
if [[ -z "$RESOLVED_RECIPIENT" ]]; then
  printf '{"resolved":"","messages":[]}\n'
  exit 0
fi

# Normalize: strip a leading + so we can match both '+16045555555' and
# '16045555555' shapes in chat_identifier.
NAKED="${RESOLVED_RECIPIENT#+}"
SQL_RECIPIENT="$(sql_string "$RESOLVED_RECIPIENT")"
SQL_NAKED="$(sql_string "$NAKED")"

MESSAGES_JSON="$(sqlite3 -readonly "$DB" <<SQL
.mode json
SELECT
  m.ROWID AS id,
  CASE WHEN m.is_from_me = 1 THEN 'me' ELSE 'them' END AS sender,
  datetime(m.date / 1000000000 + 978307200, 'unixepoch', 'localtime') AS ts,
  m.text
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c ON c.ROWID = cmj.chat_id
WHERE c.chat_identifier IN ('$SQL_RECIPIENT', '+$SQL_NAKED', '$SQL_NAKED', '+1$SQL_NAKED')
  AND m.text IS NOT NULL
  AND m.text != ''
ORDER BY m.date DESC
LIMIT $LIMIT;
SQL
)"

# sqlite3 .mode json emits nothing for zero rows; coerce to an empty array so
# the envelope is always valid JSON.
[[ -z "$MESSAGES_JSON" ]] && MESSAGES_JSON='[]'

# Resolved recipient is always a phone, email, or sanitized chat_identifier
# (group-chat ids are filtered out upstream), so it never contains characters
# that would break this raw JSON embedding.
printf '{"resolved":"%s","messages":%s}\n' "$RESOLVED_RECIPIENT" "$MESSAGES_JSON"
