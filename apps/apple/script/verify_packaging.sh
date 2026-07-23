#!/usr/bin/env bash
# verify_packaging.sh — Sanity-check ExportOptions plists and archive_ios.sh
# without requiring signing credentials or a connected device.
#
# Verifications performed:
#   1. ExportOptions plists are well-formed XML (plutil -lint).
#   2. Required keys are present in each plist.
#   3. TEAM_ID_PLACEHOLDER is present (not yet substituted — correct for a
#      checked-in template).
#   4. archive_ios.sh has valid bash syntax (bash -n).
#   5. archive_mas.sh has valid bash syntax and the MAS readiness gate passes.
#   6. Scheme names in archive_ios.sh match those declared in project.yml.
#   7. ExportOptions method values are consistent with app_metadata.sh
#      bundle IDs (cross-check that Mobile bundle ID appears somewhere in
#      project.yml under the LorvexMobileApp target).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

FAILURES=()

fail() {
  FAILURES+=("$1")
}

check_plist_key() {
  local plist="$1" key="$2"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    fail "$plist is missing required key: $key"
  fi
}

# ---------------------------------------------------------------------------
# 1. ExportOptions plist lint and required-key checks
# ---------------------------------------------------------------------------
EXPORT_OPTS_DIR="$ROOT_DIR/Config/ExportOptions"
REQUIRED_EXPORT_KEYS=(method teamID signingStyle uploadSymbols stripSwiftSymbols)

for plist in "$EXPORT_OPTS_DIR/AppStore.plist" "$EXPORT_OPTS_DIR/Development.plist"; do
  if [[ ! -f "$plist" ]]; then
    fail "ExportOptions plist not found: $plist"
    continue
  fi

  if ! plutil -lint "$plist" >/dev/null 2>&1; then
    fail "malformed plist: $plist"
    continue
  fi

  for key in "${REQUIRED_EXPORT_KEYS[@]}"; do
    check_plist_key "$plist" "$key"
  done

  # Template must still contain the placeholder (not yet substituted).
  if ! grep -q "TEAM_ID_PLACEHOLDER" "$plist"; then
    fail "$plist: TEAM_ID_PLACEHOLDER not found; template has been modified or pre-substituted"
  fi
done

# Verify method values match expectations.
APPSTORE_METHOD="$(/usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_OPTS_DIR/AppStore.plist" 2>/dev/null || true)"
if [[ "$APPSTORE_METHOD" != "app-store-connect" ]]; then
  fail "AppStore.plist method should be 'app-store-connect', got: $APPSTORE_METHOD"
fi

DEV_METHOD="$(/usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_OPTS_DIR/Development.plist" 2>/dev/null || true)"
if [[ "$DEV_METHOD" != "development" ]]; then
  fail "Development.plist method should be 'development', got: $DEV_METHOD"
fi

# ---------------------------------------------------------------------------
# 2. archive_ios.sh syntax check
# ---------------------------------------------------------------------------
ARCHIVE_SCRIPT="$ROOT_DIR/script/archive_ios.sh"
if [[ ! -f "$ARCHIVE_SCRIPT" ]]; then
  fail "archive_ios.sh not found: $ARCHIVE_SCRIPT"
else
  if ! bash -n "$ARCHIVE_SCRIPT" 2>/dev/null; then
    fail "archive_ios.sh has bash syntax errors"
  fi
  if ! grep -Fq -- '--distribution-method "$EXPORT_METHOD"' "$ARCHIVE_SCRIPT"; then
    fail "archive_ios.sh must pass the actual export method to the final IPA profile verifier"
  fi
fi

# ---------------------------------------------------------------------------
# 2b. production Developer ID DMG orchestration contracts
#
# A real DMG build needs portal credentials and contacts Apple's notary service.
# The repository gate therefore validates script syntax and pins every
# fail-closed production stage statically; Python unit tests exercise the
# profile/notary decisions with synthetic profiles and mocked tool responses.
# ---------------------------------------------------------------------------
DMG_SCRIPT="$ROOT_DIR/script/package_dmg.sh"
if [[ ! -x "$DMG_SCRIPT" ]]; then
  fail "package_dmg.sh not found or not executable: $DMG_SCRIPT"
