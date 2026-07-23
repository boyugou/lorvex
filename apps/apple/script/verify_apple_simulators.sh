#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -a RESULTS=()
HARD_FAILURE=0
UNAVAILABLE=0

run_verifier() {
  local label="$1"
  local script_path="$2"
  local status=0

  echo "== Verifying $label =="
  "$script_path" || status=$?

  if [[ "$status" -eq 0 ]]; then
    RESULTS+=("$label: passed")
  elif [[ "$status" -eq 78 ]]; then
    RESULTS+=("$label: unavailable")
    UNAVAILABLE=1
  else
    RESULTS+=("$label: failed ($status)")
    HARD_FAILURE=1
  fi
}

run_verifier "iOS simulator" "$ROOT_DIR/script/verify_mobile_simulator.sh"
run_verifier "visionOS simulator" "$ROOT_DIR/script/verify_vision_simulator.sh"
run_verifier "watchOS simulator" "$ROOT_DIR/script/verify_watch_simulator.sh"
# Not a simulator build: the unsigned device Release graph. Release
# optimization resolves opaque types across framework boundaries, and enforces
# each platform's real deployment-target floor, so compile/link failures can
# exist that Debug/simulator builds (and SwiftPM's single-unit link) never
# surface — see verify_release_link.sh's header.
run_verifier "iOS Release link" "$ROOT_DIR/script/verify_mobile_release_link.sh"
run_verifier "visionOS Release link" "$ROOT_DIR/script/verify_vision_release_link.sh"

printf '\nApple platform build verification summary:\n'
printf ' - %s\n' "${RESULTS[@]}"

if [[ "$HARD_FAILURE" -ne 0 ]]; then
  exit 1
fi

if [[ "$UNAVAILABLE" -ne 0 ]]; then
  echo "Apple platform build verification incomplete: install the matching Xcode simulator runtimes / platform SDKs and rerun."
  exit 78
fi

echo "Apple platform build verification passed"
