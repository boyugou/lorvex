#!/usr/bin/env bash
# package_dmg.sh — Build the final notarized Developer ID DMG.
#
# This is intentionally not a local-development packager. With no arguments it
# fails closed unless every production input is present: an armed schema freeze,
# a Developer ID Application identity, the expected team, three Developer ID
# provisioning profiles, a notarytool keychain profile, and explicit consent to
# erase the real Lorvex App Group while exercising the sandboxed MCP helper.
# package_local.sh remains the ad-hoc/dev/CI path. archive_mas.sh remains the
# separate Mac App Store submission path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
source "$ROOT_DIR/script/require_schema_freeze_gate.sh"

DIST="$ROOT_DIR/dist"
STAGED_APP="$DIST/$APP_NAME.app"
DMG_NAME="$APP_NAME"
DMG_STAGE=""
DMG_APP=""
ARTIFACT_STEM="$DMG_NAME-macOS-$MARKETING_VERSION+$BUILD_VERSION-arm64"
DMG_OUT="$DIST/$ARTIFACT_STEM.dmg"
EVIDENCE_DIR="$DIST/release-evidence/$ARTIFACT_STEM"
WORK_DIR=""
MOUNT_POINT=""
INSTALL_APP_PATH="${LORVEX_PRODUCTION_INSTALL_PATH:-/Applications/$APP_NAME.app}"
INSTALLED_APP=""
INSTALLED_BY_THIS_RUN=0
PACKAGE_STARTED=0
PACKAGE_SUCCEEDED=0

usage() {
  cat <<USAGE
usage: ./script/package_dmg.sh

Required environment:
  APPLE_TEAM_ID
  CODE_SIGN_IDENTITY                         Developer ID Application identity or SHA-1
  NOTARY_KEYCHAIN_PROFILE                    notarytool stored-credential profile
  DEVELOPER_ID_APP_PROVISIONING_PROFILE      com.lorvex.apple profile
  DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE com.lorvex.apple.mcp-host profile
  DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE   com.lorvex.apple.focuswidget profile
  LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1

Optional environment:
  LORVEX_PRODUCTION_INSTALL_PATH             absolute path; defaults to /Applications/$APP_NAME.app

The final artifact is a Release, arm64-only, production-CloudKit Developer ID
DMG. Verification permanently erases this Mac's existing Lorvex local state:
the App Group store, app/shared preferences, private CloudSync state, and the
derived Spotlight corpus cleared by the exact installed app's empty-state
refresh. It never moves, backs up, or restores prior data. It also replaces the
app at the production install path without preserving the previous bundle.
USAGE
}

cleanup() {
  local status=$?
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
  if [[ "$PACKAGE_STARTED" == "1" && "$PACKAGE_SUCCEEDED" != "1" ]]; then
    rm -f "$DMG_OUT" "$DMG_OUT.sha256"
    if [[ "$INSTALLED_BY_THIS_RUN" == "1" ]]; then
      rm -rf "$INSTALLED_APP"
    fi
  fi
  return "$status"
}
trap cleanup EXIT

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required production environment variable: $name" >&2
    exit 2
  fi
}

require_file_env() {
  local name="$1"
  require_env "$name"
  if [[ ! -f "${!name}" ]]; then
    echo "$name does not name a file: ${!name}" >&2
    exit 2
  fi
}

canonicalize_file_env() {
  local name="$1" path="${!1}" absolute
  absolute="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  printf -v "$name" '%s' "$absolute"
  export "$name"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required production packaging tool not found: $1" >&2
    exit 2
  fi
}

verify_identity_available() {
  local requested="$1" identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null)"
  if ! awk -v requested="$requested" '
    /"Developer ID Application:/ {
      hash = $2
      line = $0
      first_quote = index(line, "\"")
      name = substr(line, first_quote + 1)
      sub(/"[[:space:]]*$/, "", name)
      if (toupper(requested) == toupper(hash) || requested == name) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' <<<"$identities"; then
    echo "CODE_SIGN_IDENTITY is not an available Developer ID Application identity: $requested" >&2
    exit 2
  fi
}

require_clean_worktree() {
  if [[ -n "$(git -C "$ROOT_DIR/../.." status --porcelain --untracked-files=all)" ]]; then
    echo "production DMG packaging requires a clean Git worktree" >&2
    exit 2
  fi
}