else
  if ! bash -n "$DMG_SCRIPT" 2>/dev/null; then
    fail "package_dmg.sh has bash syntax errors"
  fi
  for required_check in \
    verify_codesign_entitlements.py \
    verify_developer_id_provisioning.py \
    verify_macho_distribution.py \
    verify_macho_closure.py \
    mcp_stdio_smoke.py \
    verify_production_app_runtime.py \
    reset_production_app_group.py \
    prepare_profile_entitlements.py \
    notary_submit_with_evidence.py \
    generate_production_dmg_evidence.py; do
    if ! grep -q "$required_check" "$DMG_SCRIPT"; then
      fail "package_dmg.sh must run $required_check on the composed DMG bundle"
    fi
  done
  if ! grep -q -- "--reset-real-app-group" "$DMG_SCRIPT"; then
    fail "package_dmg.sh must explicitly select the sandboxed helper's real App Group smoke"
  fi
  for required_contract in \
    'require_schema_freeze_armed' \
    'LORVEX_BUILD_CONFIGURATION=release' \
    'SIGN_TIMESTAMP=secure' \
    'verify_final_dmg_signature' \
    'DEVELOPER_ID_APP_PROVISIONING_PROFILE' \
    'DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE' \
    'DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE' \
    'LORVEX_PRODUCTION_INSTALL_PATH' \
    '/Applications/$APP_NAME.app' \
    'LorvexAppleCloudKitAppStore.entitlements' \
    'hdiutil verify' \
    'hdiutil attach' \
    '-readonly' \
    '-mountpoint "$MOUNT_POINT"' \
    'ditto "$MOUNTED_APP" "$INSTALLED_APP"' \
    'reject_ambiguous_dmg_artifacts' \
    'spctl -a -t open --context context:primary-signature' \
    '+$BUILD_VERSION-arm64'; do
    if ! grep -Fq -- "$required_contract" "$DMG_SCRIPT"; then
      fail "package_dmg.sh is missing production contract: $required_contract"
    fi
  done
  if grep -Fq 'SIGN_TIMESTAMP=none' "$DMG_SCRIPT"; then
    fail "package_dmg.sh must never disable secure timestamps"
  fi
  if [[ "$(grep -Fc 'notary_submit_with_evidence.py' "$DMG_SCRIPT")" -ne 2 ]]; then
    fail "package_dmg.sh must notarize both the app payload and final DMG"
  fi
  initial_reset_line="$(grep -nF 'echo "==> Permanently clearing production local state before first launch"' "$DMG_SCRIPT" | cut -d: -f1 || true)"
  initial_runtime_line="$(grep -nF 'echo "==> Cold-launching exact installed main app and verifying plugin registration"' "$DMG_SCRIPT" | cut -d: -f1 || true)"
  helper_smoke_line="$(grep -nF 'echo "==> Running destructive production App Group MCP round-trip"' "$DMG_SCRIPT" | cut -d: -f1 || true)"
  final_reset_line="$(grep -nF 'echo "==> Permanently clearing production local state after MCP smoke"' "$DMG_SCRIPT" | cut -d: -f1 || true)"
  final_runtime_line="$(grep -nF 'echo "==> Final clean-state launch of the exact installed production app"' "$DMG_SCRIPT" | cut -d: -f1 || true)"
  evidence_line="$(grep -nF 'generate_production_dmg_evidence.py' "$DMG_SCRIPT" | tail -1 | cut -d: -f1 || true)"
  if [[ -z "$initial_reset_line" || -z "$initial_runtime_line" \
      || -z "$helper_smoke_line" || -z "$final_reset_line" \
      || -z "$final_runtime_line" || -z "$evidence_line" \
      || "$initial_reset_line" -ge "$initial_runtime_line" \
      || "$initial_runtime_line" -ge "$helper_smoke_line" \
      || "$helper_smoke_line" -ge "$final_reset_line" \
      || "$final_reset_line" -ge "$final_runtime_line" \
      || "$final_runtime_line" -ge "$evidence_line" ]]; then
    fail "package_dmg.sh must initial-reset/launch, smoke, final-reset/relaunch, then seal evidence"
  fi
