#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

"$ROOT_DIR/script/verify_xcode_simulator.sh" \
  "$MOBILE_APP_NAME" \
  "iOS Simulator" \
  "Debug-iphonesimulator" \
  "${LORVEX_IOS_SIMULATOR_NAME:-iPhone 17 Pro}" \
  "$MOBILE_BUNDLE_ID" \
  "$MOBILE_APP_DISPLAY_NAME" \
  "$MIN_MOBILE_SYSTEM_VERSION" \
  "$ROOT_DIR/Config/LorvexMobileApp.entitlements"
