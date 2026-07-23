#!/usr/bin/env bash
# archive_ios.sh — Archive and (optionally) export an iOS, iPadOS, visionOS,
# or watchOS app from the XcodeGen-generated project.
#
# Without signing credentials the script falls back to a
# build-for-testing invocation that validates the full compile/link graph
# without touching the keychain.
#
# Usage:
#   ./script/archive_ios.sh [--scheme <scheme>] [--method <app-store-connect|development>]
#
# Modes (selected by the first positional argument or --mode flag):
#   --build-only   Compile only (default when APPLE_TEAM_ID is absent).
#   --archive      Archive only; skip -exportArchive.
#   --export       Archive + export IPA (default when APPLE_TEAM_ID is set).
#
# Required environment for --export:
#   APPLE_TEAM_ID   10-character Apple Developer Team ID
#
# Optional environment:
#   LORVEX_IOS_SCHEME     XcodeGen scheme to archive (default: LorvexMobileApp)
#   EXPORT_METHOD         app-store-connect | development (default: app-store-connect)
#   ARCHIVE_DIR           Directory for .xcarchive output  (default: dist/ios-archive)
#
# --archive and --export require the schema-freeze tripwire to be ARMED
# (see script/verify_schema_freeze.py; schema/migration_policy.json
# "launched": true) so a pre-freeze schema can never ship in an archived
# artifact. Lorvex is pre-launch today; for a local pre-launch build only,
# set LORVEX_ALLOW_UNFROZEN=1 to explicitly skip this gate. Real release
# archiving must not set that variable.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
source "$ROOT_DIR/script/require_schema_freeze_gate.sh"
source "$ROOT_DIR/script/lib_xcode_package_lock.sh"

# ---------------------------------------------------------------------------
# Defaults and CLI parsing
# ---------------------------------------------------------------------------
SCHEME="${LORVEX_IOS_SCHEME:-LorvexMobileApp}"
EXPORT_METHOD="${EXPORT_METHOD:-app-store-connect}"
ARCHIVE_DIR="${ARCHIVE_DIR:-"$ROOT_DIR/dist/ios-archive"}"
MODE=""

usage() {
  cat <<USAGE
usage: $0 [--scheme <scheme>] [--method <app-store-connect|development>]
          [--build-only|--archive|--export]

Modes:
  --build-only   swift build (no Xcode project needed) — always available
  --archive      xcodebuild archive (requires xcodegen + Xcode)
  --export       archive + exportArchive to IPA (requires APPLE_TEAM_ID)

Valid --scheme values (from Config/XcodeGen/project.yml):
  LorvexMobileApp  LorvexVisionApp  LorvexWatchApp

Environment for --export:
  APPLE_TEAM_ID      10-character Apple Developer Team ID
  EXPORT_METHOD      app-store-connect | development  (default: app-store-connect)
  ARCHIVE_DIR        output directory for .xcarchive   (default: dist/ios-archive)

Environment for --archive/--export (schema-freeze gate):
  LORVEX_ALLOW_UNFROZEN   Set to 1 to skip the schema-freeze-armed
                          requirement for a local pre-launch build. Real
                          release archiving must not set this.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme|-s)
      SCHEME="$2"; shift 2 ;;
    --method|-m)
      EXPORT_METHOD="$2"; shift 2 ;;
    --build-only|build-only)
      MODE="build-only"; shift ;;
    --archive|archive)
      MODE="archive"; shift ;;
    --export|export)
      MODE="export"; shift ;;
    --help|-h|help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Choose default mode based on credential availability
# ---------------------------------------------------------------------------
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

if [[ -z "$MODE" ]]; then
  if [[ -z "$APPLE_TEAM_ID" ]]; then
    echo "APPLE_TEAM_ID not set — falling back to --build-only (compile check without signing)" >&2
    MODE="build-only"
  else
    MODE="export"
  fi
fi

