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

# App Intents metadata. Shortcuts actions, App Shortcuts, widget configuration,
# interactive widget buttons, and controls all find a bundle's intents through
# its Metadata.appintents, which Xcode writes and `swift build` does not.
# Release staging has the compiler record each App Intents conformance's
# constant values, and extract_app_intents_metadata.py (below) turns them into
# the app's and the widget's metadata. Every product shares the flags so the
# modules they share build once. Debug staging leaves them off so its build
# matches plain `swift build` / `swift test` and keeps their build cache.
SWIFT_BUILD_FLAGS=()
if [[ "$BUILD_CONFIGURATION" == release ]]; then
  SWIFT_BUILD_FLAGS=(
    -Xswiftc -emit-const-values
    -Xswiftc -const-gather-protocols-list
    -Xswiftc "$ROOT_DIR/Config/AppIntentsConstValueProtocols.json"
  )
fi

# `${array[@]+...}` expands an empty array under `set -u` on bash 3.2 too.
swift build -c "$BUILD_CONFIGURATION" --product "$APP_PRODUCT_NAME" ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"}
swift build -c "$BUILD_CONFIGURATION" --product "LorvexWidgetBundle" ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"}
swift build -c "$BUILD_CONFIGURATION" --product "$MCP_HOST_PRODUCT" ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"}
SWIFT_BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"})"
BUILD_BINARY="$SWIFT_BIN_PATH/$APP_PRODUCT_NAME"
WIDGET_BUILD_BINARY="$SWIFT_BIN_PATH/LorvexWidgetBundle"
MCP_BUILD_BINARY="$SWIFT_BIN_PATH/$MCP_HOST_PRODUCT"

