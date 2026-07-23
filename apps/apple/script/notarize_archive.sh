#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

MODE="${1:---preflight}"
ARCHIVE_PATH="${ARCHIVE_PATH:-"$ROOT_DIR/dist/$APP_NAME-$MARKETING_VERSION+$BUILD_VERSION.zip"}"
APP_BUNDLE="${APP_BUNDLE:-"$ROOT_DIR/dist/$APP_NAME.app"}"

# --preflight extracts the archive into this directory so every signing
# assertion applies to the exact app that notarytool would receive, not merely
# to the sibling bundle from which the archive was expected to be created.
PREFLIGHT_ARCHIVE_VERIFY_DIR=""
PREFLIGHT_EXTRACTED_APP=""

# --submit extracts the final archive into this directory to prove the ZIP
# users actually download (not just the standalone .app that stapler touches
# directly) carries the notarization ticket offline. Only ever non-empty
# between verify_final_archive's mktemp and its own cleanup; the EXIT trap is
# a backstop against a failure partway through that step.
FINAL_ARCHIVE_VERIFY_DIR=""

cleanup() {
  if [[ -n "$PREFLIGHT_ARCHIVE_VERIFY_DIR" ]]; then
    rm -rf "$PREFLIGHT_ARCHIVE_VERIFY_DIR"
  fi
  if [[ -n "$FINAL_ARCHIVE_VERIFY_DIR" ]]; then
    rm -rf "$FINAL_ARCHIVE_VERIFY_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<USAGE
usage: $0 [--preflight|--submit]

Environment for --preflight and --submit:
  APPLE_TEAM_ID            Expected Developer Team ID. Optional for --preflight;
                           when omitted, preflight derives the team from the
                           top-level signature and requires every nested item to
                           match it. Required for --submit.

Environment for --submit:
  NOTARY_KEYCHAIN_PROFILE  notarytool keychain profile holding the Apple ID and
                           app-specific password. Create it once with
                           'xcrun notarytool store-credentials' so no secret is
                           passed on the command line.

Optional artifact paths:
  APP_BUNDLE            App bundle expected to match the archived app
  ARCHIVE_PATH          Zip path to submit

--submit staples the notarization ticket to \$APP_BUNDLE, then REBUILDS
\$ARCHIVE_PATH from that exact stapled app (the ZIP submitted for notarization
predates the staple, so it must not be the one users download) and validates
the rebuilt ZIP by extracting it fresh and running 'stapler validate' plus
Gatekeeper assessment against the extracted copy.
USAGE
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required tool not found: $1" >&2
    exit 2
  fi
}

require_xcrun_tool() {
  if ! xcrun --find "$1" >/dev/null 2>&1; then
    echo "required Xcode tool not found: $1" >&2
    exit 2
  fi
}

verify_archive() {
  if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "archive not found: $ARCHIVE_PATH" >&2
    exit 2
  fi
  unzip -tq "$ARCHIVE_PATH" >/dev/null
  if unzip -Z1 "$ARCHIVE_PATH" | grep -Eq '(^|/)\._'; then
    echo "archive contains AppleDouble sidecar files: $ARCHIVE_PATH" >&2
    exit 1
  fi
}

verify_signed_app() {
  local app_bundle="$1"
  local codesign_details
  test -d "$app_bundle"
  codesign --verify --deep --strict --verbose=2 "$app_bundle" >/dev/null
  codesign_details="$(codesign -dvvv "$app_bundle" 2>&1)"
  if ! grep -q "flags=.*runtime" <<<"$codesign_details"; then
    echo "app is not signed with the hardened runtime: $app_bundle" >&2
    exit 1
  fi
  verify_nested_runtime_flags "$app_bundle"
}

verify_runtime_flag() {
  local item="$1"
  local details
  details="$(codesign -dvvv "$item" 2>&1)"
  if ! grep -q "flags=.*runtime" <<<"$details"; then
    echo "nested code is not hardened: $item" >&2
    exit 1
  fi
}

