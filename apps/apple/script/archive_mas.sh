#!/usr/bin/env bash
# archive_mas.sh - Build and package the macOS Mac App Store artifact.
#
# Usage:
#   ./script/archive_mas.sh --preflight
#   MAS_APP_SIGN_IDENTITY="Apple Distribution: Team Name (TEAMID)" \
#   MAS_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Team Name (TEAMID)" \
#     ./script/archive_mas.sh --package
#   APPLE_ID="APPLE_ACCOUNT_ID" APPLE_APP_PASSWORD="app-specific-password" \
#     ./script/archive_mas.sh --validate
#   APPLE_ID="APPLE_ACCOUNT_ID" APPLE_APP_PASSWORD="app-specific-password" \
#     ./script/archive_mas.sh --upload
#
# Distribution provisioning profiles for --package (paths to
# .provisionprofile files downloaded from the Apple Developer portal; when
# unset, sign_app_bundle.sh falls back to the secrets/profiles/ convention —
# see .gitignore):
#   MAS_APP_PROVISIONING_PROFILE          macOS app (Contents/embedded.provisionprofile) — required
#   MAS_MCP_HOST_PROVISIONING_PROFILE     MCP helper .app bundle — required
#   MAS_WIDGET_PROVISIONING_PROFILE       Focus widget .appex — required
# The app, MCP helper, and Focus-widget profiles are all mandatory for
# --package: a MAS package is never distributable without them, so --package
# hard-fails immediately after packaging if any is missing (development
# staging via package_local.sh/archive_local.sh keeps sign_app_bundle.sh's
# soft-skip; package_dmg.sh layers a separate mandatory Developer ID profile
# gate). After --package, verify_mas_provisioning.py cross-checks any
# embedded profile against the signed entitlements (App Group, iCloud
# container, com.apple.developer.aps-environment, bundle id) and hard-fails on
# mismatch.
#
# Schema-freeze gate: every subcommand above routes through preflight(),
# which requires verify_schema_freeze.py to report the schema-freeze tripwire
# ARMED (schema/migration_policy.json "launched": true) before a MAS artifact
# can be produced, validated, or uploaded. Lorvex is pre-launch today, so this
# is skippable for a local pre-launch build only via LORVEX_ALLOW_UNFROZEN=1;
# real release packaging must not set that variable. See
# require_schema_freeze_gate.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
source "$ROOT_DIR/script/require_schema_freeze_gate.sh"

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
PKG_PATH="${MAS_PKG_PATH:-"$ROOT_DIR/dist/$APP_NAME-macOS-MAS-$MARKETING_VERSION+$BUILD_VERSION.pkg"}"
MAS_ENTITLEMENTS_PATH="$ROOT_DIR/Config/LorvexAppleCloudKitAppStore.entitlements"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 2
  fi
}

require_tool() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required tool: $name" >&2
    exit 2
  fi
}

preflight() {
  # Gate first: every archive_mas.sh entry point (--preflight, --package,
  # --validate, --upload) routes through preflight(), so a pre-freeze schema
  # can never reach a MAS artifact regardless of which subcommand is used.
  # See require_schema_freeze_gate.sh for the LORVEX_ALLOW_UNFROZEN=1
  # pre-launch escape hatch.
  require_schema_freeze_armed "$ROOT_DIR"
  require_tool productbuild
  require_tool xcrun
  require_tool codesign
  "$ROOT_DIR/script/verify_mas_release_readiness.py"
  echo "MAS archive preflight passed"
}

