#!/usr/bin/env bash
# Stop the stack. With --reset, also delete its data (database, PowerSync
# storage, mail) so the next up.sh starts from scratch. Touches only the
# containers and volumes of this Compose project (busybuddy-dev).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${1:-}" in
  "") bb_compose down --remove-orphans ;;
  --reset) bb_compose down --remove-orphans --volumes ;;
  *) echo "usage: dev/down.sh [--reset]" >&2; exit 2 ;;
esac
