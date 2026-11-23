#!/usr/bin/env bash
# Measure the iOS app's launch and scrolling in the simulator, headlessly:
# boots the simulator without Simulator.app, resets the store so the app seeds
# the sample day with the stress content, runs the ResponsivenessTests UI
# tests, and collects XCTest's measurements.
#
# Usage: script/ios_sim_responsiveness.sh [--optimized] <outdir> [test ...]
#        Tests are the method names in
#        Tests/LorvexMobileUITests/ResponsivenessTests.swift (testLaunch,
#        testScrollToday, …); all of them when none is given.
#        --optimized builds the app with the Swift optimizer on (-O), as a
#        release build is, into its own derived data folder. Without it the
#        app is a debug build, whose SwiftUI views run several times slower.
# Writes <outdir>/measurements.txt (XCTest's metrics, one line each:
#        `<test>|<metric>|<unit>|<average>|<values>`), <outdir>/frames.txt
#        (the app's frame probe, one line per test:
#        `FRAMEPROBE|<test>|seconds=…|frames=…|hitches=…|hitch_ms=…|worst_ms=…|busy_ms=…|long_busy=…|long_busy_over_ms=…|worst_busy_ms=…|hz=…|done=<0|1>`,
#        counted while the app drives the test's interaction itself: late
#        frames, then main-thread work, as DebugFrameProbe describes; done=0
#        means the test ended the app first), and <outdir>/xcodebuild.log.
# Env:   LORVEX_SIM_DEVICE  simulator device name (default: iPhone 17 Pro)
#        LORVEX_SIM_UDID    exact device UDID, overriding the name lookup
#        LORVEX_XCODE_JOBS  xcodebuild -jobs (default: 4)
set -euo pipefail
OPTIMIZED=0
if [[ "${1:-}" == "--optimized" ]]; then
  OPTIMIZED=1
  shift
fi
OUT="${1:?usage: ios_sim_responsiveness.sh [--optimized] <outdir> [test ...]}"
shift
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE=com.lorvex.apple
DEVICE="${LORVEX_SIM_DEVICE:-iPhone 17 Pro}"
JOBS="${LORVEX_XCODE_JOBS:-4}"
PROJECT_DIR="$ROOT_DIR/dist/xcode-LorvexMobileApp"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-LorvexMobileApp"
EXTRA_SETTINGS=()
if [[ "$OPTIMIZED" -eq 1 ]]; then
  DERIVED_DATA="$ROOT_DIR/dist/DerivedData-LorvexMobileApp-optimized"
  EXTRA_SETTINGS=(SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s)
fi
ONLY=()
for test in "$@"; do
  ONLY+=("-only-testing:LorvexMobileUITests/ResponsivenessTests/$test")
done
[[ ${#ONLY[@]} -eq 0 ]] && ONLY=("-only-testing:LorvexMobileUITests/ResponsivenessTests")
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$ROOT_DIR"
source script/lib_xcode_package_lock.sh
source script/lib_ios_sim_device.sh
UDID="$(resolve_ios_sim_udid "$DEVICE")" || { echo "no available simulator named '$DEVICE'" >&2; exit 1; }
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" --project "$PROJECT_DIR" --project-root "$ROOT_DIR" --quiet
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || sleep 8
clear_ios_sim_seeded_store "$UDID" "$BUNDLE"
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1

# The frame probe writes into the app's temporary folder, which survives a
# reinstall; clear the files an earlier run left.
probe_dir() {
  local data
  data="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
  case "$data" in
    */CoreSimulator/Devices/"$UDID"/*) echo "$data/tmp" ;;
  esac
}
PROBE_DIR="$(probe_dir)"
[[ -n "$PROBE_DIR" ]] && rm -f "${PROBE_DIR:?}"/lorvex-frame-probe-*.txt

LOG="$OUT/xcodebuild.log"
MEASUREMENTS="$OUT/measurements.txt"
set +e
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme LorvexMobileUITests \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$JOBS" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  "${ONLY[@]}" \
  ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} \
  test >"$LOG" 2>&1
STATUS=$?
set -e
FRAMES="$OUT/frames.txt"
PROBE_DIR="$(probe_dir)"
if [[ -n "$PROBE_DIR" ]]; then
  cat "$PROBE_DIR"/lorvex-frame-probe-*.txt 2>/dev/null | sort >"$FRAMES" || true
else
  : >"$FRAMES"
fi
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true

# XCTest prints: Test Case '-[LorvexMobileUITests.ResponsivenessTests testX]'
# measured [Metric Name, unit] average: 1.234, relative standard deviation:
# 5.6%, values: [1.1, 1.2, ...], performanceMetricID: ...
LC_ALL=C grep -a "measured \[" "$LOG" | sed -E \
  "s/.*ResponsivenessTests (test[A-Za-z]+)\]' measured \[([^,]+), ([^]]+)\] average: ([0-9.]+),.*values: \[([^]]*)\].*/\1|\2|\3|\4|\5/" \
  | sort -u >"$MEASUREMENTS" || true
echo "$(wc -l <"$MEASUREMENTS" | tr -d ' ') XCTest measurements → $MEASUREMENTS"
echo "$(wc -l <"$FRAMES" | tr -d ' ') frame probe results → $FRAMES"
if [[ "$STATUS" -ne 0 ]]; then
  echo "xcodebuild test exited $STATUS; see $LOG" >&2
  grep -E 'error:|\*\* TEST|failed' "$LOG" | tail -10 >&2 || true
  exit "$STATUS"
fi
