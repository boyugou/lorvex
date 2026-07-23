#!/usr/bin/env bash
# verify_mobile_release_link.sh — thin wrapper around verify_release_link.sh
# for the iPhone/iPad scheme. See that script's header for why this Release
# device-graph build (rather than Debug/simulator) is a distinct gate, and why
# the built artifact's dyld closure is verified after a successful link.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

exec "$ROOT_DIR/script/verify_release_link.sh" "$MOBILE_APP_NAME" iOS "iOS Release link"
