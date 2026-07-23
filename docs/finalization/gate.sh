#!/usr/bin/env bash
# Combined full gate. Logs step-by-step to the LOG file and exits non-zero if
# ANY step fails (the exit code is the number of failed steps). Also runs the
# newer migration/acknowledgment/privacy gates.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 99
LOG="${TMPDIR:-/tmp}/lorvex-gate.log"
TMPD="${TMPDIR:-/tmp}"
: > "$LOG"

FAILURES=0
runstep() {
  local label="$1" cmd="$2" filter="${3:-tail -4}"
  local tmp="$TMPD/gstep_$$_${RANDOM}.out"
  bash -c "set -o pipefail; $cmd" > "$tmp" 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then FAILURES=$((FAILURES + 1)); fi
  echo "### $label (exit $rc)" >> "$LOG"
  bash -c "$filter" < "$tmp" >> "$LOG" 2>&1
  rm -f "$tmp"
}

if [ -z "$(git status --porcelain)" ]; then echo "### CLEAN" >> "$LOG"; else echo "### DIRTY" >> "$LOG"; git status --porcelain >> "$LOG"; fi

runstep "app build"          "cd apps/apple && swift build"                                  "tail -3"
runstep "core test"          "cd apps/apple/core && swift test"                              "grep -E 'Executed [0-9]+ tests|error:|Fatal error' | tail -4"
runstep "app test"           "cd apps/apple && swift test"                                   "grep -E 'Test run with|Executed [0-9]+ tests|[0-9]+ failed|error:' | tail -5"
runstep "hotspots"           "cd apps/apple && python3 script/verify_hotspots.py"            "tail -2"
runstep "manifest"           "cd apps/apple && python3 script/verify_mcp_tool_manifest.py"   "tail -2"
runstep "user_docs"          "cd apps/apple && python3 script/verify_user_docs.py"           "tail -2"
runstep "metadata"           "cd apps/apple && python3 script/verify_app_metadata.py"        "tail -2"
runstep "localization"       "cd apps/apple && python3 script/verify_localization_catalog.py" "tail -2"
runstep "schema-embed"       "cd apps/apple && bash script/verify_schema_embed.sh"           "tail -2"
runstep "migration-ladder"   "cd apps/apple && python3 script/verify_migration_ladder.py"    "tail -2"
runstep "privacy-manifests"  "cd apps/apple && python3 script/verify_privacy_manifests.py"   "tail -2"
runstep "acknowledgments"    "cd apps/apple && python3 script/verify_acknowledgments.py"     "tail -2"
runstep "python unittests"   "cd apps/apple && python3 -m unittest discover -s script -p 'test_*.py'" "tail -3"
runstep "cloudkit-readiness" "cd apps/apple && python3 script/verify_cloudkit_sync_readiness.py" "tail -2"
runstep "iOS build"          "cd apps/apple && ./script/verify_mobile_simulator.sh"          "grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:|Error' | tail -6"

echo "### DONE (failures: $FAILURES)" >> "$LOG"
exit "$FAILURES"
