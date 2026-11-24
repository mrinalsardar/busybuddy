#!/usr/bin/env bash
# Run `flutter pub get`, `flutter analyze` and `flutter test` in the pinned
# toolchain image (builds it on first use). With arguments, runs that command
# instead, e.g. dev/test.sh flutter test test/data_integrity_test.dart
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bb_compose run --rm test "$@"
