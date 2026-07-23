#!/usr/bin/env bash
# require_schema_freeze_gate.sh — Shared release-path gate: refuse to
# produce a distributable MAS/iOS archive unless verify_schema_freeze.py
# reports the schema-freeze tripwire ARMED (schema/migration_policy.json
# "launched": true). Sourced by archive_mas.sh and archive_ios.sh before any
# archive/export step, so a pre-freeze schema.sql can never reach an
# App-Store-bound artifact.
#
# Lorvex is currently pre-launch, so the gate is SKIPPABLE for local
# pre-launch builds only via an explicit LORVEX_ALLOW_UNFROZEN=1. Real
# release packaging defaults to REQUIRING the freeze to be armed — this
# script never sets that variable itself; the caller (a human running a real
# release) must opt in deliberately.
#
# Usage: source this file, then call:
#   require_schema_freeze_armed "$ROOT_DIR"
# where ROOT_DIR is the apps/apple directory (the one containing script/).
# Returns 0 (armed-and-intact, or explicitly skipped pre-launch) or 1
# (not armed and not skipped, or verify_schema_freeze.py found a violation).

require_schema_freeze_armed() {
  local root_dir="$1"
  local embed_verifier="$root_dir/script/verify_schema_embed.sh"
  local ladder_verifier="$root_dir/script/verify_migration_ladder.py"
  local payload_verifier="$root_dir/script/verify_sync_payload_contract.py"
  local freeze_verifier="$root_dir/script/verify_schema_freeze.py"
  local embed_output ladder_output payload_output freeze_output
  local embed_status ladder_status payload_status freeze_status
  local errexit_was_set=0

  # Capture the exit status of the verifier without letting a nonzero result
  # trip the caller's `set -e` mid-assignment (bash aborts immediately on
  # `var=$(failing-command)` under errexit), then restore whatever errexit
  # state the caller actually had — never force it on for a caller that
  # didn't set it.
  case "$-" in
    *e*) errexit_was_set=1 ;;
  esac
  set +e
  embed_output="$("$embed_verifier" 2>&1)"
  embed_status=$?
  ladder_output="$(python3 "$ladder_verifier" 2>&1)"
  ladder_status=$?
  payload_output="$(python3 "$payload_verifier" 2>&1)"
  payload_status=$?
  freeze_output="$(python3 "$freeze_verifier" --release 2>&1)"
  freeze_status=$?
  [[ "$errexit_was_set" -eq 1 ]] && set -e

  printf '%s\n' "$embed_output"
  printf '%s\n' "$ladder_output"
  printf '%s\n' "$payload_output"
  printf '%s\n' "$freeze_output"

  if [[ "$embed_status" -ne 0 || "$ladder_status" -ne 0 \
    || "$payload_status" -ne 0 || "$freeze_status" -ne 0 ]]; then
    echo "schema-freeze gate: FAILED — release schema validation reported a violation (see above)." >&2
    return 1
  fi

  if grep -q "tripwire DORMANT" <<<"$freeze_output"; then
    if [[ "${LORVEX_ALLOW_UNFROZEN:-0}" == "1" ]]; then
      echo "schema-freeze gate: SKIPPED — LORVEX_ALLOW_UNFROZEN=1 (pre-launch local build; the freeze is not armed)." >&2
      return 0
    fi
    echo "schema-freeze gate: FAILED — the schema freeze is not armed (migration_policy.json launched=false)." >&2
    echo "Release packaging (MAS/iOS archiving) requires the freeze to be armed before it can ship:" >&2
    echo "  $root_dir/script/verify_schema_freeze.py --arm" >&2
    echo "For a pre-launch local build only, explicitly opt out with:" >&2
    echo "  LORVEX_ALLOW_UNFROZEN=1" >&2
    return 1
  fi

  echo "schema-freeze gate: PASSED — schema freeze is armed and intact." >&2
  return 0
}