rm -rf "$APP_BUNDLE"
# No Contents/Frameworks: the macOS product statically links every SwiftPM
# library into its executables and ships no embedded framework or dylib. Xcode
# omits the directory entirely in that case, and an empty Frameworks/ is a
# structural deviation. Every consumer (sign_app_bundle.sh, notarize_archive.sh,
# verify_developer_id_provisioning.py) already treats it as optional, so a
# future step that genuinely stages a framework creates it itself.
mkdir -p "$APP_MACOS" "$MCP_HELPER_MACOS" "$MCP_HELPER_RESOURCES" "$APP_CONTENTS/Resources" "$WIDGET_MACOS" "$WIDGET_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$WIDGET_BUILD_BINARY" "$WIDGET_BINARY"
chmod +x "$WIDGET_BINARY"
cp "$ROOT_DIR/Config/LorvexWidgets-Info.plist" "$WIDGET_INFO_PLIST"
cp "$ROOT_DIR/Config/PrivacyInfo.xcprivacy" "$APP_CONTENTS/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/Config/PrivacyInfo.xcprivacy" "$WIDGET_RESOURCES/PrivacyInfo.xcprivacy"
# Localized Info.plist values (bundle names, the calendar permission prompts),
# one `<language>.lproj/InfoPlist.strings` per shipped language. The system
# reads them from the bundle that owns the Info.plist, so the app and the
# widget extension each carry their own; verify_localization_catalog.py keeps
# every Config/InfoPlist target complete in every shipped language.
stage_info_plist_strings() {
  local source_dir="$1" resources="$2" strings language_dir
  for strings in "$source_dir"/*.lproj/InfoPlist.strings; do
    if [[ ! -f "$strings" ]]; then
      echo "missing localized InfoPlist.strings under $source_dir" >&2
      exit 1
    fi
    language_dir="$resources/$(basename "$(dirname "$strings")")"
    mkdir -p "$language_dir"
    cp "$strings" "$language_dir/InfoPlist.strings"
  done
}
stage_info_plist_strings "$ROOT_DIR/Config/InfoPlist/LorvexApple" "$APP_CONTENTS/Resources"
stage_info_plist_strings "$ROOT_DIR/Config/InfoPlist/LorvexWidgets" "$WIDGET_RESOURCES"
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

# Make sure each resource bundle holds compiled per-language `.lproj/*.strings`.
# Swift Build compiles the String Catalogs itself; the native build system only
# copies the raw `.xcstrings`, which leaves `NSLocalizedString(bundle:)` with no
# string tables, so the app would show the English source for every locale.
#
# Check both the staged app's bundles and the SwiftPM build-directory bundles:
# `Bundle.module` resolves to the build-directory bundle whenever it exists — i.e.
# on the developer's machine — so compiling only the staged copy leaves a locally
# run app showing English for every locale. `--best-effort` keeps this dev/packaging
# loop going with a warning if `xcstringstool` is unavailable, rather than failing
# the build (verify_all.sh runs the same script strictly, where tests depend on it).
"$ROOT_DIR/script/compile_xcstrings.sh" --best-effort "$APP_CONTENTS/Resources" "$BUILD_BIN_DIR"

# The App Intents metadata the release build's const values describe (see
# SWIFT_BUILD_FLAGS above): the app's Shortcuts actions and App Shortcuts, and
# the widget's configuration intent, buttons, and control. The expected types
# are the ones whose absence breaks a surface outright — without the widget
# configuration intent, the Today widget never leaves its placeholder.
if [[ "$BUILD_CONFIGURATION" == release ]]; then
  "$ROOT_DIR/script/extract_app_intents_metadata.py" \
    --target "$APP_PRODUCT_NAME" --binary "$APP_BINARY" --bundle-id "$BUNDLE_ID" \
    --resources "$APP_CONTENTS/Resources" --bin-path "$SWIFT_BIN_PATH" \
    --deployment-target "$MIN_SYSTEM_VERSION" \
    --expect CaptureLorvexTaskIntent --expect CompleteLorvexTaskIntent
  "$ROOT_DIR/script/extract_app_intents_metadata.py" \
    --target LorvexWidgetBundle --binary "$WIDGET_BINARY" --bundle-id "$WIDGET_BUNDLE_ID" \
    --resources "$WIDGET_RESOURCES" --bin-path "$SWIFT_BIN_PATH" \
    --deployment-target "$MIN_SYSTEM_VERSION" \
    --expect LorvexTodayWidgetConfigurationIntent --expect WidgetCompleteTaskIntent \
    --expect WidgetCompleteHabitIntent --expect OpenLorvexTodayIntent
fi

# Toolchain provenance (DT*/BuildMachineOSBuild), which Xcode stamps into every
# bundle it builds and this SwiftPM staging path must supply itself. App Store
# ingestion reads these into the build's sdkBuild/platformBuild metadata; a
# macOS TestFlight payload without them is the one observable difference from
# an Xcode-produced bundle when its install-data asset fails to generate.
DT_SDK_VERSION="$(xcrun --show-sdk-version --sdk macosx)"
DT_SDK_BUILD="$(xcrun --show-sdk-build-version --sdk macosx)"
DT_XCODE_BUILD="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
# Xcode's numeric DTXcode form: "26.6" -> "2660" (major, minor, patch-0).
DT_XCODE="$(xcodebuild -version 2>/dev/null | awk '/^Xcode/ {split($2, v, "."); printf "%02d%d%d", v[1], v[2], v[3] + 0}')"
BUILD_MACHINE_OS_BUILD="$(sw_vers -buildVersion)"