fi

for python_script in \
  prepare_profile_entitlements.py \
  verify_developer_id_provisioning.py \
  notary_submit_with_evidence.py \
  generate_production_dmg_evidence.py \
  reset_production_app_group.py \
  verify_production_app_runtime.py \
  test_production_dmg_packaging.py; do
  if ! python3 -m py_compile "$ROOT_DIR/script/$python_script" 2>/dev/null; then
    fail "$python_script failed to compile"
  fi
done

# ---------------------------------------------------------------------------
# 3. archive_mas.sh syntax and repository-side MAS readiness
# ---------------------------------------------------------------------------
MAS_ARCHIVE_SCRIPT="$ROOT_DIR/script/archive_mas.sh"
if [[ ! -x "$MAS_ARCHIVE_SCRIPT" ]]; then
  fail "archive_mas.sh not found or not executable: $MAS_ARCHIVE_SCRIPT"
else
  if ! bash -n "$MAS_ARCHIVE_SCRIPT" 2>/dev/null; then
    fail "archive_mas.sh has bash syntax errors"
  fi
fi

if ! "$ROOT_DIR/script/verify_mas_release_readiness.py" >/dev/null 2>&1; then
  fail "verify_mas_release_readiness.py failed"
fi

# sign_app_bundle.sh embeds distribution provisioning profiles and
# verify_mas_provisioning.py cross-checks them; verify_mas_release_readiness.py
# (above) already asserts both are wired together, so here just check syntax.
SIGN_APP_BUNDLE_SCRIPT="$ROOT_DIR/script/sign_app_bundle.sh"
if [[ ! -f "$SIGN_APP_BUNDLE_SCRIPT" ]]; then
  fail "sign_app_bundle.sh not found: $SIGN_APP_BUNDLE_SCRIPT"
elif ! bash -n "$SIGN_APP_BUNDLE_SCRIPT" 2>/dev/null; then
  fail "sign_app_bundle.sh has bash syntax errors"
fi

PROVISIONING_VERIFIER_SCRIPT="$ROOT_DIR/script/verify_mas_provisioning.py"
if [[ ! -f "$PROVISIONING_VERIFIER_SCRIPT" ]]; then
  fail "verify_mas_provisioning.py not found: $PROVISIONING_VERIFIER_SCRIPT"
elif ! python3 -m py_compile "$PROVISIONING_VERIFIER_SCRIPT" 2>/dev/null; then
  fail "verify_mas_provisioning.py failed to compile"
fi

# ---------------------------------------------------------------------------
# 4. Scheme names in archive_ios.sh match project.yml declarations
# ---------------------------------------------------------------------------
PROJECT_YML="$ROOT_DIR/Config/XcodeGen/project.yml"
SCHEMES_IN_SCRIPT=(LorvexMobileApp LorvexVisionApp LorvexWatchApp)

for scheme in "${SCHEMES_IN_SCRIPT[@]}"; do
  if ! grep -q "^  $scheme:" "$PROJECT_YML"; then
    fail "scheme '$scheme' referenced in archive_ios.sh is not declared in project.yml"
  fi
done

# ---------------------------------------------------------------------------
# 5. Mobile bundle ID in project.yml matches app_metadata.sh
# ---------------------------------------------------------------------------
if ! grep -q "$MOBILE_BUNDLE_ID" "$PROJECT_YML"; then
  fail "MOBILE_BUNDLE_ID ($MOBILE_BUNDLE_ID) from app_metadata.sh not found in project.yml"
fi

