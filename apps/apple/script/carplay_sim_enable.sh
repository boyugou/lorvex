#!/usr/bin/env bash
# Build, patch, sign, and install a simulator build of LorvexMobileApp that the
# CarPlay Simulator will show, without touching the project or waiting for
# Apple's entitlement approval:
#   1. builds with LORVEX_IOS_CARPLAY=1 (Config/CarPlaySimulator.xcconfig), which
#      links the CarPlay entitlement into the app binary's __TEXT,__entitlements
#      section — the only place a simulator app's entitlements are read from;
#   2. declares the CarPlay template scene in the built app's Info.plist (the
#      block documented in Config/LorvexMobileApp-Info.plist);
#   3. re-signs the app ad hoc with the empty entitlement dictionary Xcode uses
#      for simulator apps (entitlements inside the signature make launchd
#      refuse to spawn the process);
#   4. installs it on the iPhone simulator.
# Device and App Store builds are unaffected: they keep the committed
# Info.plist and entitlements (see docs/SURFACE_DESIGN.md §CarPlay).
#
# Usage: script/carplay_sim_enable.sh
# Env:   LORVEX_SIM_DEVICE / LORVEX_SIM_UDID / LORVEX_XCODE_JOBS as script/ios_sim_build.sh
# Then, in Simulator.app, choose I/O ▸ External Displays ▸ CarPlay and open
# Lorvex on the car screen.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${LORVEX_SIM_DEVICE:-iPhone 17 Pro}"
source "$ROOT_DIR/script/lib_ios_sim_device.sh"
UDID="$(resolve_ios_sim_udid "$DEVICE")" || { echo "no available simulator named '$DEVICE'" >&2; exit 1; }
PB=/usr/libexec/PlistBuddy

LORVEX_IOS_CARPLAY=1 "$ROOT_DIR/script/ios_sim_build.sh" | tail -1
APP="$ROOT_DIR/dist/DerivedData-LorvexMobileApp/Build/Products/Debug-iphonesimulator/LorvexMobileApp.app"
XCENT_DIR="$ROOT_DIR/dist/DerivedData-LorvexMobileApp/Build/Intermediates.noindex/LorvexAppleNative.build/Debug-iphonesimulator/LorvexMobileApp.build"
PLIST="$APP/Info.plist"
[[ -f "$PLIST" ]] || { echo "no simulator app at $APP" >&2; exit 1; }

# 1. The build must have put the entitlement where the simulator reads it.
if [[ "$("$PB" -c "Print :com.apple.developer.carplay-communication" "$XCENT_DIR/LorvexMobileApp.app-Simulated.xcent" 2>/dev/null)" != "true" ]] \
  || ! strings -a "$APP/LorvexMobileApp" | /usr/bin/grep -q "com.apple.developer.carplay-communication"; then
  echo "the build did not embed the CarPlay entitlement; is Config/CarPlaySimulator.xcconfig intact?" >&2
  exit 1
fi

# 2. The scene manifest mirrors the documented block in Config/LorvexMobileApp-Info.plist.
"$PB" -c "Delete :CPSupportsTemplateApplicationScene" "$PLIST" 2>/dev/null || true
"$PB" -c "Delete :UIApplicationSceneManifest" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :CPSupportsTemplateApplicationScene bool true" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest dict" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest:UISceneConfigurations dict" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest:UISceneConfigurations:CPTemplateApplicationSceneSessionRoleApplication array" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest:UISceneConfigurations:CPTemplateApplicationSceneSessionRoleApplication:0 dict" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest:UISceneConfigurations:CPTemplateApplicationSceneSessionRoleApplication:0:UISceneClassName string CPTemplateApplicationScene" "$PLIST"
"$PB" -c "Add :UIApplicationSceneManifest:UISceneConfigurations:CPTemplateApplicationSceneSessionRoleApplication:0:UISceneDelegateClassName string LorvexCarPlay.LorvexCarPlaySceneDelegate" "$PLIST"

# 3. Re-seal the bundle the way Xcode signed it: ad hoc, empty entitlements.
codesign --force --sign - --entitlements "$XCENT_DIR/LorvexMobileApp.app.xcent" --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign - --entitlements "$XCENT_DIR/LorvexMobileApp.app.xcent" "$APP"

# 4. Install.
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
echo "CarPlay-capable Lorvex installed on $DEVICE ($UDID)"
echo "In Simulator.app choose I/O > External Displays > CarPlay, then open Lorvex on the car screen."
