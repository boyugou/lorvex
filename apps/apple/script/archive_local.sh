#!/usr/bin/env bash
# archive_local.sh — Package, archive, verify, and smoke-launch the macOS app.
#
# Usage:
#   LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1 ./script/archive_local.sh
#
# What it does:
#   1. Runs package_local.sh to build and assemble the .app bundle.
#   2. Creates a distributable zip archive under dist/.
#   3. Extracts the archive and verifies bundle structure, signatures, and
#      entitlements via verify_codesign_entitlements.py and
#      verify_macho_distribution.py.
#   4. Smoke-launches the extracted app and a copy in a temp directory.
#   5. Writes dist/lorvex-apple-release-manifest.json.
#
# No arguments are accepted except --help. All configuration (bundle name,
# version) comes from script/app_metadata.sh. A sandboxed helper is exercised
# against its production App Group; the environment opt-in acknowledges that
# verification stops Lorvex processes and irreversibly erases local Lorvex data.
#
# Requires:
#   - A successful swift build + package_local.sh run (or run this script
#     which calls package_local.sh automatically).
#   - codesign (ships with Xcode Command Line Tools).

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h|help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
source "$ROOT_DIR/script/lib_launch.sh"

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ARCHIVE_PATH="$ROOT_DIR/dist/$APP_NAME-$MARKETING_VERSION+$BUILD_VERSION.zip"
MCP_CLIENT_CONFIG="$ROOT_DIR/dist/lorvex-apple-mcp-client.json"
RELEASE_MANIFEST="$ROOT_DIR/dist/lorvex-apple-release-manifest.json"
VERIFY_DIR="$ROOT_DIR/dist/archive-verify"
EXTRACTED_APP="$VERIFY_DIR/$APP_NAME.app"
INSTALL_VERIFY_DIR=""

cd "$ROOT_DIR"

# The smoke launches below start Lorvex from the extracted / installed bundle.
# Track only the PID(s) THIS run launches and reap exactly those; a blanket kill
# by process name would also take down a developer's own running Lorvex.app that
# this run never spawned.
LAUNCHED_APP_PIDS=()

record_launched_app_pids() {
  local pids_before="$1" pid
  for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
    if ! grep -qx "$pid" <<<"$pids_before"; then
      LAUNCHED_APP_PIDS+=("$pid")
    fi
  done
}

cleanup() {
  local pid
  for pid in "${LAUNCHED_APP_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
  done
  if [[ -n "$INSTALL_VERIFY_DIR" ]]; then
    rm -rf "$INSTALL_VERIFY_DIR"
  fi
}
trap cleanup EXIT

verify_privacy_manifests() {
  local app_bundle="$1"
  for privacy_manifest in \
    "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy" \
    "$app_bundle/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/Resources/PrivacyInfo.xcprivacy"; do
    plutil -lint "$privacy_manifest" >/dev/null
    /usr/libexec/PlistBuddy -c "Print :NSPrivacyTracking" \
      "$privacy_manifest" | grep -qx "false"
    /usr/libexec/PlistBuddy -c "Print :NSPrivacyTrackingDomains" \
      "$privacy_manifest" | grep -qx "Array {"
    /usr/libexec/PlistBuddy -c "Print :NSPrivacyCollectedDataTypes" \
      "$privacy_manifest" | grep -qx "Array {"
    /usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType" \
      "$privacy_manifest" | grep -qx "NSPrivacyAccessedAPICategoryUserDefaults"
    /usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0" \
      "$privacy_manifest" | grep -qx "CA92.1"
  done
}

./script/package_local.sh

rm -f "$ARCHIVE_PATH"
rm -rf "$VERIFY_DIR"

(
  cd "$ROOT_DIR/dist"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ARCHIVE_PATH"
)

test -f "$ARCHIVE_PATH"
test -f "$MCP_CLIENT_CONFIG"
"$ROOT_DIR/script/generate_release_manifest.py" \
  --archive "$ARCHIVE_PATH" \
  --app-bundle "$APP_BUNDLE" \
  --mcp-config "$MCP_CLIENT_CONFIG" \
  --output "$RELEASE_MANIFEST"
"$ROOT_DIR/script/verify_release_manifest.py" "$RELEASE_MANIFEST"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ARCHIVE_PATH" "$VERIFY_DIR"

if unzip -Z1 "$ARCHIVE_PATH" | grep -Eq '(^|/)\._'; then
  echo "archive contains AppleDouble sidecar files" >&2
  exit 1
fi

test -d "$EXTRACTED_APP"
test -x "$EXTRACTED_APP/Contents/MacOS/$APP_NAME"
test -d "$EXTRACTED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app"
test -f "$EXTRACTED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/Info.plist"
test -x "$EXTRACTED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT"
test -d "$EXTRACTED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME"
test -x "$EXTRACTED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/MacOS/$WIDGET_EXECUTABLE"
verify_privacy_manifests "$EXTRACTED_APP"
"$ROOT_DIR/script/verify_macho_distribution.py" "$EXTRACTED_APP"
"$ROOT_DIR/script/verify_macho_closure.py" "$EXTRACTED_APP"
MCP_HOST_BINARY="$EXTRACTED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT" \
  "$ROOT_DIR/script/mcp_stdio_smoke.py" --reset-real-app-group
codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
codesign --verify --strict --verbose=2 "$EXTRACTED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME"
codesign_details="$(codesign -dvvv "$EXTRACTED_APP" 2>&1)"
grep -q "flags=.*runtime" <<<"$codesign_details"
"$ROOT_DIR/script/verify_codesign_entitlements.py" "$EXTRACTED_APP"

APP_PIDS_BEFORE_LAUNCH="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
/usr/bin/open -n "$EXTRACTED_APP"
wait_for_app_launch "$APP_NAME"
record_launched_app_pids "$APP_PIDS_BEFORE_LAUNCH"
cleanup

INSTALL_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorvex-install-verify.XXXXXX")"
INSTALLED_APP="$INSTALL_VERIFY_DIR/$APP_NAME.app"
ditto "$EXTRACTED_APP" "$INSTALLED_APP"

test -d "$INSTALLED_APP"
test -x "$INSTALLED_APP/Contents/MacOS/$APP_NAME"
test -d "$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app"
test -f "$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/Info.plist"
test -x "$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT"
test -d "$INSTALLED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME"
test -x "$INSTALLED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/MacOS/$WIDGET_EXECUTABLE"
verify_privacy_manifests "$INSTALLED_APP"
"$ROOT_DIR/script/verify_macho_distribution.py" "$INSTALLED_APP"
"$ROOT_DIR/script/verify_macho_closure.py" "$INSTALLED_APP"
MCP_HOST_BINARY="$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT" \
  "$ROOT_DIR/script/mcp_stdio_smoke.py" --reset-real-app-group
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
codesign --verify --strict --verbose=2 "$INSTALLED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME"
"$ROOT_DIR/script/verify_codesign_entitlements.py" "$INSTALLED_APP"

APP_PIDS_BEFORE_LAUNCH="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
/usr/bin/open -n "$INSTALLED_APP"
wait_for_app_launch "$APP_NAME"
record_launched_app_pids "$APP_PIDS_BEFORE_LAUNCH"
cleanup

echo "Local archive verification passed: $ARCHIVE_PATH"
