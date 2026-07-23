#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
source "$ROOT_DIR/script/lib_launch.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_PLUGINS="$APP_CONTENTS/PlugIns"
APP_BINARY="$APP_MACOS/$APP_NAME"
MCP_HELPER_APP="$APP_HELPERS/$MCP_HOST_PRODUCT.app"
MCP_HELPER_CONTENTS="$MCP_HELPER_APP/Contents"
MCP_HELPER_MACOS="$MCP_HELPER_CONTENTS/MacOS"
MCP_HELPER_RESOURCES="$MCP_HELPER_CONTENTS/Resources"
MCP_HELPER_INFO_PLIST="$MCP_HELPER_CONTENTS/Info.plist"
MCP_HELPER="$MCP_HELPER_MACOS/$MCP_HOST_PRODUCT"
WIDGET_APPEX="$APP_PLUGINS/$WIDGET_APPEX_NAME"
WIDGET_CONTENTS="$WIDGET_APPEX/Contents"
WIDGET_MACOS="$WIDGET_CONTENTS/MacOS"
WIDGET_RESOURCES="$WIDGET_CONTENTS/Resources"
WIDGET_BINARY="$WIDGET_MACOS/$WIDGET_EXECUTABLE"
WIDGET_INFO_PLIST="$WIDGET_CONTENTS/Info.plist"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Packaging entry points (script/package_local.sh, and transitively
# script/archive_mas.sh / script/archive_local.sh) export
# LORVEX_BUILD_CONFIGURATION=release so the staged binaries that ship are
# optimized Release builds, not the -Onone Debug build. The interactive dev
# loop (`run`, `--debug`, `--logs`, `--telemetry`, `--verify`) leaves this
# unset and keeps building Debug for fast iteration.
BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-debug}"
case "$BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "unknown LORVEX_BUILD_CONFIGURATION: $BUILD_CONFIGURATION (expected debug or release)" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

local_code_sign_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi

  # A stable local signing identity keeps macOS TCC decisions (Calendar,
  # Reminders, protected file/folder access) attached to the app across rebuilds.
  # Ad-hoc signatures embed a changing code hash, which can make every run look
  # like a different app to the permission system.
  security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Developer ID Application:|\"Apple Development:/{print $2; exit}'
}

LOCAL_CODE_SIGN_IDENTITY="$(local_code_sign_identity)"
if [[ -z "$LOCAL_CODE_SIGN_IDENTITY" ]]; then
  LOCAL_CODE_SIGN_IDENTITY="-"
fi

LOCALIZATION_METADATA="$(python3 - <<'PY'
import sys
from pathlib import Path

root = Path.cwd()
sys.path.insert(0, str(root / "script"))

from verify_localization_catalog import (  # noqa: E402
    CATALOG_PATH,
    MODULE_CATALOGS,
    load_catalog,
    required_languages,
    required_source_language,
)

catalog_paths = [CATALOG_PATH] + [path for _, path, _ in MODULE_CATALOGS]
catalogs = []
for path in catalog_paths:
    catalog, failures = load_catalog(path)
    if failures:
        raise SystemExit("\n".join(failures))
    catalogs.append(catalog)

print(required_source_language(catalogs))
for language in required_languages(catalogs):
    print(f"    <string>{language}</string>")
PY
)"
LOCALIZATION_SOURCE_LANGUAGE="$(printf "%s\n" "$LOCALIZATION_METADATA" | sed -n '1p')"
LOCALIZATION_PLIST_ENTRIES="$(printf "%s\n" "$LOCALIZATION_METADATA" | sed '1d')"

# Replace only a prior instance launched from THIS build's bundle. A blanket
# kill by process name would also take down a developer's own running Lorvex.app
# (or another checkout's copy) that this script never launched; matching the
# absolute in-bundle binary path scopes the kill to instances this script itself
# started under dist/.
pkill -f "$APP_BINARY" >/dev/null 2>&1 || true