# ---------------------------------------------------------------------------
# 6. App Group ID consistent across entitlements
# ---------------------------------------------------------------------------
for entitlements_file in \
  "$ROOT_DIR/Config/LorvexMobileApp.entitlements" \
  "$ROOT_DIR/Config/LorvexApple.entitlements" \
  "$ROOT_DIR/Config/LorvexWatchApp.entitlements" \
  "$ROOT_DIR/Config/LorvexWatchComplication.entitlements" \
  "$ROOT_DIR/Config/LorvexWidgetExtension.entitlements"; do
  if [[ ! -f "$entitlements_file" ]]; then
    fail "expected entitlements file not found: $entitlements_file"
    continue
  fi
  if ! grep -q "$APP_GROUP_ID" "$entitlements_file"; then
    fail "$entitlements_file is missing APP_GROUP_ID ($APP_GROUP_ID)"
  fi
done

# ---------------------------------------------------------------------------
# 7. App-Group SIP signed-entitlement validation (macOS 15 SIP-protects the
#    App Group container — see
#    docs/reference/apple-official/MACOS_APP_GROUP_PROVISIONING.md).
#
# Runs against the packaged macOS bundle at dist/$APP_NAME.app when one
# exists (package_local.sh/archive_mas.sh produce it; verify_all.sh's
# packaging tier always builds one before calling this script). Proves what
# is checkable purely from the already-signed bundle on disk — no network,
# no Apple account, no device required:
#   - the App Group entitlement is present on every nested process that
#     needs it (main app, MCP helper, widget extension);
#   - when the signed entitlements also carry an application-identifier
#     (native macOS `com.apple.application-identifier`, falling back to the
#     bare iOS-family `application-identifier` key), it authorizes the
#     right bundle id, and, when a distribution profile is embedded, the
#     profile's own application-identifier matches what was actually signed.
#
# What this CANNOT prove offline — macOS accepting the profile-backed
# restricted entitlement at runtime (`launchctl procinfo` -> "entitlements
# validated"), and a live shared-container read/write test between the app,
# helper, and widget — is reported as a NOTE, never silently treated as a
# pass. Absence of the bundle, absence of a profile, or absence of the
# application-identifier key itself (the current manual-codesign flow in
# sign_app_bundle.sh does not synthesize that key the way Xcode-managed
# signing does) are all soft-skipped with an explanatory NOTE rather than a
# hard failure, since none of those are provable without a real
# Developer-ID/Distribution identity and an embedded provisioning profile.
# ---------------------------------------------------------------------------
APP_GROUP_SIGN_BUNDLE="${APP_GROUP_SIGN_BUNDLE:-"$ROOT_DIR/dist/$APP_NAME.app"}"

app_group_sign_targets() {
  # "label|relative-path-from-app-bundle|expected-bundle-id" for every
  # process that must carry the shared App Group entitlement. "." means the
  # top-level app bundle itself.
  printf '%s\n' \
    "macOS app|.|$BUNDLE_ID" \
    "MCP helper|Contents/Helpers/$MCP_HOST_PRODUCT.app|$MCP_HOST_BUNDLE_ID" \
    "widget extension|Contents/PlugIns/$WIDGET_APPEX_NAME|$WIDGET_BUNDLE_ID"
}

# Decodes an embedded .provisionprofile's application-identifier entitlement.
# `security cms -D -i` only parses the profile's own local CMS signature — no
# network or Apple account involved. Prints nothing (and returns failure) if
# the profile can't be decoded or carries neither identifier key.
decode_embedded_profile_app_id() {
  local profile="$1" tmp value
  tmp="$(mktemp "${TMPDIR:-/tmp}/lorvex-profile-decode.XXXXXX")"
  if ! security cms -D -i "$profile" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  value="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$tmp" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$tmp" 2>/dev/null || true)"
  fi
  rm -f "$tmp"
  if [[ -z "$value" ]]; then
    return 1
  fi
  printf '%s' "$value"
}