verify_nested_runtime_flags() {
  local app_bundle="$1"
  local item
  if [[ -d "$app_bundle/Contents/MacOS" ]]; then
    while IFS= read -r -d '' item; do
      verify_runtime_flag "$item"
    done < <(find "$app_bundle/Contents/MacOS" -type f -perm -111 -print0)
  fi
  if [[ -d "$app_bundle/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' item; do
      verify_runtime_flag "$item"
    done < <(find "$app_bundle/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm -111 \) -print0)
  fi
  if [[ -d "$app_bundle/Contents/Helpers" ]]; then
    while IFS= read -r -d '' item; do
      verify_runtime_flag "$item"
    done < <(find "$app_bundle/Contents/Helpers" -maxdepth 1 -type d -name "*.app" -print0)
    while IFS= read -r -d '' item; do
      verify_runtime_flag "$item"
    done < <(find "$app_bundle/Contents/Helpers" -type f -perm -111 -print0)
  fi
  if [[ -d "$app_bundle/Contents/PlugIns" ]]; then
    while IFS= read -r -d '' item; do
      verify_runtime_flag "$item"
      while IFS= read -r -d '' nested; do
        verify_runtime_flag "$nested"
      done < <(find "$item/Contents/MacOS" -type f -perm -111 -print0 2>/dev/null || true)
    done < <(find "$app_bundle/Contents/PlugIns" -maxdepth 1 -type d -name "*.appex" -print0)
  fi
}

signed_team_identifier() {
  local item="$1"
  local codesign_details team_identifier
  codesign_details="$(codesign -dvvv "$item" 2>&1)"
  team_identifier="$(sed -n 's/^TeamIdentifier=//p' <<<"$codesign_details" | head -n 1)"
  if [[ -z "$team_identifier" ]]; then
    echo "Developer ID signature has no TeamIdentifier: $item" >&2
    exit 1
  fi
  printf '%s\n' "$team_identifier"
}

verify_developer_id_signature() {
  local item="$1"
  local expected_team_id="$2"
  local codesign_details timestamp_line
  codesign_details="$(codesign -dvvv "$item" 2>&1)"
  if grep -Fq "Signature=adhoc" <<<"$codesign_details"; then
    echo "notarization requires a Developer ID signature, but code is ad-hoc signed: $item" >&2
    exit 1
  fi
  if ! grep -Fq "Authority=Developer ID Application:" <<<"$codesign_details"; then
    echo "notarization requires a Developer ID Application signature: $item" >&2
    exit 1
  fi
  if ! grep -Fxq "TeamIdentifier=$expected_team_id" <<<"$codesign_details"; then
    echo "signature TeamIdentifier does not match expected team $expected_team_id: $item" >&2
    exit 1
  fi
  timestamp_line="$(grep -E '^Timestamp=' <<<"$codesign_details" | head -n 1 || true)"
  if [[ -z "$timestamp_line" || "$timestamp_line" == "Timestamp=none" ]]; then
    echo "notarization requires a secure timestamp; rebuild without SIGN_TIMESTAMP=none: $item" >&2
    exit 1
  fi
}

verify_developer_id_signatures() {
  local app_bundle="$1"
  local expected_team_id="$2"
  local item
  verify_developer_id_signature "$app_bundle" "$expected_team_id"
  if [[ -d "$app_bundle/Contents/MacOS" ]]; then
    while IFS= read -r -d '' item; do
      verify_developer_id_signature "$item" "$expected_team_id"
    done < <(find "$app_bundle/Contents/MacOS" -type f -perm -111 -print0)
  fi
  if [[ -d "$app_bundle/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' item; do
      verify_developer_id_signature "$item" "$expected_team_id"
    done < <(find "$app_bundle/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm -111 \) -print0)
  fi
  if [[ -d "$app_bundle/Contents/Helpers" ]]; then
    while IFS= read -r -d '' item; do
      verify_developer_id_signature "$item" "$expected_team_id"
    done < <(find "$app_bundle/Contents/Helpers" -maxdepth 1 -type d -name "*.app" -print0)
    while IFS= read -r -d '' item; do
      verify_developer_id_signature "$item" "$expected_team_id"
    done < <(find "$app_bundle/Contents/Helpers" -type f -perm -111 -print0)
  fi
  if [[ -d "$app_bundle/Contents/PlugIns" ]]; then
    while IFS= read -r -d '' item; do
      verify_developer_id_signature "$item" "$expected_team_id"
      while IFS= read -r -d '' nested; do
        verify_developer_id_signature "$nested" "$expected_team_id"
      done < <(find "$item/Contents/MacOS" -type f -perm -111 -print0 2>/dev/null || true)
    done < <(find "$app_bundle/Contents/PlugIns" -maxdepth 1 -type d -name "*.appex" -print0)
  fi
}

extract_preflight_archive() {
  PREFLIGHT_ARCHIVE_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorvex-notarize-preflight.XXXXXX")"
  PREFLIGHT_EXTRACTED_APP="$PREFLIGHT_ARCHIVE_VERIFY_DIR/$(basename "$APP_BUNDLE")"
  ditto -x -k "$ARCHIVE_PATH" "$PREFLIGHT_ARCHIVE_VERIFY_DIR"
  if [[ ! -d "$PREFLIGHT_EXTRACTED_APP" ]]; then
    echo "archive does not contain the expected top-level app: $(basename "$APP_BUNDLE")" >&2
    exit 1
  fi
  if ! diff -qr "$APP_BUNDLE" "$PREFLIGHT_EXTRACTED_APP" >/dev/null; then
    echo "archived app does not match APP_BUNDLE; rebuild the archive before notarization" >&2
    exit 1
  fi
}

preflight() {
  require_tool unzip
  require_tool codesign
  require_tool diff
  require_tool ditto
  require_xcrun_tool notarytool
  require_xcrun_tool stapler
  verify_archive
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "app bundle not found: $APP_BUNDLE" >&2
    exit 2
  fi
  extract_preflight_archive
  verify_signed_app "$PREFLIGHT_EXTRACTED_APP"
  local signed_team_id expected_team_id
  signed_team_id="$(signed_team_identifier "$PREFLIGHT_EXTRACTED_APP")"
  expected_team_id="${APPLE_TEAM_ID:-$signed_team_id}"
  verify_developer_id_signatures "$PREFLIGHT_EXTRACTED_APP" "$expected_team_id"
  echo "Notarization preflight passed for Developer ID team $expected_team_id: $ARCHIVE_PATH"
}

# Rebuilds $ARCHIVE_PATH from the just-stapled $APP_BUNDLE. The ZIP submitted
# to notarytool above was created before stapling (by archive_local.sh) and
# `xcrun stapler staple "$APP_BUNDLE"` only staples the standalone .app, not
# that ZIP — without this step the distributed archive would still contain
# the pre-staple app and fail Gatekeeper offline on a machine with no network
# access to look up the notarization ticket. Mirrors archive_local.sh's own
# ditto invocation so the rebuilt archive has the identical layout.
rebuild_archive_from_stapled_app() {
  local app_dir app_name
  app_dir="$(cd "$(dirname "$APP_BUNDLE")" && pwd)"
  app_name="$(basename "$APP_BUNDLE")"
  rm -f "$ARCHIVE_PATH"
  (
    cd "$app_dir"
    COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$app_name" "$ARCHIVE_PATH"
  )
  echo "Rebuilt distribution archive from the stapled app: $ARCHIVE_PATH"
}

# Extracts the just-rebuilt $ARCHIVE_PATH into a clean directory and validates
# THAT copy — the artifact a user's `unzip`/Archive Utility would produce —
# rather than trusting the in-place $APP_BUNDLE the staple command touched
# directly. A pre-staple ZIP is exactly the failure mode this closes: it would
# still pass every earlier check in this script (the standalone .app really is
# stapled) while shipping stale bytes to users.
verify_final_archive() {
  FINAL_ARCHIVE_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorvex-notarize-verify.XXXXXX")"
  local extracted_app="$FINAL_ARCHIVE_VERIFY_DIR/$(basename "$APP_BUNDLE")"
  ditto -x -k "$ARCHIVE_PATH" "$FINAL_ARCHIVE_VERIFY_DIR"
  test -d "$extracted_app"
  xcrun stapler validate "$extracted_app"
  codesign --verify --deep --strict --verbose=2 "$extracted_app"
  spctl -a -vv "$extracted_app"
  rm -rf "$FINAL_ARCHIVE_VERIFY_DIR"
  FINAL_ARCHIVE_VERIFY_DIR=""
  echo "Final distribution archive extracted and validated as stapled: $ARCHIVE_PATH"
}

submit() {
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for --submit}"
  : "${NOTARY_KEYCHAIN_PROFILE:?NOTARY_KEYCHAIN_PROFILE is required for --submit}"

  preflight
  # Authenticate with a stored keychain profile so the app-specific password is
  # never passed as a CLI argument (which would leak it into the process table).
  # Create the profile once, outside CI logs, with:
  #   xcrun notarytool store-credentials "$NOTARY_KEYCHAIN_PROFILE" \
  #     --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vv "$APP_BUNDLE"
  rebuild_archive_from_stapled_app
  verify_final_archive
  echo "Notarization and stapling passed: $APP_BUNDLE"
  echo "Distribution archive rebuilt from the stapled app and validated: $ARCHIVE_PATH"
}

case "$MODE" in
  --preflight|preflight)
    preflight
    ;;
  --submit|submit)
    submit
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
