#!/usr/bin/env bash
# Print the newest 6-digit sign-in code mailed to <email>. Waits up to 15 s for
# the mail. In the app, ask for the code first, then run this.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || { echo "usage: dev/code.sh <email>" >&2; exit 2; }
email=$1

for _ in $(seq 1 15); do
  id=$(curl -s -G "$BB_MAIL_URL/api/v1/search" --data-urlencode "query=to:$email" \
    | grep -oE '"ID":"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)
  if [ -n "$id" ]; then
    code=$(curl -s "$BB_MAIL_URL/api/v1/message/$id" \
      | grep -oE '"Text":"[^"]*"' | grep -oE '[0-9]{6}' | head -n 1 || true)
    if [ -n "$code" ]; then echo "$code"; exit 0; fi
  fi
  sleep 1
done
echo "no sign-in mail for $email at $BB_MAIL_URL. Did the app ask for a code?" >&2
exit 1
