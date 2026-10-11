#!/usr/bin/env bash
# Archives, validates, and uploads one TestFlight build on both store channels
# (iOS with its watch app, and the Mac App Store), then polls App Store Connect
# until both builds are processed.
#
# Usage:
#   script/release_testflight.sh validate [log-dir]
#   script/release_testflight.sh upload [log-dir]
#   script/release_testflight.sh deliver [log-dir]
#   script/release_testflight.sh poll <ios-delivery-id> <mac-delivery-id> [log-dir]
#
# `validate` runs everything `upload` does except the two uploads: both archives,
# their signing, and App Store Connect's own validation of each package. Run it
# whenever the machine, the toolchain, or the signing changed.
#
# `deliver` uploads the packages that `validate` (or an earlier `upload`) left in
# dist/, without archiving again, so exactly the validated bits reach TestFlight;
# it refuses an iOS package whose build number is not the current one.
#
# RELEASE_CHANNELS=ios (or mac) runs one channel only, so a channel that failed
# can be redone without repeating the one that succeeded.
#
# `upload` runs the two channels in parallel and stops each one at its first
# failing step; it prints the delivery id of every upload that succeeded, which
# is what `poll` takes. A step that fails with a transient network error (a lost
# connection, a 502, 503, or 504) runs once more before its channel gives up.
# Bump the build number first (`script/bump_build.py`) and commit it, so the
# uploaded build matches a commit on main.
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
# shellcheck source=script/lib_run_masked.sh
source "$ROOT_DIR/script/lib_run_masked.sh"
# shellcheck source=script/lib_ipa_build.sh
source "$ROOT_DIR/script/lib_ipa_build.sh"
source "$ROOT_DIR/script/app_metadata.sh"

delivery_id() {
  grep -iA2 'delivery' "$1" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1
}

# ios_channel <log-dir> <validate|upload>
ios_channel() {
  local log="$1/ios.log" mode="$2" ipa=dist/ios-archive/LorvexMobileApp-export/LorvexMobileApp.ipa
  : > "$log"
  if [[ "$mode" == "deliver" ]]; then
    local ipa_build
    ipa_build="$(ipa_build_number "$ipa")"
    if [[ "$ipa_build" != "$BUILD_VERSION" ]]; then
      echo "the iOS package at $ipa is build '${ipa_build:-missing}', not $BUILD_VERSION; run validate first" >> "$log"
      echo "IOS_DELIVER_FAILED" >> "$log"
      return 1
    fi
  else
    run_masked "$log" ./script/archive_ios.sh --scheme LorvexMobileApp --export \
      || { echo "IOS_ARCHIVE_FAILED" >> "$log"; return 1; }
    run_masked "$log" xcrun altool --validate-app --type ios -f "$ipa" -u "$APPLE_ID" -p "@env:APPLE_APP_PASSWORD" \
      --output-format json || { echo "IOS_VALIDATE_FAILED" >> "$log"; return 1; }
    if [[ "$mode" == "validate" ]]; then
      echo "IOS_VALIDATED" >> "$log"
      return 0
    fi
  fi
  : > "$1/ios_upload.log"
  run_masked "$1/ios_upload.log" xcrun altool --upload-app --type ios -f "$ipa" -u "$APPLE_ID" -p "@env:APPLE_APP_PASSWORD" \
    --output-format json || { echo "IOS_UPLOAD_FAILED" >> "$log"; return 1; }
  echo "IOS_UPLOADED" >> "$log"
}

# mac_channel <log-dir> <validate|upload>
mac_channel() {
  local log="$1/mac.log" mode="$2" step
  : "${MAS_APP_SIGN_IDENTITY:?MAS_APP_SIGN_IDENTITY is not set}"
  : "${MAS_INSTALLER_SIGN_IDENTITY:?MAS_INSTALLER_SIGN_IDENTITY is not set}"
  : > "$log"
  if [[ "$mode" != "deliver" ]]; then
    for step in package validate; do
      run_masked "$log" ./script/archive_mas.sh "--$step" \
        || { echo "MAC_${step}_FAILED" >> "$log"; return 1; }
    done
    if [[ "$mode" == "validate" ]]; then
      echo "MAC_VALIDATED" >> "$log"
      return 0
    fi
  fi
  : > "$1/mac_upload.log"
  run_masked "$1/mac_upload.log" ./script/archive_mas.sh --upload \
    || { echo "MAC_UPLOAD_FAILED" >> "$log"; return 1; }
  echo "MAC_UPLOADED" >> "$log"
}

case "$MODE" in
  upload|validate|deliver)
    LOG_DIR="${2:-$(mktemp -d)}"
    mkdir -p "$LOG_DIR"
    # RELEASE_CHANNELS="ios" or "mac" runs one channel only, so a channel that
    # failed can be redone without repeating the one that succeeded.
    CHANNELS=" ${RELEASE_CHANNELS:-ios mac} "
    echo "release_testflight: $MODE, logs in $LOG_DIR"
    ios_pid="" mac_pid="" ios_rc=0 mac_rc=0
    if [[ "$CHANNELS" == *" ios "* ]]; then ios_channel "$LOG_DIR" "$MODE" & ios_pid=$!; fi
    if [[ "$CHANNELS" == *" mac "* ]]; then mac_channel "$LOG_DIR" "$MODE" & mac_pid=$!; fi
    if [[ -n "$ios_pid" ]]; then wait "$ios_pid"; ios_rc=$?; fi
    if [[ -n "$mac_pid" ]]; then wait "$mac_pid"; mac_rc=$?; fi
    for channel in ios mac; do
      [[ "$CHANNELS" == *" $channel "* ]] || continue
      rc_name="${channel}_rc"
      if [[ "${!rc_name}" -ne 0 ]]; then
        echo "$channel channel failed; see $LOG_DIR/$channel.log"
      elif [[ "$MODE" == "validate" ]]; then
        echo "$channel channel validated"
      else
        echo "$channel delivery: $(delivery_id "$LOG_DIR/${channel}_upload.log")"
      fi
    done
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
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
esac
