#!/usr/bin/env bash
# Shared helper: wait for a launched app process to appear, with a bounded
# polling loop. Sourced by build_and_run.sh and archive_local.sh.

# wait_for_app_launch <process-name>
# Returns 0 once `pgrep -x <process-name>` matches; returns 1 with a message on
# stderr if the process does not appear within ~10 seconds.
wait_for_app_launch() {
  local app_name="$1"
  local i
  for i in $(seq 1 20); do
    if pgrep -x "$app_name" >/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  if ! pgrep -x "$app_name" >/dev/null; then
    echo "App did not launch within timeout: $app_name" >&2
    return 1
  fi
}
