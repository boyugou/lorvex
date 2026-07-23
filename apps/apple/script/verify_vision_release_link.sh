#!/usr/bin/env bash
# verify_vision_release_link.sh — thin wrapper around verify_release_link.sh
# for the visionOS scheme. See that script's header for why this Release
# device-graph build (rather than Debug/simulator) is a distinct gate; on
# visionOS specifically, this is also the gate that catches API calls gated
# behind a visionOS version newer than this app's deployment floor (e.g.
# SwiftUI's `.sensoryFeedback`, which requires visionOS 26.0).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

exec "$ROOT_DIR/script/verify_release_link.sh" "$VISION_APP_NAME" visionOS "visionOS Release link"
