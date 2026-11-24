#!/usr/bin/env bash
# Start the backend and PowerSync, wait until they are healthy, create the
# seed accounts. Safe to run again. Needs only Docker.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bb_compose up -d --wait --remove-orphans
"$BB_DEV_DIR/seed.sh"
echo
echo "Backend is up. Mail inbox: $BB_MAIL_URL"
echo "Run the app:   flutter run -d <device-id> \$(dev/defines.sh emulator)"
echo "Sign-in code:  dev/code.sh owner@busybuddy.test"
