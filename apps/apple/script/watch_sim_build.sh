#!/usr/bin/env bash
# Build LorvexWatchApp for the watchOS simulator through the XcodeGen project,
# reusing dist/DerivedData-LorvexWatchApp so incremental builds stay short.
# Package resolution is pinned (lib_xcode_package_lock.sh), so the tracked
# Package.resolved files are never rewritten. Never wipes the cache.
#
# Usage: script/watch_sim_build.sh
# Env:   LORVEX_WATCH_SIM_DEVICE  simulator device name (default: Apple Watch
#                                 Series 11 (46mm)); the device on the newest
#                                 watchOS runtime with that name is used
#        LORVEX_WATCH_SIM_UDID    exact device UDID, overriding the name lookup
#        LORVEX_XCODE_JOBS        xcodebuild -jobs (default: 4)
# Prints the built .app path on success.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME=LorvexWatchApp
DEVICE="${LORVEX_WATCH_SIM_DEVICE:-Apple Watch Series 11 (46mm)}"
JOBS="${LORVEX_XCODE_JOBS:-4}"
PROJECT_DIR="$ROOT_DIR/dist/xcode-$SCHEME"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-$SCHEME"
cd "$ROOT_DIR"
source script/lib_xcode_package_lock.sh
source script/lib_watch_sim_device.sh
UDID="$(resolve_watch_sim_udid "$DEVICE")" || { echo "no available watch simulator named '$DEVICE'" >&2; exit 1; }
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" --project "$PROJECT_DIR" --project-root "$ROOT_DIR" --quiet
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"
set +o pipefail
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=watchOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  -jobs "$JOBS" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  build 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | tail -20
STATUS=${PIPESTATUS[0]}
set -o pipefail
[[ "$STATUS" -eq 0 ]] || exit "$STATUS"
echo "app: $DERIVED_DATA/Build/Products/Debug-watchsimulator/$SCHEME.app"
