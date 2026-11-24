#!/usr/bin/env bash
# Create the throwaway accounts in $BB_SEED_EMAILS (confirmed, no password:
# sign in with an emailed code, see code.sh). Safe to run again.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for email in "${BB_SEED_EMAILS[@]}"; do
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BB_API_URL/auth/v1/admin/users" \
    -H "apikey: $BB_SERVICE_KEY" -H "Authorization: Bearer $BB_SERVICE_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"email_confirm\":true}")
  case "$status" in
    200) echo "created  $email" ;;
    422) echo "exists   $email" ;;
    *) echo "seed failed for $email (HTTP $status). Is the stack up? Try dev/up.sh" >&2; exit 1 ;;
  esac
done
