#!/usr/bin/env bash
# Build LorvexMobileApp for the iOS simulator through the XcodeGen project,
# reusing dist/DerivedData-LorvexMobileApp so incremental builds stay short.
# Package resolution is pinned (lib_xcode_package_lock.sh), so the tracked
# Package.resolved files are never rewritten. Never wipes the cache.
#
# Usage: script/ios_sim_build.sh
# Env:   LORVEX_SIM_DEVICE  simulator device name (default: iPhone 17 Pro); the
#                           device on the newest iOS runtime with that name is used
#        LORVEX_SIM_UDID    exact device UDID, overriding the name lookup
#        LORVEX_XCODE_JOBS  xcodebuild -jobs (default: 4, keeps the machine responsive)
#        LORVEX_IOS_CARPLAY 1 builds the app with Config/CarPlaySimulator.xcconfig, which
#                           signs LorvexMobileApp with the simulator CarPlay entitlements
#                           (script/carplay_sim_enable.sh); every other target is unchanged
# Prints the built .app path on success.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME=LorvexMobileApp
DEVICE="${LORVEX_SIM_DEVICE:-iPhone 17 Pro}"
JOBS="${LORVEX_XCODE_JOBS:-4}"
EXTRA_ARGS=()
if [[ "${LORVEX_IOS_CARPLAY:-0}" == "1" ]]; then
  EXTRA_ARGS+=(-xcconfig "$ROOT_DIR/Config/CarPlaySimulator.xcconfig")
fi
PROJECT_DIR="$ROOT_DIR/dist/xcode-$SCHEME"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-$SCHEME"
cd "$ROOT_DIR"
source script/lib_xcode_package_lock.sh
source script/lib_ios_sim_device.sh
UDID="$(resolve_ios_sim_udid "$DEVICE")" || { echo "no available simulator named '$DEVICE'" >&2; exit 1; }
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" --project "$PROJECT_DIR" --project-root "$ROOT_DIR" --quiet
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"
set +o pipefail
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  -jobs "$JOBS" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
  build 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | tail -20
STATUS=${PIPESTATUS[0]}
set -o pipefail
[[ "$STATUS" -eq 0 ]] || exit "$STATUS"
echo "app: $DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"
