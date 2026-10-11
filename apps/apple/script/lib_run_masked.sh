#!/usr/bin/env bash
# Sourced by release_testflight.sh: run one release step with its output masked and
# logged, retrying once when it fails with a transient network error.
#
#   MASK                          a `sed -E` program that masks passwords and email
#                                 addresses; the caller sets it before calling.
#   run_masked <log-file> <cmd>   appends the masked output to <log-file> and returns
#                                 the command's status. A failure whose output names a
#                                 transient network error (a lost connection, NSURLError
#                                 -1005 or -1001, a 502, 503, or 504) runs the command one
#                                 more time, because the archive and upload steps reach
#                                 Apple's servers and take minutes to redo by hand. A
#                                 second failure, or any other failure, stands.

LORVEX_TRANSIENT_NETWORK='network connection was lost|NSURLError[A-Za-z]*[^0-9-]*-100[15]|HTTP[^0-9]*50[234]|request timed out'

run_masked() {
  local log="$1" attempt output status
  shift
  for attempt in 1 2; do
    output="$(mktemp)"
    "$@" 2>&1 | sed -E "$MASK" | tee -a "$log" >"$output"
    status="${PIPESTATUS[0]}"
    if (( status == 0 )); then
      rm -f "$output"
      return 0
    fi
    if (( attempt == 1 )) && grep -qiE "$LORVEX_TRANSIENT_NETWORK" "$output"; then
      echo "release: transient network failure, running the step once more" | tee -a "$log"
      rm -f "$output"
      continue
    fi
    rm -f "$output"
    return "$status"
  done
  return 1
}
