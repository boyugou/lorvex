#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
MCP_HELPER_APP="$APP_BUNDLE/Contents/Helpers/$MCP_HOST_PRODUCT.app"
MCP_HELPER="$MCP_HELPER_APP/Contents/MacOS/$MCP_HOST_PRODUCT"
MCP_HELPER_INFO_PLIST="$MCP_HELPER_APP/Contents/Info.plist"
WIDGET_APPEX="$APP_BUNDLE/Contents/PlugIns/$WIDGET_APPEX_NAME"
WIDGET_BINARY="$WIDGET_APPEX/Contents/MacOS/$WIDGET_EXECUTABLE"
WIDGET_INFO_PLIST="$WIDGET_APPEX/Contents/Info.plist"
WIDGET_PRIVACY_MANIFEST="$WIDGET_APPEX/Contents/Resources/PrivacyInfo.xcprivacy"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_PRIVACY_MANIFEST="$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
MCP_CLIENT_CONFIG="$ROOT_DIR/dist/lorvex-apple-mcp-client.json"

# Packaging ships the app: force a Release/-O build so the distributed
# binaries are optimized (not Debug/-Onone) and any `#if DEBUG` branches are
# excluded. script/archive_mas.sh and script/archive_local.sh both route
# through this script, so this covers every packaging entry point without
# touching the interactive dev loop (script/build_and_run.sh's default `run`
# mode stays Debug because it does not set this variable).
export LORVEX_BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-release}"

cd "$ROOT_DIR"

./script/verify_apple_strategy.py
./script/verify_core_service_coverage.py
./script/verify_hotspots.py
./script/build_and_run.sh --stage-only

# App Store submission compliance the SwiftPM staging does not produce (Xcode
# would, but the macOS app is a pure-SwiftPM build).
#
# Every embedded bundle needs a CFBundleIdentifier or App Store Connect rejects
# the payload (error 90276), and on macOS it must be wrapped in `Contents/`
# rather than left in the flat iOS shape `swift build` emits. build_and_run.sh
# produces both; enumerate bundle DIRECTORIES here rather than Info.plist paths,
# so a bundle carrying no Info.plist at all is reported instead of being
# invisible to the walk. Runs before verification and signing, so the check sees
# exactly what gets signed.
while IFS= read -r -d '' bundle_dir; do
  bundle_plist="$bundle_dir/Contents/Info.plist"
  if [[ ! -d "$bundle_dir/Contents" ]]; then
    echo "staged bundle uses the flat iOS layout: $bundle_dir" >&2
    echo "build_and_run.sh must wrap it into Contents/Info.plist + Contents/Resources" >&2
    exit 1
  fi
  if [[ ! -f "$bundle_plist" ]]; then
    echo "staged bundle has no Info.plist: $bundle_dir" >&2
    echo "its SwiftPM package likely omits defaultLocalization; build_and_run.sh must stamp one" >&2
    exit 1
  fi
  if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle_plist" \
    >/dev/null 2>&1; then
    echo "staged bundle Info.plist has no CFBundleIdentifier: $bundle_plist" >&2
    exit 1
  fi
done < <(find "$APP_BUNDLE" -type d -name "*.bundle" -print0)

# The widget app-extension needs LSMinimumSystemVersion (error 90360); SwiftPM
# does not stamp it. Mirror the app's floor, before signing so the value is
# covered by the signature. Idempotent: skipped when the key is already present.
if ! /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" \
  "$APP_BUNDLE/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy \
    -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" \
    "$APP_BUNDLE/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/Info.plist"
fi

test -d "$APP_BUNDLE"
test -x "$APP_BINARY"
test -d "$MCP_HELPER_APP"
test -f "$MCP_HELPER_INFO_PLIST"
test -x "$MCP_HELPER"
test -d "$WIDGET_APPEX"
test -x "$WIDGET_BINARY"
# Every app wrapper carries a PkgInfo; app extensions deliberately do not.
grep -qxF "APPL????" "$APP_BUNDLE/Contents/PkgInfo"
grep -qxF "APPL????" "$MCP_HELPER_APP/Contents/PkgInfo"
test ! -e "$WIDGET_APPEX/Contents/PkgInfo"
# Xcode omits Contents/Frameworks when a product embeds no framework or dylib.
# An empty one would ship as a structural deviation, so reject it while still
# allowing a build that genuinely stages something there.
if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]] &&
  [[ -z "$(ls -A "$APP_BUNDLE/Contents/Frameworks")" ]]; then
  echo "staged app carries an empty Contents/Frameworks directory" >&2
  exit 1
