#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 8 ]]; then
  echo "usage: $0 <scheme> <platform> <sdk-products-dir> <sim-name> <bundle-id> <display-name> <min-os> <entitlements>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCHEME="$1"
PLATFORM="$2"
SDK_PRODUCTS_DIR="$3"
SIMULATOR_NAME="$4"
BUNDLE_ID="$5"
DISPLAY_NAME="$6"
MIN_OS="$7"
ENTITLEMENTS_PATH="$8"

PROJECT_DIR="$ROOT_DIR/dist/xcode-$SCHEME"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-$SCHEME"
APP_PATH="$DERIVED_DATA/Build/Products/$SDK_PRODUCTS_DIR/$SCHEME.app"

source "$ROOT_DIR/script/lib_xcode_package_lock.sh"

cd "$ROOT_DIR"

command -v xcodegen >/dev/null

rm -rf "$PROJECT_DIR" "$DERIVED_DATA"
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" \
  --project "$PROJECT_DIR" \
  --project-root "$ROOT_DIR" \
  --quiet

# Seed the committed resolver lock and pin resolution so the destination probe
# and build below read only the pinned versions and never rewrite the
# git-tracked core/Package.resolved (see lib_xcode_package_lock.sh).
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"

SIMULATOR_ID="$(
  /usr/bin/python3 -c '
import json
import sys

name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("name") == name and device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(f"available simulator not found: {name}")
' "$SIMULATOR_NAME" < <(xcrun simctl list devices available -j)
)"
DESTINATION="platform=$PLATFORM,id=$SIMULATOR_ID"

AVAILABLE_DESTINATIONS="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
    -showdestinations 2>&1 || true
)"
if ! grep -q "platform:$PLATFORM" <<<"$AVAILABLE_DESTINATIONS"; then
  {
    echo "No usable $PLATFORM destination is available for $SCHEME."
    echo "Requested simulator: $SIMULATOR_NAME ($SIMULATOR_ID)"
    echo
    echo "xcodebuild destinations:"
    echo "$AVAILABLE_DESTINATIONS"
    echo
    echo "Installed SDKs:"
    xcodebuild -showsdks
    echo
    echo "Installed simulator runtimes:"
    xcrun simctl list runtimes available
  } >&2
  exit 78
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  build

test -d "$APP_PATH"
test -x "$APP_PATH/$SCHEME"
plutil -lint "$APP_PATH/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" \
  | grep -qx "$BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP_PATH/Info.plist" \
  | grep -qx "$DISPLAY_NAME"
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP_PATH/Info.plist" \
  | grep -qx "$MIN_OS"
test -f "$ENTITLEMENTS_PATH"

# An iOS app that embeds a companion watchOS app (a `Watch/<app>.app` payload)
# cannot be installed on a STANDALONE iPhone simulator: simctl rejects it with
# "Watch-only apps cannot be contained in companion apps installed on the
# companion" unless an iPhone+Watch simulator *pair* is booted. The embed is an
# App Store requirement (a watchOS app ships inside its iOS companion), and the
# build above already runs Xcode's ValidateEmbeddedBinary on the watch app and
# its complication, so the artifact is validated. Skip the install/launch smoke
# (which would need a paired sim) for such apps — mirroring how the watchOS
# launch is treated as a warning below — and keep it a hard requirement for apps
# without an embedded watch.
if [[ -d "$APP_PATH/Watch" ]]; then
  echo "note: $SCHEME embeds a watchOS companion app; skipping simulator" \
    "install/launch (needs a booted iPhone+Watch pair). Build, bundle layout," \
    "Info.plist, and entitlements validated."
  echo "$SCHEME simulator verification passed: $APP_PATH on $SIMULATOR_NAME (build + bundle; embeds a watch app)"
  exit 0
fi

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

# `simctl launch` on the watch simulator brittle-fails (`SBMainWorkspace`
# denial / `No such process`) when there is no paired-iPhone sim already
# booted in the same session. The build + install + plist + entitlement
# checks above validate the binary; on watchOS treat a launch failure as a
# warning so the dev loop doesn't hang on an environmental quirk. Other
# platforms keep launch as a hard requirement.
if [[ "$PLATFORM" == "watchOS Simulator" ]]; then
  if ! xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "warning: simctl launch on $SIMULATOR_NAME failed; build + install validated."
  fi
else
  xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null
fi
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "$SCHEME simulator verification passed: $APP_PATH on $SIMULATOR_NAME"
