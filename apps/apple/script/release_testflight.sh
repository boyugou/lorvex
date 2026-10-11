#!/usr/bin/env bash
# Archives, validates, and uploads one TestFlight build on both store channels
# (iOS with its watch app, and the Mac App Store), then polls App Store Connect
# until both builds are processed.
#
# Usage:
#   script/release_testflight.sh upload [log-dir]
#   script/release_testflight.sh poll <ios-delivery-id> <mac-delivery-id> [log-dir]
#
# `upload` runs the two channels in parallel and stops each one at its first
# failing step; it prints the delivery id of every upload that succeeded, which
# is what `poll` takes. Bump the build number first (the eight files
# `script/verify_app_metadata.py` cross-checks) and commit it, so the uploaded
# build matches a commit on main.
#
# Credentials come from `secrets/apple-developer.env` at the repository root,
# which git ignores. It must define APPLE_ID, APPLE_PASSWORD (an app-specific
# password), APPLE_TEAM_ID, MAS_APP_SIGN_IDENTITY ("Apple Distribution: …"), and
# MAS_INSTALLER_SIGN_IDENTITY ("3rd Party Mac Developer Installer: …"). The Mac
# App Store provisioning profiles are read from `apps/apple/secrets/profiles/`.
# altool reads the password from the environment, so it never appears in `ps`,
# and every log line passes through a filter that masks passwords and email
# addresses.
#
# The schema-freeze tripwire gates archiving; never bypass it for a release.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="$ROOT_DIR/../../secrets/apple-developer.env"
MODE="${1:-}"

if [[ ! -f "$SECRETS" ]]; then
  echo "release_testflight: $SECRETS is missing" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1090
source "$SECRETS"
set +a
export APPLE_APP_PASSWORD="${APPLE_PASSWORD:?APPLE_PASSWORD is not set}"
: "${APPLE_ID:?APPLE_ID is not set}" "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"

MASK='s/[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}/[redacted]/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[email]/g'
cd "$ROOT_DIR" || exit 1

delivery_id() {
  grep -iA2 'delivery' "$1" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
}

ios_channel() {
  local log="$1/ios.log" ipa=dist/ios-archive/LorvexMobileApp-export/LorvexMobileApp.ipa
  : > "$log"
  ./script/archive_ios.sh --scheme LorvexMobileApp --export 2>&1 | sed -E "$MASK" >> "$log" \
    || { echo "IOS_ARCHIVE_FAILED" >> "$log"; return 1; }
  xcrun altool --validate-app --type ios -f "$ipa" -u "$APPLE_ID" -p "@env:APPLE_APP_PASSWORD" \
    --output-format json 2>&1 | sed -E "$MASK" >> "$log" || { echo "IOS_VALIDATE_FAILED" >> "$log"; return 1; }
  xcrun altool --upload-app --type ios -f "$ipa" -u "$APPLE_ID" -p "@env:APPLE_APP_PASSWORD" \
    --output-format json 2>&1 | sed -E "$MASK" > "$1/ios_upload.log" || { echo "IOS_UPLOAD_FAILED" >> "$log"; return 1; }
  echo "IOS_UPLOADED" >> "$log"
}

mac_channel() {
  local log="$1/mac.log"
  : "${MAS_APP_SIGN_IDENTITY:?MAS_APP_SIGN_IDENTITY is not set}"
  : "${MAS_INSTALLER_SIGN_IDENTITY:?MAS_INSTALLER_SIGN_IDENTITY is not set}"
  : > "$log"
  local step
  for step in package validate; do
    ./script/archive_mas.sh "--$step" 2>&1 | sed -E "$MASK" >> "$log" \
      || { echo "MAC_${step}_FAILED" >> "$log"; return 1; }
  done
  ./script/archive_mas.sh --upload 2>&1 | sed -E "$MASK" > "$1/mac_upload.log" \
    || { echo "MAC_UPLOAD_FAILED" >> "$log"; return 1; }
  echo "MAC_UPLOADED" >> "$log"
}

case "$MODE" in
  upload)
    LOG_DIR="${2:-$(mktemp -d)}"
    mkdir -p "$LOG_DIR"
    echo "release_testflight: logs in $LOG_DIR"
    ios_channel "$LOG_DIR" & ios_pid=$!
    mac_channel "$LOG_DIR" & mac_pid=$!
    wait "$ios_pid"; ios_rc=$?
    wait "$mac_pid"; mac_rc=$?
    [[ $ios_rc -eq 0 ]] && echo "ios delivery: $(delivery_id "$LOG_DIR/ios_upload.log")" || echo "ios channel failed; see $LOG_DIR/ios.log"
    [[ $mac_rc -eq 0 ]] && echo "mac delivery: $(delivery_id "$LOG_DIR/mac_upload.log")" || echo "mac channel failed; see $LOG_DIR/mac.log"
    [[ $ios_rc -eq 0 && $mac_rc -eq 0 ]]
    ;;
  poll)
    IOS_ID="${2:?ios delivery id}" MAC_ID="${3:?mac delivery id}"
    LOG="${4:-$(mktemp -d)}/poll.log"
    pending=("ios:$IOS_ID" "mac:$MAC_ID")
    # altool's first status call can take minutes or fail once; keep polling.
    for _ in $(seq 1 60); do
      still=()
      for pair in "${pending[@]}"; do
        out=$(xcrun altool --build-status --delivery-id "${pair#*:}" -u "$APPLE_ID" \
          -p "@env:APPLE_APP_PASSWORD" --output-format json 2>&1 | sed -E "$MASK")
        status=$(echo "$out" | grep -oE '"import-status" *: *"[A-Z_]+"' | head -1)
        echo "$(date +%H:%M:%S) ${pair%%:*} $status" | tee -a "$LOG"
        echo "$status" | grep -qE '"(VALID|BETA_INTERNAL_TESTING)"' || still+=("$pair")
      done
      [[ ${#still[@]} -eq 0 ]] && { echo "both builds processed"; exit 0; }
      pending=("${still[@]}")
      sleep 30
    done
    echo "release_testflight: builds still processing after 30 minutes" >&2
    exit 1
    ;;
  *)
    sed -n '2,9p' "$0" >&2
    exit 2
    ;;
esac
