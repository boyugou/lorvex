#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

"$ROOT_DIR/script/verify_xcode_simulator.sh" \
  "$VISION_APP_NAME" \
  "visionOS Simulator" \
  "Debug-xrsimulator" \
  "${LORVEX_VISION_SIMULATOR_NAME:-Apple Vision Pro}" \
  "$VISION_BUNDLE_ID" \
  "$VISION_APP_DISPLAY_NAME" \
  "$MIN_VISION_SYSTEM_VERSION" \
  "$ROOT_DIR/Config/LorvexVisionApp.entitlements"
