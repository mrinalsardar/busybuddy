#!/usr/bin/env bash
# Print the --dart-define flags that point the app at this stack.
#   emulator  Android emulator: it reaches your computer at 10.0.2.2
#   desktop   an app that runs on your computer: 127.0.0.1
# Use it as: flutter run -d <device-id> $(dev/defines.sh emulator)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${1:-}" in
  emulator) host=10.0.2.2 ;;
  desktop) host=127.0.0.1 ;;
  *) echo "usage: dev/defines.sh emulator|desktop" >&2; exit 2 ;;
esac
echo "--dart-define=SUPABASE_URL=http://$host:54321" \
  "--dart-define=SUPABASE_ANON_KEY=$BB_ANON_KEY" \
  "--dart-define=POWERSYNC_URL=http://$host:8080"