# Assert one string key, whether or not the plist already declares it.
# PlistBuddy's `Add` fails on an existing key and `Set` fails on a missing one,
# so neither alone survives both inputs this staging sees.
set_plist_string() {
  local plist="$1" key="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

# Staged copies only (never the tracked Config/ sources): stamp the toolchain
# provenance into the widget, helper, and embedded resource bundle Info.plists.
# The staged Config/ copies arrive without these keys; the resource bundle
# plists SwiftPM generates already carry a full set. Each key is therefore
# asserted rather than added, and an existing value is overwritten because
# these keys must describe the toolchain that produced THIS bundle.
stamp_toolchain_provenance() {
  local plist="$1"
  set_plist_string "$plist" DTSDKName "macosx$DT_SDK_VERSION"
  set_plist_string "$plist" DTSDKBuild "$DT_SDK_BUILD"
  set_plist_string "$plist" DTPlatformName macosx
  set_plist_string "$plist" DTPlatformVersion "$DT_SDK_VERSION"
  set_plist_string "$plist" DTPlatformBuild "$DT_SDK_BUILD"
  set_plist_string "$plist" DTXcode "$DT_XCODE"
  set_plist_string "$plist" DTXcodeBuild "$DT_XCODE_BUILD"
  set_plist_string "$plist" DTCompiler com.apple.compilers.llvm.clang.1_0
  set_plist_string "$plist" BuildMachineOSBuild "$BUILD_MACHINE_OS_BUILD"
  set_plist_string "$plist" CFBundleInfoDictionaryVersion 6.0
  # Dropped and rebuilt, not appended: `Add :CFBundleSupportedPlatforms:0` on a
  # plist that already declares the array leaves a second MacOSX entry behind.
  /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleSupportedPlatforms array" \
    -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    "$plist"
}
stamp_toolchain_provenance "$WIDGET_INFO_PLIST"
stamp_toolchain_provenance "$MCP_HELPER_INFO_PLIST"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DTSDKName</key>
  <string>macosx$DT_SDK_VERSION</string>
  <key>DTSDKBuild</key>
  <string>$DT_SDK_BUILD</string>
  <key>DTPlatformName</key>
  <string>macosx</string>
  <key>DTPlatformVersion</key>
  <string>$DT_SDK_VERSION</string>
  <key>DTPlatformBuild</key>
  <string>$DT_SDK_BUILD</string>
  <key>DTXcode</key>
  <string>$DT_XCODE</string>
  <key>DTXcodeBuild</key>
  <string>$DT_XCODE_BUILD</string>
  <key>DTCompiler</key>
  <string>com.apple.compilers.llvm.clang.1_0</string>
  <key>BuildMachineOSBuild</key>
  <string>$BUILD_MACHINE_OS_BUILD</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
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
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.lorvex.apple.task-ref</string>
      <key>UTTypeDescription</key>
      <string>Lorvex Task Reference</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.lorvex.apple.checklist-item-ref</string>
      <key>UTTypeDescription</key>
      <string>Lorvex Checklist Item Reference</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

add_plist_string_if_absent() {
  local plist="$1" key="$2" value="$3"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}

# Convert a resource bundle from the flat layout `swift build` emits to the
# wrapped layout Xcode produces for macOS: `Contents/Info.plist` beside
# `Contents/Resources/<payload>`. Flat is the iOS bundle shape — every resource
# bundle inside a shipping Xcode-built macOS app is wrapped — and this staging
# is the macOS product's only packaging path (iOS/watchOS archive
# through Xcode, which already gets this right for their platform).
#
# Runtime is unaffected: CFBundle detects the layout and reports `resourceURL`
# as `Contents/Resources` for a wrapped bundle, so `Bundle(url:)` plus
# `url(forResource:)` / `resourceURL` — the only ways this app reaches bundled
# resources — resolve identically either way.
wrap_embedded_bundle() {
  local bundle_dir="$1"
  if [[ -d "$bundle_dir/Contents" ]]; then
    return 0
  fi
  local flat="$bundle_dir.flat"
  rm -rf "$flat"
  mv "$bundle_dir" "$flat"
  mkdir -p "$bundle_dir/Contents/Resources"
  if [[ -f "$flat/Info.plist" ]]; then
    mv "$flat/Info.plist" "$bundle_dir/Contents/Info.plist"
  fi
  while IFS= read -r -d '' entry; do
    mv "$entry" "$bundle_dir/Contents/Resources/"
  done < <(find "$flat" -mindepth 1 -maxdepth 1 -print0)
  rmdir "$flat"
}

# Give every embedded resource bundle the identity Xcode stamps into one: the
# same toolchain provenance the app and its extensions carry, plus the bundle
# identity keys. A SwiftPM package that does not declare `defaultLocalization`
# emits no Info.plist for its resource bundles at all, so the `.bundle`
# directory is not a valid bundle and App Store Connect rejects the payload
# (error 90276 for the missing CFBundleIdentifier). The plist is CREATED when
# absent — not merely patched — so a resource bundle from a package that forgets
# the declaration cannot ship structurally broken. The identifier is derived
# from the bundle name; script/verify_swiftpm_resource_bundles.py re-asserts the
# layout and the whole key set on the staged app.
normalize_embedded_bundle_identity() {
  local bundle_dir="$1"
  local plist="$bundle_dir/Contents/Info.plist"
  local bundle_name slug
  bundle_name="$(basename "$bundle_dir" .bundle)"
  slug="$(printf '%s' "$bundle_name" | tr '[:upper:]_' '[:lower:]-')"
  if [[ ! -f "$plist" ]]; then
    cat >"$plist" <<'EMPTY_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EMPTY_PLIST
  fi
  stamp_toolchain_provenance "$plist"
  add_plist_string_if_absent "$plist" CFBundleIdentifier "com.lorvex.apple.resource.$slug"
  add_plist_string_if_absent "$plist" CFBundleName "$bundle_name"
  add_plist_string_if_absent "$plist" CFBundlePackageType "BNDL"
  add_plist_string_if_absent "$plist" CFBundleInfoDictionaryVersion "6.0"
  add_plist_string_if_absent "$plist" CFBundleDevelopmentRegion "$LOCALIZATION_SOURCE_LANGUAGE"
  add_plist_string_if_absent "$plist" LSMinimumSystemVersion "$MIN_SYSTEM_VERSION"
  plutil -lint "$plist" >/dev/null
}

# `-depth` visits a nested bundle before its container, so wrapping a container
# never invalidates a path still queued for its children.
staged_bundles=()
while IFS= read -r -d '' staged_bundle; do
  staged_bundles+=("$staged_bundle")
done < <(find "$APP_BUNDLE" -depth -type d -name "*.bundle" -print0)
if [[ "${#staged_bundles[@]}" -eq 0 ]]; then
  echo "no SwiftPM resource bundles staged into $APP_BUNDLE" >&2
  exit 1
fi
for staged_bundle in "${staged_bundles[@]}"; do
  wrap_embedded_bundle "$staged_bundle"
  normalize_embedded_bundle_identity "$staged_bundle"
done

# PkgInfo: the four-byte package type plus the four-byte creator signature,
# which Xcode writes for every app wrapper. "????" is the standard "no creator
# code" value and matches the app Info.plists, which declare no
# CFBundleSignature. App extensions do not get one — Xcode ships .appex
# bundles without a PkgInfo.
printf 'APPL????' >"$APP_CONTENTS/PkgInfo"
printf 'APPL????' >"$MCP_HELPER_CONTENTS/PkgInfo"

# Strip extended attributes before signing. Finder metadata, resource forks,
# and provenance attributes picked up while staging otherwise ride into the
# signature's sealed resources, where they are a needless difference from an
# Xcode-produced bundle. sign_app_bundle.sh still hard-fails on a quarantine
# xattr first, so this never masks a quarantined input.
#
# The chmod is a prerequisite, not cosmetics: `cp -R` preserves the mode of a
# dependency's resource file, and SwiftPM's package checkouts are read-only, so
# a staged copy can land at 0444 — which makes removexattr fail with EACCES.
chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

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

# Registers the staged bundle so lorvex:// resolves to this build while it
# runs. Only the modes that launch it register it: a bundle staged for
# packaging is signed and shipped, never run here, and registering it would
# hand this Mac's lorvex:// links and widget taps to the staged copy instead
# of the installed app.
refresh_launchservices_registration() {
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_BUNDLE"
  else
    echo "WARNING: lsregister not found; lorvex:// may still resolve to a stale app bundle." >&2
  fi
}

case "$MODE" in
  --stage-only|stage)
    ;;
  run)
    refresh_launchservices_registration
    open_app
    ;;
  --debug|debug)
    refresh_launchservices_registration
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    refresh_launchservices_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    refresh_launchservices_registration
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    refresh_launchservices_registration
    open_app
    wait_for_app_launch "$APP_NAME"
    ;;
  *)
    echo "usage: $0 [run|--stage-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