swift build -c "$BUILD_CONFIGURATION" --product "$APP_PRODUCT_NAME"
swift build -c "$BUILD_CONFIGURATION" --product "LorvexWidgetBundle"
swift build -c "$BUILD_CONFIGURATION" --product "$MCP_HOST_PRODUCT"
SWIFT_BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$SWIFT_BIN_PATH/$APP_PRODUCT_NAME"
WIDGET_BUILD_BINARY="$SWIFT_BIN_PATH/LorvexWidgetBundle"
MCP_BUILD_BINARY="$SWIFT_BIN_PATH/$MCP_HOST_PRODUCT"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$MCP_HELPER_MACOS" "$MCP_HELPER_RESOURCES" "$APP_CONTENTS/Resources" "$WIDGET_MACOS" "$WIDGET_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$WIDGET_BUILD_BINARY" "$WIDGET_BINARY"
chmod +x "$WIDGET_BINARY"
cp "$ROOT_DIR/Config/LorvexWidgetExtension-Info.plist" "$WIDGET_INFO_PLIST"
cp "$ROOT_DIR/Config/PrivacyInfo.xcprivacy" "$APP_CONTENTS/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/Config/PrivacyInfo.xcprivacy" "$WIDGET_RESOURCES/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/Resources/AppIcon/LorvexAppIcon.icns" "$APP_CONTENTS/Resources/LorvexAppIcon.icns"
# Compile a macOS asset catalog carrying the app icon. App Store requires a
# compiled Assets.car with a named app-icon set (reject ITMS-90546); the .icns
# alone (Finder/dock fallback) is not enough. SwiftPM has no asset-catalog
# build step, so synthesize a single-size macOS AppIcon from the 1024 master
# and compile it with actool into the app's Resources. CFBundleIconName above
# names this set ("AppIcon").
ICON_CATALOG_DIR="$(mktemp -d)"
mkdir -p "$ICON_CATALOG_DIR/Assets.xcassets/AppIcon.appiconset"
cp "$ROOT_DIR/Resources/AppIcon/master_1024.png" \
  "$ICON_CATALOG_DIR/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
cat > "$ICON_CATALOG_DIR/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$ICON_CATALOG_DIR/Assets.xcassets/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
xcrun actool "$ICON_CATALOG_DIR/Assets.xcassets" \
  --compile "$APP_CONTENTS/Resources" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon AppIcon \
  --output-partial-info-plist "$ICON_CATALOG_DIR/partial.plist" \
  --output-format human-readable-text >/dev/null
test -f "$APP_CONTENTS/Resources/Assets.car"
rm -rf "$ICON_CATALOG_DIR"
# NSHumanReadableCopyright (below) tells the user "See LICENSE"; stage the
# actual file so that reference resolves inside the shipped bundle instead of
# only in the source checkout.
cp "$ROOT_DIR/LICENSE" "$APP_CONTENTS/Resources/LICENSE"
# The helper ships as a minimal bundled app (not a bare Mach-O) so the sandbox
# can initialize a container for it and it can carry its own app-group
# provisioning profile — a bare executable has no Info.plist and is killed at
# launch when sandbox-entitled. MCP clients launch the inner binary directly
# by path; running a bundled executable this way needs no LaunchServices.
cp "$MCP_BUILD_BINARY" "$MCP_HELPER"
chmod +x "$MCP_HELPER"
cp "$ROOT_DIR/Config/LorvexMCPHost-Info.plist" "$MCP_HELPER_INFO_PLIST"
cp "$ROOT_DIR/Config/PrivacyInfo.xcprivacy" "$MCP_HELPER_RESOURCES/PrivacyInfo.xcprivacy"

# Copy the SwiftPM resource bundles (`<Package>_<Target>.bundle`) into the app
# so `Bundle.module` resolves them on any machine. Without this the bundled
# `schema.sql` / `checksums.lock` (LorvexCore) and the per-module localization
# catalogs are missing from the distributed `.app`, and the app falls back to
# the in-repo `#filePath` dev path — which only exists on the build machine.
BUILD_BIN_DIR="$SWIFT_BIN_PATH"
for bundle in "$BUILD_BIN_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  rm -rf "$APP_CONTENTS/Resources/$(basename "$bundle")"
  cp -R "$bundle" "$APP_CONTENTS/Resources/"