fi
for required_bundle in \
  "LorvexApple_LorvexCore.bundle" \
  "LorvexAppleCore_LorvexSync.bundle"
do
  test -d "$APP_BUNDLE/Contents/Resources/$required_bundle"
  test -d "$MCP_HELPER_APP/Contents/Resources/$required_bundle"
  test -d "$WIDGET_APPEX/Contents/Resources/$required_bundle"
done
# App Intents metadata, which release staging extracts (build_and_run.sh): the
# app's Shortcuts actions and App Shortcuts, and the widget's configuration
# intent, buttons, and control. A bundle without it ships intents the system
# never sees, and an AppIntentConfiguration widget never leaves its placeholder.
for intents_resources in "$APP_BUNDLE/Contents/Resources" "$WIDGET_APPEX/Contents/Resources"; do
  test -s "$intents_resources/Metadata.appintents/extract.actionsdata"
  test -s "$intents_resources/en.lproj/Localizable.strings"
done
test -s "$APP_BUNDLE/Contents/Resources/en.lproj/AppShortcuts.strings"
# Localized Info.plist values: every language a bundle declares carries its
# InfoPlist.strings, so the bundle name and the calendar permission prompts
# follow the system language, and the English prompts match app_metadata.sh.
for staged_plist in "$INFO_PLIST" "$WIDGET_INFO_PLIST"; do
  staged_resources="$(dirname "$staged_plist")/Resources"
  staged_languages="$(plutil -extract CFBundleLocalizations json -o - "$staged_plist" \
    | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)))')"
  test -n "$staged_languages"
  while IFS= read -r staged_language; do
    plutil -lint "$staged_resources/$staged_language.lproj/InfoPlist.strings" >/dev/null
  done <<<"$staged_languages"
done
plutil -extract NSCalendarsWriteOnlyAccessUsageDescription raw -o - \
  "$APP_BUNDLE/Contents/Resources/en.lproj/InfoPlist.strings" \
  | grep -qx "$CALENDAR_WRITE_USAGE_DESCRIPTION"
plutil -extract NSCalendarsFullAccessUsageDescription raw -o - \
  "$APP_BUNDLE/Contents/Resources/en.lproj/InfoPlist.strings" \
  | grep -qx "$CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION"
"$ROOT_DIR/script/verify_macho_distribution.py" "$APP_BUNDLE"
"$ROOT_DIR/script/verify_macho_closure.py" "$APP_BUNDLE"
"$ROOT_DIR/script/verify_swiftpm_resource_bundles.py" "$APP_BUNDLE"
plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$WIDGET_INFO_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" \
  | grep -qx "$APP_NAME"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$INFO_PLIST" \
  | grep -qx "$APP_DISPLAY_NAME"
/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST" \
  | grep -qx "$APP_DISPLAY_NAME"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" \
  | grep -qx "$BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$INFO_PLIST" \
  | grep -qx "APPL"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" \
  | grep -qx "$MARKETING_VERSION"
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" \
  | grep -qx "$BUILD_VERSION"
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" \
  | grep -qx "$MIN_SYSTEM_VERSION"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLName" "$INFO_PLIST" \
  | grep -qx "$BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$INFO_PLIST" \
  | grep -qx "$URL_SCHEME"
/usr/libexec/PlistBuddy -c "Print :NSCalendarsWriteOnlyAccessUsageDescription" "$INFO_PLIST" \
  | grep -qx "$CALENDAR_WRITE_USAGE_DESCRIPTION"
/usr/libexec/PlistBuddy -c "Print :NSCalendarsFullAccessUsageDescription" "$INFO_PLIST" \
  | grep -qx "$CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION"
/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" "$INFO_PLIST" \
  | grep -qx "$APP_CATEGORY"
# legal-L3: export-compliance declaration. Lorvex only uses SHA-256 hashing
# (idempotency keys, content checksums), which is exempt; without this key an
# App Store Connect upload blocks on the export-compliance questionnaire.
/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$INFO_PLIST" \
  | grep -qx "false"
