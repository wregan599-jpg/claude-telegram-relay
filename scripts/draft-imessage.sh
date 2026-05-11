#!/usr/bin/env bash
# draft-imessage.sh — drop an iMessage draft into the Messages.app compose
# surface without sending it. Reads the draft body from stdin and the
# recipient from $1.
#
# Usage:
#   echo "Hey Peggy ..." | scripts/draft-imessage.sh +16043154583
#   echo "Hi mom" | scripts/draft-imessage.sh mom@icloud.com
#
# Mechanism:
#   1. Read body from stdin and copy to the macOS clipboard via pbcopy.
#   2. Open the Messages conversation with the given recipient via the
#      imessage:// URL scheme. macOS focuses Messages on the right thread.
#   3. Print a one-line instruction telling the user to paste (Cmd+V) and
#      review before sending. NEVER sends the message.
#
# Why this design:
#   - No Full Disk Access required (clipboard + open are unrestricted).
#   - No Automation/Accessibility permission required.
#   - Honors the hard rule that the bot never sends; user always reviews
#     and sends manually.
#
# See: docs/IMESSAGE-SETUP.md for the read-context path which DOES need FDA.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 RECIPIENT (phone like +16043154583 or email)" >&2
  exit 64
fi

RECIPIENT="$1"
BODY="$(cat)"

if [[ -z "$BODY" ]]; then
  echo "error: empty draft body on stdin" >&2
  exit 65
fi

printf '%s' "$BODY" | pbcopy

# imessage:// URL handles both phone numbers and emails. Phone numbers should
# include the country code, e.g. +16043154583.
open "imessage://$RECIPIENT"

cat <<EOF
Draft copied to clipboard. Messages.app is open on the thread with $RECIPIENT.
Paste with Cmd+V, review, then send manually. The relay will not send for you.
EOF
