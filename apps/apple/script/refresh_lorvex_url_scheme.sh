#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
TARGET_APP="$ROOT_DIR/dist/$APP_NAME.app"
APPLY=0

usage() {
  cat <<EOF
usage: $0 [--apply] [--target /path/to/Lorvex.app]

Refresh LaunchServices so lorvex:// deep links resolve to the intended local app.
By default this is a dry run. Pass --apply to unregister known stale local bundles
and register the target bundle.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --target)
      TARGET_APP="${2:?--target requires a bundle path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$LSREGISTER" ]]; then
  echo "lsregister not found at $LSREGISTER" >&2
  exit 1
fi

canonical_path() {
  /usr/bin/python3 - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

registered_lorvex_bundles() {
  "$LSREGISTER" -dump | /usr/bin/python3 -c '
import re
import sys

scheme = sys.argv[1]
dump = sys.stdin.read()
blocks = re.split(r"(?m)^-{20,}\s*$", dump)
for block in blocks:
    if f"claimed schemes:            {scheme}:" not in block:
        continue
    match = re.search(r"^path:\s+(.+?)\s+\(0x[0-9a-fA-F]+\)\s*$", block, re.MULTILINE)
    if match:
        print(match.group(1))
' "$URL_SCHEME"
}

register_bundle() {
  local bundle="$1"
  if [[ "$APPLY" -eq 1 ]]; then
    "$LSREGISTER" -f "$bundle"
  else
    printf 'dry-run: %q -f %q\n' "$LSREGISTER" "$bundle"
  fi
}

unregister_bundle() {
  local bundle="$1"
  if [[ "$APPLY" -eq 1 ]]; then
    if ! "$LSREGISTER" -u "$bundle"; then
      echo "WARNING: couldn't unregister stale LaunchServices path: $bundle" >&2
    fi
  else
    printf 'dry-run: %q -u %q\n' "$LSREGISTER" "$bundle"
  fi
}

if [[ ! -d "$TARGET_APP" ]]; then
  echo "target app bundle does not exist: $TARGET_APP" >&2
  echo "run ./script/build_and_run.sh --stage-only first, or pass --target." >&2
  exit 1
fi

target_real="$(canonical_path "$TARGET_APP")"
declare -a candidates=(
  "/Applications/$APP_DISPLAY_NAME.app"
  "/Applications/$APP_NAME.app"
  "$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
  "$ROOT_DIR/dist/$APP_NAME.app"
)

while IFS= read -r registered_bundle; do
  [[ -n "$registered_bundle" ]] && candidates+=("$registered_bundle")
done < <(registered_lorvex_bundles)

for backup in /Applications/"$APP_DISPLAY_NAME".app.bak.* /Applications/"$APP_NAME".app.bak.*; do
  [[ -e "$backup" ]] && candidates+=("$backup")
done

echo "Refreshing $URL_SCHEME:// LaunchServices registration"
echo "Target: $TARGET_APP"

for bundle in "${candidates[@]}"; do
  [[ "$(canonical_path "$bundle")" == "$target_real" ]] && continue
  unregister_bundle "$bundle"
done

register_bundle "$TARGET_APP"

if [[ "$APPLY" -eq 1 ]]; then
  echo "LaunchServices registration refreshed. Smoke-test with: open '$URL_SCHEME://open/today'"
else
  echo "Dry run only. Re-run with --apply to update LaunchServices."
fi