# ---------------------------------------------------------------------------
# Validate scheme
# ---------------------------------------------------------------------------
VALID_SCHEMES=(LorvexMobileApp LorvexVisionApp LorvexWatchApp)
SCHEME_VALID=0
for s in "${VALID_SCHEMES[@]}"; do
  [[ "$s" == "$SCHEME" ]] && SCHEME_VALID=1 && break
done
if [[ "$SCHEME_VALID" -eq 0 ]]; then
  echo "unknown scheme: $SCHEME (valid: ${VALID_SCHEMES[*]})" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Validate export method
# ---------------------------------------------------------------------------
if [[ "$EXPORT_METHOD" != "app-store-connect" && "$EXPORT_METHOD" != "development" ]]; then
  echo "unknown export method: $EXPORT_METHOD (valid: app-store-connect, development)" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Tool availability checks
# ---------------------------------------------------------------------------
require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required tool not found: $1" >&2
    exit 2
  fi
}

require_xcrun_tool() {
  if ! xcrun --find "$1" >/dev/null 2>&1; then
    echo "required Xcode tool not found: $1" >&2
    exit 2
  fi
}

# Apple requires App Store submissions to be built against the iOS 26 SDK
# (bundled with Xcode 26) since 2026-04-28; `xcodebuild` merely being present is
# not enough — an older Xcode links an SDK the App Store rejects at upload. The
# iphoneos SDK version stands in for the Xcode version, so one check covers the
# iOS / visionOS / watchOS schemes this script archives.
IOS_SDK_FLOOR_MAJOR=26
require_ios_sdk_floor() {
  local version major
  version="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || true)"
  major="${version%%.*}"
  if [[ -z "$major" || ! "$major" =~ ^[0-9]+$ ]]; then
    echo "could not determine the iOS SDK version (xcrun --sdk iphoneos --show-sdk-version)." >&2
    echo "install Xcode ${IOS_SDK_FLOOR_MAJOR}+ and select it with xcode-select." >&2
    exit 2
  fi
  if (( major < IOS_SDK_FLOOR_MAJOR )); then
    echo "iOS SDK $version is below the App Store floor (iOS ${IOS_SDK_FLOOR_MAJOR} SDK, required since 2026-04-28)." >&2
    echo "update Xcode to a version bundling the iOS ${IOS_SDK_FLOOR_MAJOR}+ SDK and select it with xcode-select." >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Mode: build-only — uses xcodebuild if xcodegen is present; otherwise
# reports clearly that a platform-targeted build requires Xcode.
# ---------------------------------------------------------------------------
if [[ "$MODE" == "build-only" ]]; then
  if command -v xcodegen >/dev/null 2>&1 && xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "==> build-only: xcodebuild (generic simulator destination, no signing)"

    PROJECT_DIR="$ROOT_DIR/dist/ios-xcode-project"
    PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"

    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
    xcodegen \
      --spec "$ROOT_DIR/Config/XcodeGen/project.yml" \
      --project "$PROJECT_DIR" \
      --project-root "$ROOT_DIR" \
      --quiet

    # Seed the committed resolver lock and pin resolution so this build reads
    # only the pinned versions and never rewrites the git-tracked
    # core/Package.resolved (see lib_xcode_package_lock.sh).
    seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"

    # Use the generic device destination (no running device required).
    # CODE_SIGNING_ALLOWED=NO lets xcodebuild compile/link without creds.
    DESTINATION=""
    case "$SCHEME" in
      LorvexMobileApp) DESTINATION="generic/platform=iOS" ;;
      LorvexVisionApp) DESTINATION="generic/platform=visionOS" ;;
      LorvexWatchApp)  DESTINATION="generic/platform=watchOS" ;;
    esac

    set +e
    BUILD_OUTPUT="$(xcrun xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "$DESTINATION" \
      "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" \
      CODE_SIGNING_ALLOWED=NO \
      build 2>&1)"
    BUILD_STATUS=$?
    set -e

    if [[ $BUILD_STATUS -ne 0 ]]; then
      # Check for missing platform SDK — not a script error but an environment gap.
      if echo "$BUILD_OUTPUT" | grep -q "is not installed. Please download and install the platform"; then
        echo "build-only: SDK platform not installed on this host." >&2
        echo "$BUILD_OUTPUT" | grep "is not installed" >&2
        echo "" >&2
        echo "Install the missing platform in Xcode > Settings > Components, then re-run." >&2
        echo "No signing credentials are needed; this is a compile-only check." >&2
        exit 1
      fi
      echo "$BUILD_OUTPUT" >&2
      exit $BUILD_STATUS
    fi

    echo "build-only passed: scheme=$SCHEME"
  else
    echo "build-only: xcodegen or xcodebuild not available on this host." >&2
    echo "SwiftPM cannot build iOS/watchOS/visionOS targets on macOS without Xcode." >&2
    echo "Install Xcode and xcodegen (brew install xcodegen) to enable build-only mode." >&2
    echo ""
    echo "To perform a full compile+link check without signing, set APPLE_TEAM_ID" >&2
    echo "and run: ./script/archive_ios.sh --scheme $SCHEME --archive" >&2
    exit 1
  fi

  echo ""
  echo "NOTE: To produce a signed IPA, set APPLE_TEAM_ID and re-run with --export."
  exit 0
