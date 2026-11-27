#!/usr/bin/env bash
# Start the backend and PowerSync, wait until they are healthy, create the
# seed accounts. Safe to run again. Needs only Docker.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bb_compose up -d --wait --remove-orphans
"$BB_DEV_DIR/seed.sh"
echo
echo "Backend is up. Mail inbox: $BB_MAIL_URL"
echo "Run the app:   dev/defines.sh emulator > env/dev.json"
echo "               flutter run -d <device-id> --flavor dev --dart-define-from-file=env/dev.json"
echo "Sign-in code:  dev/code.sh owner@busybuddy.test"
