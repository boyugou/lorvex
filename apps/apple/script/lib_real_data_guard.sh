#!/usr/bin/env bash
# Refuses to go on when this Mac holds real Lorvex data: an installed Lorvex.app (a store, TestFlight, or
# direct-download release) or the production App Group container its data lives in. The scripts that call
# this build the app, launch it against the managed store, or package and verify it, and none of that may
# touch a person's planner. `verify_swift.sh` and `verify_static_gates.sh` never read the real store and
# do not call this.
#
#   source script/lib_real_data_guard.sh
#   refuse_on_machine_with_lorvex_data verify_all.sh || exit 78
#
# LORVEX_ALLOW_RUN_WITH_REAL_DATA=1 passes the check, for a machine known to hold nothing worth keeping.
# LORVEX_REAL_DATA_PROBE_PATHS (colon-separated) replaces the paths that are probed, for the unit test.

lorvex_real_data_probe_paths() {
  if [[ -n "${LORVEX_REAL_DATA_PROBE_PATHS:-}" ]]; then
    printf '%s\n' "$LORVEX_REAL_DATA_PROBE_PATHS" | tr ':' '\n'
    return 0
  fi
  printf '%s\n' \
    "/Applications/Lorvex.app" \
    "$HOME/Applications/Lorvex.app" \
    "$HOME/Library/Group Containers/${APP_GROUP_ID:-group.com.lorvex.apple}"
}

refuse_on_machine_with_lorvex_data() {
  local caller="${1:-this script}" path found=""
  if [[ "${LORVEX_ALLOW_RUN_WITH_REAL_DATA:-0}" == "1" ]]; then
    return 0
  fi
  while IFS= read -r path; do
    if [[ -n "$path" && -e "$path" ]]; then
      found="${found}  ${path}"$'\n'
    fi
  done < <(lorvex_real_data_probe_paths)
  if [[ -z "$found" ]]; then
    return 0
  fi
  {
    echo "$caller: this Mac holds real Lorvex data, and this script builds, launches, or packages the app"
    echo "against it. Found:"
    printf '%s' "$found"
    echo "Run script/verify_swift.sh and script/verify_static_gates.sh here instead; they never read the"
    echo "real store. To run this script anyway on a Mac that holds nothing worth keeping, set"
    echo "LORVEX_ALLOW_RUN_WITH_REAL_DATA=1."
  } >&2
  return 78
}