fi

# ---------------------------------------------------------------------------
# Schema-freeze gate — only the archive/export modes actually produce a
# distributable artifact (build-only above compiles and exits, never
# reaching here), so this is where "MAS/iOS archiving doesn't ship a
# pre-freeze schema" is enforced. Skippable for a local pre-launch build only
# via LORVEX_ALLOW_UNFROZEN=1; real release packaging must not set it. See
# require_schema_freeze_gate.sh.
# ---------------------------------------------------------------------------
require_schema_freeze_armed "$ROOT_DIR"

# ---------------------------------------------------------------------------
# From here on we need xcodegen and xcodebuild
# ---------------------------------------------------------------------------
require_tool xcodegen
require_xcrun_tool xcodebuild
require_ios_sdk_floor

# ---------------------------------------------------------------------------
# Generate the Xcode project into a temporary directory
# ---------------------------------------------------------------------------
PROJECT_DIR="$ROOT_DIR/dist/ios-xcode-project"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"

cleanup() {
  rm -rf "$PROJECT_DIR"
}
trap cleanup EXIT

echo "==> Generating Xcode project via XcodeGen"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
xcodegen \
  --spec "$ROOT_DIR/Config/XcodeGen/project.yml" \
  --project "$PROJECT_DIR" \
  --project-root "$ROOT_DIR" \
  --quiet

# Seed the committed resolver lock and pin resolution so the archive step reads
# only the pinned versions and never rewrites the git-tracked
# core/Package.resolved (see lib_xcode_package_lock.sh).
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"

# ---------------------------------------------------------------------------
# Mode: archive (± export)
# ---------------------------------------------------------------------------
ARCHIVE_PATH="$ARCHIVE_DIR/$SCHEME.xcarchive"
mkdir -p "$ARCHIVE_DIR"

echo "==> Archiving scheme: $SCHEME"
ARCHIVE_DESTINATION=""
case "$SCHEME" in
  LorvexMobileApp) ARCHIVE_DESTINATION="generic/platform=iOS" ;;
  LorvexVisionApp) ARCHIVE_DESTINATION="generic/platform=visionOS" ;;
  LorvexWatchApp)  ARCHIVE_DESTINATION="generic/platform=watchOS" ;;
esac

XCODE_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration Release
  -destination "$ARCHIVE_DESTINATION"
  -archivePath "$ARCHIVE_PATH"
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}"
  CODE_SIGN_STYLE=Automatic
)