package_mas() {
  # A MAS package must ship Release binaries. package_local.sh defaults the
  # staging configuration to release but honors a caller's environment value —
  # refuse an explicit debug override outright rather than silently shipping
  # -Onone binaries in a submission package.
  if [[ "${LORVEX_BUILD_CONFIGURATION:-release}" != "release" ]]; then
    echo "ERROR: --package requires LORVEX_BUILD_CONFIGURATION=release" \
      "(got '${LORVEX_BUILD_CONFIGURATION}'). Unset it or set it to release." >&2
    exit 2
  fi
  preflight
  require_env MAS_APP_SIGN_IDENTITY
  require_env MAS_INSTALLER_SIGN_IDENTITY

  # App Store codesigning needs the application-identifier and
  # team-identifier entitlements per component. Xcode injects these from the
  # provisioning profile automatically; a manual codesign does not, and App
  # Store Connect rejects a build whose signed entitlements omit them
  # (TestFlight warning 90886). Derive the team id from the signing identity
  # ("Apple Distribution: Name (TEAMID)") and synthesize per-component
  # entitlements = base file + application-identifier + team-identifier.
  local team_id
  team_id="$(sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\)).*/\1/p' <<<"$MAS_APP_SIGN_IDENTITY")"
  if [[ -z "$team_id" ]]; then
    echo "ERROR: could not derive team id from MAS_APP_SIGN_IDENTITY" >&2
    exit 2
  fi
  local ent_dir
  ent_dir="$(mktemp -d)"
  trap 'rm -rf "$ent_dir"' RETURN
  synth_entitlements() {  # base_plist  bundle_id  out_plist
    /bin/cp "$1" "$3"
    /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$3" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$3" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $team_id.$2" "$3"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $team_id" "$3"
  }
  synth_entitlements "$MAS_ENTITLEMENTS_PATH" "$BUNDLE_ID" "$ent_dir/app.entitlements"
  synth_entitlements "$ROOT_DIR/Config/LorvexMCPHost.entitlements" "$MCP_HOST_BUNDLE_ID" "$ent_dir/helper.entitlements"
  synth_entitlements "$ROOT_DIR/Config/LorvexWidgetExtension.entitlements" "$WIDGET_BUNDLE_ID" "$ent_dir/widget.entitlements"

  (
    cd "$ROOT_DIR"
    export CODE_SIGN_IDENTITY="$MAS_APP_SIGN_IDENTITY"
    # The App Store-signed sandboxed helper cannot open its App Group from a
    # bare in-tree launch (see package_local.sh); the App Store install
    # validates the MCP host in the environment where App Groups resolve.
    export LORVEX_MAS_SKIP_LOCAL_MCP_SMOKE=1
    export ENTITLEMENTS_PATH="$ent_dir/app.entitlements"
    export HELPER_ENTITLEMENTS_PATH="$ent_dir/helper.entitlements"
    export WIDGET_ENTITLEMENTS_PATH="$ent_dir/widget.entitlements"
    # Only override sign_app_bundle.sh's provisioning-profile variables when
    # the caller actually supplied one; leaving them unset lets it fall back
    # to its own secrets/profiles/ default-path convention.
    if [[ -n "${MAS_APP_PROVISIONING_PROFILE:-}" ]]; then
      export APP_PROVISIONING_PROFILE="$MAS_APP_PROVISIONING_PROFILE"
    fi
    if [[ -n "${MAS_MCP_HOST_PROVISIONING_PROFILE:-}" ]]; then
      export HELPER_PROVISIONING_PROFILE="$MAS_MCP_HOST_PROVISIONING_PROFILE"
    fi
    if [[ -n "${MAS_WIDGET_PROVISIONING_PROFILE:-}" ]]; then
      export WIDGET_PROVISIONING_PROFILE="$MAS_WIDGET_PROVISIONING_PROFILE"
    fi
    ./script/package_local.sh
  )

  # sign_app_bundle.sh's profile embedding is a soft-skip by design (the
  # normal state for a dev/Developer-ID build without portal credentials —
  # see its own comments and verify_mas_provisioning.py's NOTE-and-skip
  # behavior). A MAS package is different: App Store Connect rejects an
  # upload with no distribution provisioning profile, so shipping a .pkg
  # that "succeeded" without one is a false-positive gate. Enforce it here,
  # after packaging has had its chance to embed the profiles and before the
  # productbuild/pkgutil steps below produce an artifact that looks
  # complete but is not distributable.
  local app_profile="$APP_BUNDLE/Contents/embedded.provisionprofile"
  local helper_profile="$APP_BUNDLE/Contents/Helpers/$MCP_HOST_PRODUCT.app/Contents/embedded.provisionprofile"
  local widget_profile="$APP_BUNDLE/Contents/PlugIns/$WIDGET_APPEX_NAME/Contents/embedded.provisionprofile"
  if [[ ! -f "$app_profile" ]]; then
    echo "MAS package is missing the required app distribution provisioning profile: $app_profile" >&2
    echo "set MAS_APP_PROVISIONING_PROFILE or place it at secrets/profiles/$APP_PRODUCT_NAME.provisionprofile" >&2
    exit 1
  fi
  if [[ ! -f "$helper_profile" ]]; then
    echo "MAS package is missing the required MCP helper distribution provisioning profile: $helper_profile" >&2
    echo "set MAS_MCP_HOST_PROVISIONING_PROFILE or place it at secrets/profiles/$MCP_HOST_PRODUCT.provisionprofile" >&2
    exit 1
  fi
  if [[ ! -f "$widget_profile" ]]; then
    echo "MAS package is missing the required Focus-widget distribution provisioning profile: $widget_profile" >&2
    echo "set MAS_WIDGET_PROVISIONING_PROFILE or place it at secrets/profiles/$WIDGET_EXECUTABLE.provisionprofile" >&2
    exit 1
  fi

  "$ROOT_DIR/script/verify_codesign_entitlements.py" \
    --require-cloudkit \
    --require-production-aps \
    "$APP_BUNDLE"
  "$ROOT_DIR/script/verify_mas_provisioning.py" "$APP_BUNDLE"

  rm -f "$PKG_PATH"
  productbuild \
    --component "$APP_BUNDLE" /Applications \
    --sign "$MAS_INSTALLER_SIGN_IDENTITY" \
    "$PKG_PATH"
  pkgutil --check-signature "$PKG_PATH" >/dev/null
  echo "MAS package written: $PKG_PATH"
}

validate_or_upload() {
  local mode="$1"
  preflight
  if [[ ! -f "$PKG_PATH" ]]; then
    echo "MAS package not found: $PKG_PATH" >&2
    echo "run ./script/archive_mas.sh --package first, or set MAS_PKG_PATH" >&2
    exit 2
  fi
  require_env APPLE_ID
  require_env APPLE_APP_PASSWORD

  local action=(--validate-app)
  if [[ "$mode" == "upload" ]]; then
    action=(--upload-app)
  fi

  # Pass the app-specific password by env-var reference (`@env:`) rather than
  # its literal value, so it never appears in this process's argv (visible to
  # any `ps` on the host). altool reads APPLE_APP_PASSWORD from the environment,
  # which `require_env` above already guarantees is set.
  xcrun altool "${action[@]}" \
    -f "$PKG_PATH" \
    --type osx \
    --apple-id "$APPLE_ID" \
    --password "@env:APPLE_APP_PASSWORD"
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  --help|-h|help)
    usage
    ;;
  --preflight)
    preflight
    ;;
  --package)
    package_mas
    ;;
  --validate)
    validate_or_upload validate
    ;;
  --upload)
    validate_or_upload upload
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac
