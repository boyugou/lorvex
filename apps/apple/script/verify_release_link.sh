#!/usr/bin/env bash
# verify_release_link.sh — Build an app scheme's *Release* device graph
# (unsigned) for a given generic platform destination, to catch Release-only
# compile/link failures that neither `swift build` nor a Debug simulator check
# can see.
#
# Why a separate Release gate: optimized builds resolve opaque result types
# across framework boundaries (see e.g. SwiftUI's `WidgetBundleBuilder`, whose
# `@_alwaysEmitIntoClient` opaque-type instantiation only fails to link in the
# Xcode Release device graph). Release also enforces the app's real
# deployment-target floor per platform, which is how e.g. a visionOS-2.0-floor
# build catches a `visionOS 26.0`-gated API call that Debug/simulator builds
# and SwiftPM's single-unit link never surface.
#
# Usage: verify_release_link.sh <scheme> <generic-platform> <label>
#   e.g.  verify_release_link.sh LorvexMobileApp iOS      "iOS Release link"
#         verify_release_link.sh LorvexVisionApp visionOS "visionOS Release link"
#
# A successful link is not a launchable artifact: Xcode builds SwiftPM
# library products as dynamic `…PackageProduct` frameworks when two targets
# in one process link the same product, and those must be embedded into each
# host app's Frameworks/ directory or the app dies at launch with dyld
# "Library not loaded". After the build, script/verify_macho_closure.py
# therefore walks every executable in the built .app (app, extensions, any
# nested watch app) and proves each non-system load command resolves inside
# the bundle with the run paths the executables actually carry. It also checks
# that the embedded LorvexCore.framework's bundled Migrations/ directory
# survived as a real subdirectory rather than being flattened by XcodeGen's
# default resource handling.
#
# Exit codes: 0 = pass; 78 = environment unavailable (no xcodegen /
# xcodebuild / platform SDK), matching the simulator verifiers' soft-skip
# convention; anything else = build, link, or closure failure.

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "usage: $0 <scheme> <generic-platform> <label>" >&2
  exit 2
fi

SCHEME="$1"
GENERIC_PLATFORM="$2"
LABEL="$3"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/dist/xcode-release-link-$SCHEME"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData-release-link-$SCHEME"

source "$ROOT_DIR/script/lib_xcode_package_lock.sh"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "verify_release_link ($LABEL): xcodegen not available on this host." >&2
  exit 78
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "verify_release_link ($LABEL): xcodebuild not available on this host." >&2
  exit 78
fi

rm -rf "$PROJECT_DIR" "$DERIVED_DATA"
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" \
  --project "$PROJECT_DIR" \
  --project-root "$ROOT_DIR" \
  --quiet

# Seed the committed resolver lock and pin resolution so this build reads only
# the pinned versions and never rewrites the git-tracked core/Package.resolved
# (see lib_xcode_package_lock.sh).
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"

set +e
BUILD_OUTPUT="$(xcrun xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=$GENERIC_PLATFORM" \
  -derivedDataPath "$DERIVED_DATA" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1)"
BUILD_STATUS=$?
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  if grep -q "is not installed. Please download and install the platform" <<<"$BUILD_OUTPUT"; then
    echo "verify_release_link ($LABEL): $GENERIC_PLATFORM platform SDK not installed on this host." >&2
    grep "is not installed" <<<"$BUILD_OUTPUT" >&2
    exit 78
  fi
  # Surface the error context (linker errors sit far from the final summary
  # in parallel xcodebuild output), then the closing failure summary.
  grep -B 2 -A 12 -E "Undefined symbols|error:" <<<"$BUILD_OUTPUT" >&2 || true
  tail -n 25 <<<"$BUILD_OUTPUT" >&2
  echo "verify_release_link ($LABEL): FAILED (xcodebuild status $BUILD_STATUS)" >&2
  exit "$BUILD_STATUS"
fi

# The link can succeed while the artifact is dyld-broken; prove the dynamic
# closure of the built app (and its nested extensions / watch app) before
# declaring the gate green. On failure the build products are kept for
# inspection. Products land in Release-<platform-dir> (iphoneos, xros, ...).
case "$GENERIC_PLATFORM" in
  iOS)      PRODUCTS_DIR="Release-iphoneos" ;;
  visionOS) PRODUCTS_DIR="Release-xros" ;;
  macOS)    PRODUCTS_DIR="Release" ;;
  watchOS)  PRODUCTS_DIR="Release-watchos" ;;
  *)        PRODUCTS_DIR="Release-$GENERIC_PLATFORM" ;;
esac
APP_BUNDLE="$DERIVED_DATA/Build/Products/$PRODUCTS_DIR/$SCHEME.app"
"$ROOT_DIR/script/verify_macho_closure.py" "$APP_BUNDLE"

# Every scheme embeds the LorvexCore-family framework (PRODUCT_NAME LorvexCore
# in every one of LorvexCore/LorvexCoreVision/LorvexCoreWatch) at
# Frameworks/LorvexCore.framework, and SwiftLorvexCoreService+Migrations.swift
# resolves the bundled migration ladder by looking for a real `Migrations`
# subdirectory at that framework's resource root. XcodeGen's `folder`-type
# source preserves that directory (see project.yml's LorvexCore/
# LorvexCoreVision/LorvexCoreWatch targets); a `group`-type source would
# flatten it into loose files instead, silently breaking the loader at the
# first real migration. Assert the layout the loader expects survived this
# build.
CORE_FRAMEWORK="$APP_BUNDLE/Frameworks/LorvexCore.framework"
if [[ ! -d "$CORE_FRAMEWORK" ]]; then
  echo "verify_release_link ($LABEL): no embedded LorvexCore.framework at $CORE_FRAMEWORK" >&2
  exit 1
fi
if [[ ! -d "$CORE_FRAMEWORK/Migrations" ]]; then
  echo "verify_release_link ($LABEL): $CORE_FRAMEWORK is missing a Migrations/ resource" \
    "directory — XcodeGen flattened the migration ladder into loose files" \
    "(see the LorvexCore target's folder-type source in project.yml)" >&2
  exit 1
fi

rm -rf "$PROJECT_DIR" "$DERIVED_DATA"
echo "verify_release_link passed: $LABEL (scheme=$SCHEME, Release, unsigned, generic/platform=$GENERIC_PLATFORM, dyld closure + Migrations layout verified)"
