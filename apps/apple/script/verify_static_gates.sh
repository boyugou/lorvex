#!/usr/bin/env bash
# Runs verify_all.sh's static tier on its own: the Python verifiers, the script unit tests,
# and the embedded-schema check. The tier starts no Swift build or test, launches no app, and
# never reads or writes Lorvex data, so it finishes in under a minute and is safe on a
# machine that holds real data. Run it before cutting a TestFlight build: the full gate in
# verify_all.sh builds and launches the app, so it cannot run on such a machine, and a gate
# that nothing runs drifts. The localized-string argument check is not part of the tier
# because it needs its own incremental macOS build.
#
# The tier is the region of verify_all.sh between its begin and end marker lines, so the
# list of gates has one source and the standalone run cannot fall behind the full gate.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
cd "$ROOT_DIR"

TIER="$(awk '
  $0 == "# --- static tier: begin ---" { inside = 1; next }
  $0 == "# --- static tier: end ---" { inside = 0 }
  inside
' script/verify_all.sh)"
if [[ -z "$TIER" ]]; then
  echo "verify_static_gates: script/verify_all.sh has no static tier between its markers" >&2
  exit 1
fi
eval "$TIER"
echo "verify_static_gates: every static gate passed"