validate_install_path() {
  if [[ "$INSTALL_APP_PATH" != /* ]]; then
    echo "LORVEX_PRODUCTION_INSTALL_PATH must be absolute: $INSTALL_APP_PATH" >&2
    exit 2
  fi
  if [[ "$(basename "$INSTALL_APP_PATH")" != "$APP_NAME.app" ]]; then
    echo "production install path must end in $APP_NAME.app: $INSTALL_APP_PATH" >&2
    exit 2
  fi
  local parent
  parent="$(dirname "$INSTALL_APP_PATH")"
  if [[ ! -d "$parent" || ! -w "$parent" ]]; then
    echo "production install directory must already exist and be writable: $parent" >&2
    echo "do not run the whole release pipeline with sudo; choose a writable absolute LORVEX_PRODUCTION_INSTALL_PATH instead" >&2
    exit 2
  fi
  parent="$(cd "$parent" && pwd -P)"
  INSTALL_APP_PATH="$parent/$APP_NAME.app"
}

reject_ambiguous_dmg_artifacts() {
  local candidate
  local -a stale=()
  mkdir -p "$DIST"
  while IFS= read -r -d '' candidate; do
    if [[ "$candidate" != "$DMG_OUT" ]]; then
      stale+=("$candidate")
    fi
  # Reject every filesystem entry with a release-looking DMG name, including a
  # dangling symlink. Restricting this to regular files would let an ambiguous
  # old/unsigned artifact alias survive beside the candidate.
  done < <(find "$DIST" -maxdepth 1 -name "$DMG_NAME-macOS-*.dmg" -print0)
  if [[ "${#stale[@]}" -gt 0 ]]; then
    echo "refusing ambiguous production output; remove or archive these stale Lorvex DMGs first:" >&2
    printf '  %s\n' "${stale[@]}" >&2
    exit 2
  fi
}

reject_existing_release_outputs() {
  local candidate
  local -a existing=()
  for candidate in "$DMG_OUT" "$DMG_OUT.sha256" "$EVIDENCE_DIR"; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      existing+=("$candidate")
    fi
  done
  if [[ "${#existing[@]}" -gt 0 ]]; then
    echo "refusing to overwrite immutable production output for $ARTIFACT_STEM:" >&2
    printf '  %s\n' "${existing[@]}" >&2
    echo "advance BUILD_VERSION before producing another production DMG" >&2
    exit 2
  fi
}

verify_final_app() {
  local app_bundle="$1"
  codesign --verify --deep --strict --verbose=2 "$app_bundle"
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    "$ROOT_DIR/script/verify_codesign_entitlements.py" \
      --require-cloudkit \
      --require-production-aps \
      "$app_bundle"
  python3 "$ROOT_DIR/script/verify_developer_id_provisioning.py" \
    --expected-team-id "$APPLE_TEAM_ID" \
    "$app_bundle"
  "$ROOT_DIR/script/verify_macho_distribution.py" "$app_bundle"
  "$ROOT_DIR/script/verify_macho_closure.py" "$app_bundle"
  "$ROOT_DIR/script/verify_swiftpm_resource_bundles.py" "$app_bundle"
}

verify_final_dmg_signature() {
  local dmg="$1" details
  codesign --verify --strict --verbose=2 "$dmg"
  details="$(codesign -dvvv "$dmg" 2>&1)"
  if ! grep -Fq 'Authority=Developer ID Application:' <<<"$details"; then
    echo "final DMG is not signed by Developer ID Application" >&2
    exit 1
  fi
  if ! grep -Fxq "TeamIdentifier=$APPLE_TEAM_ID" <<<"$details"; then
    echo "final DMG signature does not carry TeamIdentifier=$APPLE_TEAM_ID" >&2
    exit 1
  fi
  if ! grep -Eq '^Timestamp=.+$' <<<"$details" \
      || grep -Eiq '^Timestamp=(none)?$' <<<"$details"; then
    echo "final DMG signature has no secure timestamp" >&2
    exit 1
  fi
}

capture_bundle_evidence() {
  local label="$1" bundle="$2"
  codesign -dvvv "$bundle" >"$EVIDENCE_DIR/$label-codesign.txt" 2>&1
  codesign -d --entitlements - --xml "$bundle" \
    >"$EVIDENCE_DIR/$label-signed-entitlements.plist" 2>/dev/null
  security cms -D -i "$bundle/Contents/embedded.provisionprofile" \
    >"$EVIDENCE_DIR/$label-provisioning-profile.plist"
  plutil -lint "$EVIDENCE_DIR/$label-signed-entitlements.plist" >/dev/null
  plutil -lint "$EVIDENCE_DIR/$label-provisioning-profile.plist" >/dev/null
}

if [[ $# -ne 0 ]]; then
  if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" || "$1" == "help" ) ]]; then
    usage
    exit 0
  fi
  usage >&2
  exit 2
fi

for name in APPLE_TEAM_ID CODE_SIGN_IDENTITY NOTARY_KEYCHAIN_PROFILE; do
  require_env "$name"
done
for name in \
  DEVELOPER_ID_APP_PROVISIONING_PROFILE \
  DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE \
  DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE
do
  require_file_env "$name"
  canonicalize_file_env "$name"
done

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_TEAM_ID must be a ten-character Apple Developer Team ID" >&2
  exit 2
fi
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  echo "production DMG packaging forbids ad-hoc signing" >&2
  exit 2
fi
if [[ "${LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET:-0}" != "1" ]]; then
  echo "production DMG verification irreversibly erases all local Lorvex state" >&2
  echo "set LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1 to acknowledge it" >&2
  exit 2
fi
if [[ -n "${LORVEX_ALLOW_UNFROZEN:-}" && "${LORVEX_ALLOW_UNFROZEN}" != "0" ]]; then
  echo "production DMG packaging never permits LORVEX_ALLOW_UNFROZEN" >&2
  exit 2
fi
if [[ "${LORVEX_BUILD_CONFIGURATION:-release}" != "release" ]]; then
  echo "production DMG packaging requires LORVEX_BUILD_CONFIGURATION=release" >&2
  exit 2
fi
export LORVEX_BUILD_CONFIGURATION=release
unset LORVEX_ALLOW_UNFROZEN

for tool in awk codesign diff ditto file find git grep hdiutil launchctl lipo openssl pgrep plutil python3 security spctl xcrun; do
  require_tool "$tool"
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
verify_identity_available "$CODE_SIGN_IDENTITY"
require_clean_worktree
validate_install_path
reject_ambiguous_dmg_artifacts
reject_existing_release_outputs

PACKAGE_STARTED=1
mkdir -p "$(dirname "$EVIDENCE_DIR")"
mkdir "$EVIDENCE_DIR"
require_schema_freeze_armed "$ROOT_DIR" 2>&1 | tee "$EVIDENCE_DIR/schema-freeze.txt"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorvex-production-dmg.XXXXXX")"
ENTITLEMENTS_DIR="$WORK_DIR/entitlements"
DMG_STAGE="$WORK_DIR/dmg-stage"
DMG_APP="$DMG_STAGE/$DMG_NAME.app"
mkdir -p "$ENTITLEMENTS_DIR"

python3 "$ROOT_DIR/script/prepare_profile_entitlements.py" \
  --base "$ROOT_DIR/Config/LorvexAppleCloudKitAppStore.entitlements" \
  --profile "$DEVELOPER_ID_APP_PROVISIONING_PROFILE" \
  --bundle-id "$BUNDLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --output "$ENTITLEMENTS_DIR/app.plist"
python3 "$ROOT_DIR/script/prepare_profile_entitlements.py" \
  --base "$ROOT_DIR/Config/LorvexMCPHost.entitlements" \
  --profile "$DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE" \
  --bundle-id "$MCP_HOST_BUNDLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --output "$ENTITLEMENTS_DIR/helper.plist"
python3 "$ROOT_DIR/script/prepare_profile_entitlements.py" \
  --base "$ROOT_DIR/Config/LorvexWidgetExtension.entitlements" \
  --profile "$DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE" \
  --bundle-id "$WIDGET_BUNDLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --output "$ENTITLEMENTS_DIR/widget.plist"

echo "==> Building Release bundle"
cd "$ROOT_DIR"
# build_and_run.sh always gives its staged development bundle an initial local
# signature.  Keep that bootstrap ad-hoc so the production identity is used
# exactly once, below, with the final entitlements/profiles and secure timestamp.
CODE_SIGN_IDENTITY=- ./script/build_and_run.sh --stage-only
# SwiftPM/Xcode package resolution must not rewrite a committed lock while
# producing the candidate; otherwise the evidence commit would not describe
# the source tree that actually built it.
require_clean_worktree

echo "==> Verifying every Mach-O is arm64-only"
: >"$EVIDENCE_DIR/architectures.txt"
MACHO_COUNT=0
while IFS= read -r -d '' bin; do
  if ! file -b "$bin" | grep -q 'Mach-O'; then
    continue
  fi
  MACHO_COUNT=$((MACHO_COUNT + 1))
  archs="$(lipo -archs "$bin")"
  printf '%s: %s\n' "${bin#"$STAGED_APP/"}" "$archs" | tee -a "$EVIDENCE_DIR/architectures.txt"
  if [[ "$archs" != "arm64" ]]; then
    echo "production DMG contains a non-arm64-only Mach-O: $bin ($archs)" >&2
    exit 1
  fi
done < <(find "$STAGED_APP" -type f -print0)
if [[ "$MACHO_COUNT" -eq 0 ]]; then
  echo "production DMG staging contains no Mach-O code" >&2
  exit 1
fi

echo "==> Signing app, helper, and widget with production profiles"
CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
SIGN_TIMESTAMP=secure \
ENTITLEMENTS_PATH="$ENTITLEMENTS_DIR/app.plist" \
HELPER_ENTITLEMENTS_PATH="$ENTITLEMENTS_DIR/helper.plist" \
WIDGET_ENTITLEMENTS_PATH="$ENTITLEMENTS_DIR/widget.plist" \
APP_PROVISIONING_PROFILE="$DEVELOPER_ID_APP_PROVISIONING_PROFILE" \
HELPER_PROVISIONING_PROFILE="$DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE" \
WIDGET_PROVISIONING_PROFILE="$DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE" \
  "$ROOT_DIR/script/sign_app_bundle.sh" "$STAGED_APP"

verify_final_app "$STAGED_APP" 2>&1 | tee "$EVIDENCE_DIR/pre-notary-app-verification.txt"

echo "==> Notarizing and stapling the app payload"
APP_NOTARY_ZIP="$WORK_DIR/$ARTIFACT_STEM-app.zip"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$STAGED_APP" "$APP_NOTARY_ZIP"
python3 "$ROOT_DIR/script/notary_submit_with_evidence.py" \
  --artifact "$APP_NOTARY_ZIP" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --evidence-prefix "$EVIDENCE_DIR/app-notary"
xcrun stapler staple "$STAGED_APP"
xcrun stapler validate "$STAGED_APP"
spctl -a -vv "$STAGED_APP" 2>&1 | tee "$EVIDENCE_DIR/app-gatekeeper.txt"
verify_final_app "$STAGED_APP" 2>&1 | tee "$EVIDENCE_DIR/stapled-app-verification.txt"

capture_bundle_evidence "app" "$STAGED_APP"
capture_bundle_evidence "helper" "$STAGED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app"
capture_bundle_evidence "widget" "$STAGED_APP/Contents/PlugIns/$WIDGET_APPEX_NAME"

echo "==> Creating and signing final DMG: $DMG_OUT"
mkdir -p "$DMG_STAGE"
ditto "$STAGED_APP" "$DMG_APP"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$DMG_STAGE" \
  -fs HFS+ \
  -format UDZO \
  "$DMG_OUT" >/dev/null
codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_OUT"
verify_final_dmg_signature "$DMG_OUT"
codesign -dvvv "$DMG_OUT" >"$EVIDENCE_DIR/dmg-codesign.txt" 2>&1

echo "==> Notarizing and stapling final DMG"
python3 "$ROOT_DIR/script/notary_submit_with_evidence.py" \
  --artifact "$DMG_OUT" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --evidence-prefix "$EVIDENCE_DIR/dmg-notary"
xcrun stapler staple "$DMG_OUT"
xcrun stapler validate "$DMG_OUT"
verify_final_dmg_signature "$DMG_OUT"
codesign -dvvv "$DMG_OUT" >"$EVIDENCE_DIR/dmg-codesign.txt" 2>&1
hdiutil verify "$DMG_OUT" 2>&1 | tee "$EVIDENCE_DIR/hdiutil-verify.txt"
spctl -a -t open --context context:primary-signature -vv "$DMG_OUT" \
  2>&1 | tee "$EVIDENCE_DIR/dmg-gatekeeper.txt"
hdiutil imageinfo -plist "$DMG_OUT" >"$EVIDENCE_DIR/dmg-imageinfo.plist"

echo "==> Mounting and verifying the exact final artifact"
MOUNT_POINT="$WORK_DIR/mount"
mkdir -p "$MOUNT_POINT"
hdiutil attach \
  -readonly \
  -nobrowse \
  -noautoopen \
  -mountpoint "$MOUNT_POINT" \
  -plist \
  "$DMG_OUT" >"$EVIDENCE_DIR/dmg-attach.plist"
plutil -lint "$EVIDENCE_DIR/dmg-attach.plist" >/dev/null
MOUNTED_APP="$MOUNT_POINT/$DMG_NAME.app"
test -d "$MOUNTED_APP"
diff -qr "$DMG_APP" "$MOUNTED_APP" >/dev/null
xcrun stapler validate "$MOUNTED_APP"
spctl -a -vv "$MOUNTED_APP" 2>&1 | tee "$EVIDENCE_DIR/mounted-app-gatekeeper.txt"
verify_final_app "$MOUNTED_APP" 2>&1 | tee "$EVIDENCE_DIR/mounted-app-verification.txt"

echo "==> Installing exact final-DMG app at $INSTALL_APP_PATH"
python3 "$ROOT_DIR/script/verify_production_app_runtime.py" \
  --quiesce-only \
  --process-name "$APP_NAME" \
  --process-name "$MCP_HOST_PRODUCT" \
  --process-name "$WIDGET_EXECUTABLE"
INSTALLED_APP="$INSTALL_APP_PATH"
rm -rf "$INSTALLED_APP"
INSTALLED_BY_THIS_RUN=1
ditto "$MOUNTED_APP" "$INSTALLED_APP"
diff -qr "$MOUNTED_APP" "$INSTALLED_APP" >/dev/null
xcrun stapler validate "$INSTALLED_APP"
spctl -a -vv "$INSTALLED_APP" 2>&1 | tee "$EVIDENCE_DIR/installed-app-gatekeeper.txt"
verify_final_app "$INSTALLED_APP" 2>&1 | tee "$EVIDENCE_DIR/installed-app-verification.txt"
capture_bundle_evidence "installed-app" "$INSTALLED_APP"

echo "==> Permanently clearing production local state before first launch"
python3 "$ROOT_DIR/script/reset_production_app_group.py" \
  --helper-binary "$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT" \
  --evidence "$EVIDENCE_DIR/installed-app-group-reset.json" \
  --process-name "$APP_NAME" \
  --process-name "$MCP_HOST_PRODUCT" \
  --process-name "$WIDGET_EXECUTABLE"

echo "==> Cold-launching exact installed main app and verifying plugin registration"
PRE_SMOKE_RUNTIME_EVIDENCE="$WORK_DIR/pre-smoke-runtime-evidence"
mkdir "$PRE_SMOKE_RUNTIME_EVIDENCE"
python3 "$ROOT_DIR/script/verify_production_app_runtime.py" \
  --mounted-app "$MOUNTED_APP" \
  --installed-app "$INSTALLED_APP" \
  --evidence-dir "$PRE_SMOKE_RUNTIME_EVIDENCE" \
  --app-name "$APP_NAME" \
  --widget-bundle-id "$WIDGET_BUNDLE_ID" \
  --widget-appex-name "$WIDGET_APPEX_NAME" \
  --process-name "$APP_NAME" \
  --process-name "$MCP_HOST_PRODUCT" \
  --process-name "$WIDGET_EXECUTABLE"

echo "==> Running destructive production App Group MCP round-trip"
MCP_HOST_BINARY="$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT" \
  "$ROOT_DIR/script/mcp_stdio_smoke.py" --reset-real-app-group \
  2>&1 | tee "$EVIDENCE_DIR/mcp-production-app-group-smoke.txt"

echo "==> Permanently clearing production local state after MCP smoke"
python3 "$ROOT_DIR/script/reset_production_app_group.py" \
  --helper-binary "$INSTALLED_APP/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/MacOS/$MCP_HOST_PRODUCT" \
  --evidence "$EVIDENCE_DIR/final-app-group-reset.json" \
  --process-name "$APP_NAME" \
  --process-name "$MCP_HOST_PRODUCT" \
  --process-name "$WIDGET_EXECUTABLE"

echo "==> Final clean-state launch of the exact installed production app"
python3 "$ROOT_DIR/script/verify_production_app_runtime.py" \
  --mounted-app "$MOUNTED_APP" \
  --installed-app "$INSTALLED_APP" \
  --evidence-dir "$EVIDENCE_DIR" \
  --app-name "$APP_NAME" \
  --widget-bundle-id "$WIDGET_BUNDLE_ID" \
  --widget-appex-name "$WIDGET_APPEX_NAME" \
  --clean-reset-evidence "$EVIDENCE_DIR/final-app-group-reset.json" \
  --process-name "$APP_NAME" \
  --process-name "$MCP_HOST_PRODUCT" \
  --process-name "$WIDGET_EXECUTABLE"

python3 "$ROOT_DIR/script/generate_production_dmg_evidence.py" \
  --dmg "$DMG_OUT" \
  --app "$INSTALLED_APP" \
  --evidence-dir "$EVIDENCE_DIR" \
  --team-id "$APPLE_TEAM_ID"
PACKAGE_SUCCEEDED=1

echo
echo "Production DMG ready: $DMG_OUT"
echo "Checksum: $DMG_OUT.sha256"
echo "Release evidence: $EVIDENCE_DIR/release-evidence.json"
ls -lh "$DMG_OUT" "$DMG_OUT.sha256"
