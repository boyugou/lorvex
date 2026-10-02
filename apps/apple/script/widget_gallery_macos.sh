#!/bin/bash
# Renders the widget gallery at the Mac desktop's widget sizes, light and dark,
# into <outdir>: today, large, and habits-progress, each as <section>-light.png
# and <section>-dark.png. The views draw in a borderless window far off screen
# (WidgetGalleryMacRenderTests); nothing is shown and no app is activated.
#
# Usage: script/widget_gallery_macos.sh <outdir>
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:?usage: script/widget_gallery_macos.sh <outdir>}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

swift build -j 4 --build-tests
LORVEX_WIDGET_GALLERY_DIR="$out" swift test --skip-build --filter WidgetGalleryMacRenderTests
echo "rendered → $out"
/bin/ls "$out"
