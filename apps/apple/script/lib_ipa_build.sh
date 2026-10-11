#!/usr/bin/env bash
# Sourced by release_testflight.sh.
#
#   ipa_build_number <ipa>   prints the iPhone app's CFBundleVersion, or nothing when the
#                            package is missing or holds no readable Info.plist.
#
# It reads the app's own Payload/<name>.app/Info.plist by exact path: a `*` in an unzip
# pattern also matches the embedded watch app's Info.plist, and the two would be read
# as one stream.

ipa_build_number() {
  local ipa="$1" entry
  entry="$(unzip -Z1 "$ipa" 2>/dev/null | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -1)"
  [[ -n "$entry" ]] || return 0
  unzip -p "$ipa" "$entry" 2>/dev/null | plutil -extract CFBundleVersion raw -o - - 2>/dev/null
}
