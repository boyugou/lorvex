#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

"$ROOT_DIR/script/verify_xcode_simulator.sh" \
  "$WATCH_APP_NAME" \
  "watchOS Simulator" \
  "Debug-watchsimulator" \
  "${LORVEX_WATCH_SIMULATOR_NAME:-Apple Watch Series 11 (46mm)}" \
  "$WATCH_BUNDLE_ID" \
  "$WATCH_APP_DISPLAY_NAME" \
  "$MIN_WATCH_SYSTEM_VERSION" \
  "$ROOT_DIR/Config/LorvexWatchApp.entitlements"