check_app_group_signing() {
  local app_bundle="$1"
  if [[ ! -d "$app_bundle" ]]; then
    echo "NOTE: App-Group-SIP signed-entitlement check skipped — no packaged bundle at $app_bundle (run package_local.sh or archive_mas.sh --package first)"
    return 0
  fi

  local label rel_path expected_bundle_id bundle_path details
  local tmp_entitlements app_id app_id_suffix profile_path profile_app_id
  while IFS='|' read -r label rel_path expected_bundle_id; do
    bundle_path="$app_bundle"
    [[ "$rel_path" != "." ]] && bundle_path="$app_bundle/$rel_path"
    if [[ ! -d "$bundle_path" ]]; then
      echo "NOTE: $label bundle not found at $bundle_path — skipping App-Group-SIP check"
      continue
    fi

    if ! details="$(codesign -dvvv "$bundle_path" 2>&1)"; then
      fail "$label: could not read code signature from $bundle_path (is it signed?)"
      continue
    fi
    if grep -Fq "Signature=adhoc" <<<"$details" || grep -Fxq "TeamIdentifier=not set" <<<"$details"; then
      echo "NOTE: $label is ad-hoc/local-signed (no stable identity) — App Group and application-identifier are omitted by design (see sign_app_bundle.sh); skipping"
      continue
    fi

    tmp_entitlements="$(mktemp "${TMPDIR:-/tmp}/lorvex-app-group-sign.XXXXXX")"
    if ! codesign -d --entitlements :- "$bundle_path" >"$tmp_entitlements" 2>/dev/null; then
      fail "$label: could not read signed entitlements from $bundle_path"
      rm -f "$tmp_entitlements"
      continue
    fi

    if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups" "$tmp_entitlements" 2>/dev/null \
        | grep -Fq "$APP_GROUP_ID"; then
      fail "$label signed entitlements at $bundle_path are missing App Group $APP_GROUP_ID"
    fi

    app_id="$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "$tmp_entitlements" 2>/dev/null || true)"
    if [[ -z "$app_id" ]]; then
      app_id="$(/usr/libexec/PlistBuddy -c "Print :application-identifier" "$tmp_entitlements" 2>/dev/null || true)"
    fi
    rm -f "$tmp_entitlements"

    if [[ -z "$app_id" ]]; then
      echo "NOTE: $label signed entitlements carry no application-identifier — REQUIRES SIGNED ARCHIVE: sign_app_bundle.sh's manual codesign flow does not synthesize this key from the checked-in Config/*.entitlements plists the way Xcode-managed signing does. Confirming it requires a real Developer ID/Distribution identity plus an embedded distribution provisioning profile, then decoding the FINAL signed entitlements on that real archive (owner/CI); see docs/reference/apple-official/MACOS_APP_GROUP_PROVISIONING.md."
      continue
    fi

    app_id_suffix="${app_id#*.}"
    if [[ "$app_id_suffix" != "$expected_bundle_id" ]]; then
      fail "$label signed application-identifier ($app_id) does not authorize bundle id $expected_bundle_id"
    fi

    profile_path="$bundle_path/Contents/embedded.provisionprofile"
    if [[ ! -f "$profile_path" ]]; then
      echo "NOTE: $label has no embedded provisioning profile — REQUIRES SIGNED ARCHIVE: profile authorization of application-identifier $app_id cannot be checked offline (expected for a local/dev build)"
      continue
    fi
    if profile_app_id="$(decode_embedded_profile_app_id "$profile_path")"; then
      if [[ "$profile_app_id" != "$app_id" ]]; then
        fail "$label embedded provisioning profile authorizes application-identifier $profile_app_id, but the signed executable carries $app_id"
      fi
    else
      echo "NOTE: $label embedded provisioning profile has no decodable application-identifier entitlement — cannot cross-check offline"
    fi
  done < <(app_group_sign_targets)

  echo "NOTE: App-Group-SIP validation above covers only what is provable from the on-disk signed bundle. Runtime acceptance (\`launchctl procinfo\` -> \"entitlements validated\"), a live shared-container read/write test between the app/helper/widget, and full App Store review all REQUIRE a real signed archive and device install — see docs/reference/apple-official/MACOS_APP_GROUP_PROVISIONING.md \"Required Release Evidence\"."
}

check_app_group_signing "$APP_GROUP_SIGN_BUNDLE"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo "verify_packaging: FAILED" >&2
  for f in "${FAILURES[@]}"; do
    echo "  FAIL: $f" >&2
  done
  exit 1
fi

echo "verify_packaging passed"