done

# The MCP helper and widget extension are separate processes with their own
# `Bundle.main`, so neither can rely on the outer app's Contents/Resources.
# Both write the shared database and therefore need LorvexCore's schema bundle
# and LorvexSync's numbered payload-contract bundle in their own sealed resource
# directory. Missing either is a packaging error, never a source-tree fallback.
for process_bundle_name in \
  "LorvexApple_LorvexCore.bundle" \
  "LorvexAppleCore_LorvexSync.bundle"
do
  process_bundle="$BUILD_BIN_DIR/$process_bundle_name"
  if [[ ! -d "$process_bundle" ]]; then
    echo "missing required process resource bundle: $process_bundle" >&2
    exit 1
  fi
  for process_resources in "$MCP_HELPER_RESOURCES" "$WIDGET_RESOURCES"; do
    rm -rf "$process_resources/$process_bundle_name"
    cp -R "$process_bundle" "$process_resources/"
  done
done

# Compile String Catalogs (`*.xcstrings`) into per-language `.lproj/*.strings`
# inside each resource bundle. `swift build` copies the raw `.xcstrings` but does
# NOT compile it, so `NSLocalizedString(bundle:)` finds no string tables and the
# app shows the English source for every locale — the in-app language switch
# (and every non-English language) silently has no effect.
#
# Compile both the staged app's catalogs and the SwiftPM build-directory bundles:
# `Bundle.module` resolves to the build-directory bundle whenever it exists — i.e.
# on the developer's machine — so compiling only the staged copy leaves a locally
# run app showing English for every locale. `--best-effort` keeps this dev/packaging
# loop going with a warning if `xcstringstool` is unavailable, rather than failing
# the build (verify_all.sh runs the same script strictly, where tests depend on it).
"$ROOT_DIR/script/compile_xcstrings.sh" --best-effort "$APP_CONTENTS/Resources" "$BUILD_BIN_DIR"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>LorvexAppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>$LOCALIZATION_SOURCE_LANGUAGE</string>
  <key>CFBundleLocalizations</key>
  <array>
$LOCALIZATION_PLIST_ENTRIES
  </array>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$URL_SCHEME</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>$APP_CATEGORY</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>Licensed under Apache-2.0. See LICENSE.</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
  <string>$CALENDAR_WRITE_USAGE_DESCRIPTION</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>$CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSUserActivityTypes</key>
  <array>
    <string>com.lorvex.apple.openTask</string>
    <string>com.lorvex.apple.openDestination</string>
    <string>com.lorvex.apple.openList</string>
  </array>
</dict>
</plist>
PLIST

# Sign inside-out (helper → widget → app). An unsigned bundle traps at startup:
# the executable target's `Bundle.module` resource lookup fails its assertion
# before the first window appears, so the app dies on launch. Prefer a stable
# local signing certificate when one exists; fall back to ad-hoc on machines
# without a codesigning identity. Local run builds intentionally stay
# non-sandboxed; app group surfaces are guarded at runtime so a dev build without
# app group entitlements does not touch the shared container and trigger macOS
# "data from other apps" prompts.
if [[ "$LOCAL_CODE_SIGN_IDENTITY" == "-" ]]; then
  echo "==> Signing staged app bundle ad-hoc"
else
  echo "==> Signing staged app bundle with local identity $LOCAL_CODE_SIGN_IDENTITY"
fi
codesign --force --sign "$LOCAL_CODE_SIGN_IDENTITY" --timestamp=none "$MCP_HELPER_APP"
codesign --force --sign "$LOCAL_CODE_SIGN_IDENTITY" --timestamp=none "$WIDGET_APPEX"
codesign --force --deep --sign "$LOCAL_CODE_SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

refresh_launchservices_registration() {
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_BUNDLE"
  else
    echo "WARNING: lsregister not found; lorvex:// may still resolve to a stale app bundle." >&2
  fi
}

refresh_launchservices_registration

case "$MODE" in
  --stage-only|stage)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    wait_for_app_launch "$APP_NAME"
    ;;
  *)
    echo "usage: $0 [run|--stage-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
