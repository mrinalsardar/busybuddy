#!/usr/bin/env bash
# Print the build values that point the app at this stack, in the env/<env>.json
# format (see env/example.json).
#   emulator  Android emulator: it reaches your computer at 10.0.2.2
#   desktop   an app that runs on your computer: 127.0.0.1
# Use it as:
#   dev/defines.sh emulator > env/dev.json
#   flutter run -d <device-id> --flavor dev --dart-define-from-file=env/dev.json
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${1:-}" in
  emulator) host=10.0.2.2 ;;
  desktop) host=127.0.0.1 ;;
  *) echo "usage: dev/defines.sh emulator|desktop" >&2; exit 2 ;;
esac
printf '{\n  "SUPABASE_URL": "http://%s:54321",\n  "SUPABASE_ANON_KEY": "%s",\n  "POWERSYNC_URL": "http://%s:8080"\n}\n' \
  "$host" "$BB_ANON_KEY" "$host"
