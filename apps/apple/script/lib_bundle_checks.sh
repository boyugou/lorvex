#!/usr/bin/env bash
# Sourced by archive_mas.sh, whose `set -euo pipefail` is the context these run in.
#
#   bundle_unreadable_files <bundle>    prints (at most 5) paths other users cannot read.
#   bundle_quarantined_files <bundle>   prints (at most 5) paths holding com.apple.quarantine.
#
# Both print nothing for a clean bundle and always return 0, so the caller decides by the
# output. Under pipefail a `grep` that matches nothing, or a `head` that closes the pipe
# early, would otherwise end the whole script with no message.

bundle_unreadable_files() {
  { find "$1" -not -perm -004 -print || true; } | head -5 || true
}

bundle_quarantined_files() {
  { xattr -rl "$1" 2>/dev/null || true; } | { grep 'com.apple.quarantine' || true; } | cut -d: -f1 | head -5 || true
}