/usr/libexec/PlistBuddy -c "Print :NSPrincipalClass" "$INFO_PLIST" \
  | grep -qx "NSApplication"
for privacy_manifest in "$APP_PRIVACY_MANIFEST" "$WIDGET_PRIVACY_MANIFEST"; do
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
/usr/libexec/PlistBuddy -c "Print :NSUserActivityTypes:0" "$INFO_PLIST" \
  | grep -qx "com.lorvex.apple.openTask"
/usr/libexec/PlistBuddy -c "Print :NSUserActivityTypes:1" "$INFO_PLIST" \
  | grep -qx "com.lorvex.apple.openDestination"
/usr/libexec/PlistBuddy -c "Print :NSUserActivityTypes:2" "$INFO_PLIST" \
  | grep -qx "com.lorvex.apple.openList"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$WIDGET_INFO_PLIST" \
  | grep -qx "$WIDGET_EXECUTABLE"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$WIDGET_INFO_PLIST" \
  | grep -qx "$WIDGET_BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$WIDGET_INFO_PLIST" \
  | grep -qx "XPC!"
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$WIDGET_INFO_PLIST" \
  | grep -qx "$WIDGET_EXTENSION_POINT_IDENTIFIER"
plutil -lint "$MCP_HELPER_INFO_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$MCP_HELPER_INFO_PLIST" \
  | grep -qx "$MCP_HOST_PRODUCT"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$MCP_HELPER_INFO_PLIST" \
  | grep -qx "$MCP_HOST_BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$MCP_HELPER_INFO_PLIST" \
  | grep -qx "APPL"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$MCP_HELPER_INFO_PLIST" \
  | grep -qx "true"
/usr/libexec/PlistBuddy -c "Print :LSBackgroundOnly" "$MCP_HELPER_INFO_PLIST" \
  | grep -qx "true"

"$ROOT_DIR/script/sign_app_bundle.sh" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$WIDGET_APPEX"
codesign --verify --strict --verbose=2 "$MCP_HELPER_APP"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -dvvv "$APP_BUNDLE" >/dev/null 2>&1
codesign_details="$(codesign -dvvv "$APP_BUNDLE" 2>&1)"
grep -q "flags=.*runtime" <<<"$codesign_details"
# The verifier itself skips entitlement assertions for ad-hoc/local-identity
# signatures, so it is safe (and policy-deduplicating) to call unconditionally.
"$ROOT_DIR/script/verify_codesign_entitlements.py" "$APP_BUNDLE"
"$ROOT_DIR/script/generate_mcp_client_config.py" \
  --app-bundle "$APP_BUNDLE" \
  --output "$MCP_CLIENT_CONFIG"
"$ROOT_DIR/script/verify_mcp_client_config.py" "$MCP_CLIENT_CONFIG" "$APP_BUNDLE"
# Real-identity signing makes the helper sandboxed, so it must exercise the
# production App Group. The smoke then also requires the caller's explicit
# LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1 acknowledgement. Ad-hoc builds are
# unsandboxed and still run entirely against a temporary database.
#
# App Store signing is the exception: the helper carries an
# application-identifier entitlement, and macOS only honors a sandboxed app's
# App Group grant when the app runs from an App Store install context. A bare
# in-tree launch fails the App Group DB open (the process exits, so the stdio
# smoke sees a broken pipe). The MCP logic is identical to the ad-hoc/Developer
# ID builds the smoke does cover, so a MAS package skips this local run; the
# App Store install validates it in the environment where App Groups actually
# resolve.
if [[ "${LORVEX_MAS_SKIP_LOCAL_MCP_SMOKE:-0}" == "1" ]]; then
  echo "MCP stdio smoke skipped: App Store-signed helper cannot open its App Group outside an App Store install" >&2
else
  MCP_HOST_BINARY="$MCP_HELPER" "$ROOT_DIR/script/mcp_stdio_smoke.py" --reset-real-app-group
fi

if spctl -a -vv "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "spctl accepted local app bundle"
else
  echo "spctl did not accept the ad-hoc signed local app bundle; expected for non-notarized development builds" >&2
fi

echo "Local package verification passed: $APP_BUNDLE"
