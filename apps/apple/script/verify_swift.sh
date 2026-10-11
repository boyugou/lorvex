#!/usr/bin/env bash
# verify_swift.sh - the check to run before a commit that touches Swift: builds every
# target and test target, compiles the string catalogs into the resource bundles, and
# runs the full Swift suite.
#
# Usage:
#   script/verify_swift.sh                       build, compile catalogs, run every test
#   script/verify_swift.sh --filter MobileHabit  extra arguments go to `swift test`
#   script/verify_swift.sh --core                also run the core package's own suite
#
# Why not `swift build && swift test`: the native SwiftPM build system, the default of
# Xcode 26.x, copies the string catalogs without compiling them, so about thirty
# localization tests fail on a plain run. Swift Build, the default from Xcode 27,
# compiles them itself. The compile step is idempotent, so this script is correct
# under either system. A `--filter` run skips the source-pin tests; run the whole
# suite before committing.
#
# It starts no app and reads or writes no Lorvex data. The exit status is the first
# failing stage's.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_CORE=0
if [[ "${1:-}" == "--core" ]]; then
  RUN_CORE=1
  shift
fi
JOBS="${LORVEX_JOBS:-4}"

swift build -j "$JOBS" --build-tests
./script/compile_xcstrings.sh
swift test --skip-build -j "$JOBS" "$@"
if (( RUN_CORE )); then
  (cd core && swift test -j "$JOBS")
fi