# Each target's App Store entitlements file is declared per-target, per
# Release-configuration in Config/XcodeGen/project.yml (search for
# `CODE_SIGN_ENTITLEMENTS`). Do NOT pass CODE_SIGN_ENTITLEMENTS here as a
# command-line build setting: xcodebuild command-line settings are
# project-wide, so a single override applies to every target in the
# archive — the iPhone app's CloudKit/APNs entitlements would leak onto
# frameworks, the widget extension, the watch app, and the watch
# complication instead of each target resolving its own file.

# App Store Connect API-key authentication for automatic provisioning. When
# ASC_KEY_ID / ASC_ISSUER_ID are set (and the AuthKey_<id>.p8 lives in the
# standard ~/.appstoreconnect/private_keys/ or ~/private_keys/ location, or
# ASC_KEY_PATH points at it), xcodebuild fetches/creates profiles headlessly
# without a signed-in Xcode account. Falls back to the Xcode account when
# unset.
AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  AUTH_ARGS+=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    AUTH_ARGS+=(-authenticationKeyPath "$ASC_KEY_PATH")
  fi
fi

if [[ -n "$APPLE_TEAM_ID" ]]; then
  # -allowProvisioningUpdates must be present at the ARCHIVE step, not just at
  # export: a clean machine has no profiles yet, and automatic signing can only
  # fetch them from the portal when the flag is passed to the invocation that
  # actually signs.
  XCODE_ARGS+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID" -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"})
fi

xcrun xcodebuild "${XCODE_ARGS[@]}" archive

test -d "$ARCHIVE_PATH"
echo "Archive produced: $ARCHIVE_PATH"

# The archive can succeed while the product is dyld-broken; prove the dynamic
# closure of the archived .app (and its nested extensions / watch payload)
# before treating the archive as distributable. Signature/profile audits need
# credentials and stay owner-side; this is the structural half.
ARCHIVED_APP="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$ARCHIVED_APP" ]]; then
  echo "archive contains no .app under Products/Applications" >&2
  exit 1
fi
"$ROOT_DIR/script/verify_macho_closure.py" "$ARCHIVED_APP"

if [[ "$MODE" == "archive" ]]; then
  echo "archive passed (no export requested)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode: export — requires APPLE_TEAM_ID
# ---------------------------------------------------------------------------
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for --export}"

# Guard: the watch app ships INSIDE the iPhone host's IPA — a standalone
# watchOS export cannot be submitted to the App Store. Refuse the combination
# outright; development-method exports of the watch scheme remain available
# for local install testing.
if [[ "$SCHEME" == "LorvexWatchApp" && "$EXPORT_METHOD" == "app-store-connect" ]]; then
  echo "ERROR: LorvexWatchApp has no standalone App Store export." >&2
  echo "The watch app ships embedded in the iPhone IPA — export LorvexMobileApp instead:" >&2
  echo "  ./script/archive_ios.sh --scheme LorvexMobileApp --export" >&2
  echo "See docs/DISTRIBUTION.md §5 for details." >&2
  exit 1
fi

# Select and patch the ExportOptions plist
case "$SCHEME" in
  LorvexMobileApp)
    case "$EXPORT_METHOD" in
      app-store-connect) EXPORT_OPTS_TEMPLATE="$ROOT_DIR/Config/ExportOptions/AppStore.plist" ;;
      development)       EXPORT_OPTS_TEMPLATE="$ROOT_DIR/Config/ExportOptions/Development.plist" ;;
    esac
    ;;
  LorvexVisionApp)
    EXPORT_OPTS_TEMPLATE="$ROOT_DIR/Config/ExportOptions/VisionOS.plist"
    ;;
  LorvexWatchApp)
    EXPORT_OPTS_TEMPLATE="$ROOT_DIR/Config/ExportOptions/WatchOS.plist"
    ;;
esac

test -f "$EXPORT_OPTS_TEMPLATE"
EXPORT_OPTS_WORK="$ARCHIVE_DIR/ExportOptions-work.plist"
sed "s/TEAM_ID_PLACEHOLDER/$APPLE_TEAM_ID/g" "$EXPORT_OPTS_TEMPLATE" > "$EXPORT_OPTS_WORK"

