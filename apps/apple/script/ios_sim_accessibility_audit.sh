#!/usr/bin/env bash
# Run XCTest's accessibility audit on the iOS app's screens, headlessly: boots
# the simulator without Simulator.app, resets the store to today's sample day,
# runs the AccessibilityAuditTests UI test, and collects its findings.
#
# The audit checks contrast, hit regions, missing descriptions, clipped text,
# text that ignores the text size setting, and traits. It reports and never
# fails on a finding: read each line beside the screenshot of its screen and
# decide whether it is real.
#
# Usage: script/ios_sim_accessibility_audit.sh <outdir> [light|dark] [screen ...]
#        Screens are the names in Tests/LorvexMobileUITests/AccessibilityAuditTests.swift
#        (today, tasks, calendar, …); all of them when none is given.
# Writes <outdir>/findings-<appearance>.txt (one line per finding, see the
#        test's header for the fields; findings the audit cannot tie to an
#        element read alike and appear once, and each screen's `done` line
#        carries its full count), <outdir>/<appearance>/<screen>.png, and
#        <outdir>/xcodebuild-<appearance>.log.
# Env:   LORVEX_SIM_DEVICE       simulator device name (default: iPhone 17 Pro)
#        LORVEX_SIM_UDID         exact device UDID, overriding the name lookup
#        LORVEX_XCODE_JOBS       xcodebuild -jobs (default: 4)
#        LORVEX_AUDIT_TEXT_SIZE  a UIContentSizeCategory name the app launches
#                                with, e.g. UICTContentSizeCategoryAccessibilityXL
set -euo pipefail
OUT="${1:?usage: ios_sim_accessibility_audit.sh <outdir> [light|dark] [screen ...]}"
APPEARANCE="${2:-light}"
shift $(( $# > 1 ? 2 : 1 ))
SCREENS="$(IFS=,; echo "$*")"
case "$APPEARANCE" in
  light|dark) ;;
  *) echo "appearance must be light or dark, not '$APPEARANCE'" >&2; exit 1 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE=com.lorvex.apple
DEVICE="${LORVEX_SIM_DEVICE:-iPhone 17 Pro}"
JOBS="${LORVEX_XCODE_JOBS:-4}"
PROJECT_DIR="$ROOT_DIR/dist/xcode-LorvexMobileApp"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-LorvexMobileApp"
mkdir -p "$OUT/$APPEARANCE"
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
xcrun simctl ui "$UDID" appearance "$APPEARANCE" >/dev/null 2>&1
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1
xcrun simctl ui "$UDID" increase_contrast disabled >/dev/null 2>&1

LOG="$OUT/xcodebuild-$APPEARANCE.log"
FINDINGS="$OUT/findings-$APPEARANCE.txt"
set +e
TEST_RUNNER_LORVEX_AUDIT_OUT="$OUT/$APPEARANCE" \
TEST_RUNNER_LORVEX_AUDIT_SCREENS="$SCREENS" \
TEST_RUNNER_LORVEX_AUDIT_TEXT_SIZE="${LORVEX_AUDIT_TEXT_SIZE:-}" \
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme LorvexMobileUITests \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -jobs "$JOBS" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  -only-testing:LorvexMobileUITests/AccessibilityAuditTests \
  test >"$LOG" 2>&1
STATUS=$?
set -e
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true

# xcodebuild prefixes the runner's output with a timestamp on some lines.
LC_ALL=C grep -ao 'AXAUDIT|.*' "$LOG" | sort -u >"$FINDINGS" || true
SCREENS_DONE="$(grep -c '|done|' "$FINDINGS" || true)"
ERRORS="$(grep -c '|error|' "$FINDINGS" || true)"
FOUND="$(grep -vc '|done|\||error|\||window|' "$FINDINGS" || true)"
echo "audited $SCREENS_DONE screens ($APPEARANCE): $FOUND findings, $ERRORS screens the audit could not run on → $FINDINGS"
if [[ "$STATUS" -ne 0 ]]; then
  echo "xcodebuild test exited $STATUS; see $LOG" >&2
  grep -E 'error:|\*\* TEST' "$LOG" | tail -10 >&2 || true
  exit "$STATUS"
fi
