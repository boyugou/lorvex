#!/usr/bin/env bash
#
# Regenerate the Apple-native app icon (`Resources/AppIcon/LorvexAppIcon.icns`)
# from the brand master PNG (`Resources/AppIcon/master_1024.png`).
#
# The master is the SHARED Lorvex brand mark — the same artwork the Tauri app
# bundles (`apps/tauri/app/src-tauri/icons/icon-1024.png`). Both apps render one
# identical icon. To refresh the brand: update the master here AND the Tauri
# source together, then re-run this script. (The apps stay independent — each
# keeps its own copy of the asset; this script only rebuilds the `.icns` from
# the local master.)
#
# Usage: script/generate_app_icon.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT_DIR/Resources/AppIcon/master_1024.png"
ICNS_OUT="$ROOT_DIR/Resources/AppIcon/LorvexAppIcon.icns"

test -f "$MASTER" || { echo "ERROR: missing master at $MASTER" >&2; exit 1; }

dims="$(sips -g pixelWidth -g pixelHeight "$MASTER" | awk '/pixel/{print $2}' | paste -sd x -)"
if [ "$dims" != "1024x1024" ]; then
  echo "ERROR: master must be 1024x1024 (got $dims)" >&2
  exit 1
fi

ICONSET="$(mktemp -d)/Lorvex.iconset"
mkdir -p "$ICONSET"

# Standard macOS iconset sizes (pt@scale).
gen() { sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1.png" >/dev/null; }
gen icon_16x16        16
gen icon_16x16@2x     32
gen icon_32x32        32
gen icon_32x32@2x     64
gen icon_128x128      128
gen icon_128x128@2x   256
gen icon_256x256      256
gen icon_256x256@2x   512
gen icon_512x512      512
gen icon_512x512@2x   1024

iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
rm -rf "$(dirname "$ICONSET")"

echo "Wrote $ICNS_OUT"
ls -lh "$ICNS_OUT"