EXPORT_DIR="$ARCHIVE_DIR/$SCHEME-export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "==> Exporting IPA (method: $EXPORT_METHOD, team: $APPLE_TEAM_ID)"
xcrun xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS_WORK" \
  -allowProvisioningUpdates ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

# Confirm IPA was produced
IPA_PATH="$(find "$EXPORT_DIR" -name "*.ipa" | head -n 1)"
if [[ -z "$IPA_PATH" ]]; then
  echo "export completed but no .ipa found under $EXPORT_DIR" >&2
  exit 1
fi

# The exported, re-signed IPA is the artifact that actually ships; audit its
# payload (host app + PlugIns/*.appex widget + Watch/*.app + complication)
# before treating it as distributable. Two orthogonal checks run over the same
# unzipped payload:
#   1. verify_macho_closure.py — the *dynamic* closure (no dangling @rpath load
#      in any nested executable). The archive closure check above validated the
#      pre-export layout; this validates the re-signed .app unzipped from the IPA.
#   2. verify_ios_ipa.py — the *distribution* integrity closure cannot see: each
#      nested bundle's code signature, signed entitlements, embedded
#      .mobileprovision (and its app-id/team relationship to the bundle),
#      PrivacyInfo.xcprivacy presence, and CFBundleShortVersionString /
#      CFBundleVersion against the release metadata. The iPhone shape includes
#      both the Widget and the separately-profiled Focus Filter extension. It
#      runs here because only an
#      --export run produces a real signed artifact; exit 78 (codesign absent) is
#      a soft-skip.
IPA_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorvex-ipa-verify.XXXXXX")"
unzip -q "$IPA_PATH" -d "$IPA_VERIFY_DIR"
IPA_APP="$(find "$IPA_VERIFY_DIR/Payload" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$IPA_APP" ]]; then
  echo "IPA contains no .app under Payload/" >&2
  rm -rf "$IPA_VERIFY_DIR"
  exit 1
fi
# Tell the recursive verifier which platform's bundle set to expect. Each
# scheme ships a different payload shape (iPhone embeds a widget + Watch app +
# complication; visionOS is the host app alone; a standalone watch export is the
# Watch app + complication), so passing the platform keeps this producing script
# and the verifier in agreement instead of asserting an iPhone shape on every
# export.
case "$SCHEME" in
  LorvexMobileApp) IPA_PLATFORM="ios" ;;
  LorvexVisionApp) IPA_PLATFORM="visionos" ;;
  LorvexWatchApp)  IPA_PLATFORM="watchos" ;;
esac
set +e
"$ROOT_DIR/script/verify_macho_closure.py" "$IPA_APP"
IPA_CLOSURE_STATUS=$?
"$ROOT_DIR/script/verify_ios_ipa.py" \
  --platform "$IPA_PLATFORM" \
  --distribution-method "$EXPORT_METHOD" \
  "$IPA_APP"
IPA_RECURSIVE_STATUS=$?
set -e
rm -rf "$IPA_VERIFY_DIR"
if [[ "$IPA_CLOSURE_STATUS" -ne 0 ]]; then
  echo "IPA payload failed Mach-O closure verification: $IPA_PATH" >&2
  exit 1
fi
# 78 = codesign unavailable on this host (soft-skip); any other non-zero is a
# real distribution-integrity failure.
if [[ "$IPA_RECURSIVE_STATUS" -ne 0 && "$IPA_RECURSIVE_STATUS" -ne 78 ]]; then
  echo "IPA payload failed recursive distribution verification: $IPA_PATH" >&2
  exit 1
fi

echo "IPA produced: $IPA_PATH"
echo ""
echo "Next steps:"
echo "  App Store Connect upload:"
echo "    xcrun altool --upload-app \\"
echo "      -f '$IPA_PATH' \\"
echo "      --type ios \\"
echo "      --apple-id APPLE_ID --password APP_SPECIFIC_PASSWORD"
echo "  or use Transporter.app / Xcode Organizer."
