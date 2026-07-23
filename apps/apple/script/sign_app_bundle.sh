#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"

APP_BUNDLE="${1:-"$ROOT_DIR/dist/$APP_NAME.app"}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_PLUGINS="$APP_CONTENTS/PlugIns"
WIDGET_BUNDLE="$APP_PLUGINS/$WIDGET_APPEX_NAME"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH-"$ROOT_DIR/Config/LorvexApple.entitlements"}"
HELPER_ENTITLEMENTS_PATH="${HELPER_ENTITLEMENTS_PATH-"$ROOT_DIR/Config/LorvexMCPHost.entitlements"}"
WIDGET_ENTITLEMENTS_PATH="${WIDGET_ENTITLEMENTS_PATH-"$ROOT_DIR/Config/LorvexWidgetExtension.entitlements"}"
SIGN_TIMESTAMP="${SIGN_TIMESTAMP:-auto}"
SIGN_TIMEOUT_SECONDS="${SIGN_TIMEOUT_SECONDS:-120}"

# Distribution provisioning profiles, mirroring how signing identities and
# entitlements are already passed (env var override, default falls back to a
# checked-in-but-gitignored `secrets/` convention — see .gitignore's "Secrets &
# internal ops" block). *_PROVISIONING_PROFILE_SET distinguishes "caller
# explicitly pointed at a path" (missing file is a hard config error) from
# "using the default secrets/ location" (missing file just means no profile
# was ever placed there, i.e. an ordinary dev build — soft-skip embedding).
APP_PROVISIONING_PROFILE_DEFAULT="$ROOT_DIR/secrets/profiles/$APP_PRODUCT_NAME.provisionprofile"
HELPER_PROVISIONING_PROFILE_DEFAULT="$ROOT_DIR/secrets/profiles/$MCP_HOST_PRODUCT.provisionprofile"
WIDGET_PROVISIONING_PROFILE_DEFAULT="$ROOT_DIR/secrets/profiles/$WIDGET_EXECUTABLE.provisionprofile"
APP_PROVISIONING_PROFILE_SET="${APP_PROVISIONING_PROFILE+1}"
HELPER_PROVISIONING_PROFILE_SET="${HELPER_PROVISIONING_PROFILE+1}"
WIDGET_PROVISIONING_PROFILE_SET="${WIDGET_PROVISIONING_PROFILE+1}"
APP_PROVISIONING_PROFILE="${APP_PROVISIONING_PROFILE-"$APP_PROVISIONING_PROFILE_DEFAULT"}"
HELPER_PROVISIONING_PROFILE="${HELPER_PROVISIONING_PROFILE-"$HELPER_PROVISIONING_PROFILE_DEFAULT"}"
WIDGET_PROVISIONING_PROFILE="${WIDGET_PROVISIONING_PROFILE-"$WIDGET_PROVISIONING_PROFILE_DEFAULT"}"

# Embeds a distribution provisioning profile into a bundle before it is
# signed (embedding after signing would invalidate the signature). Absent
# profile at the default secrets/ location is a normal dev build and is
# silently skipped; an explicitly-set path that does not exist is a
# misconfiguration and hard-fails.
embed_provisioning_profile() {
  local profile_path="$1" dest="$2" was_explicitly_set="$3" label="$4"
  if [[ -z "$profile_path" ]]; then
    return 0
  fi
  if [[ ! -f "$profile_path" ]]; then
    if [[ -n "$was_explicitly_set" ]]; then
      echo "$label provisioning profile not found: $profile_path" >&2
      exit 2
    fi
    return 0
  fi
  cp "$profile_path" "$dest"
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 2
fi

# Refuse to sign a bundle carrying a com.apple.quarantine xattr anywhere in its
# tree. A quarantined file that slips into the signed artifact makes Gatekeeper
# kill the app on first launch on a fresh machine. Fail loudly rather than
# stripping the attribute, so the upstream source of the quarantined file gets
# fixed instead of masked.
if xattr -rl "$APP_BUNDLE" | grep -q "com.apple.quarantine"; then
  echo "sign_app_bundle: FAIL: com.apple.quarantine xattr present in $APP_BUNDLE" >&2
  exit 1
fi

codesign_with_timeout() {
  local status
  if [[ "$SIGN_TIMEOUT_SECONDS" == "0" ]]; then
    codesign "$@"
    return
  fi
  set +e
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' \
    "$SIGN_TIMEOUT_SECONDS" codesign "$@"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    if [[ "$status" -eq 142 ]]; then
      echo "codesign timed out after ${SIGN_TIMEOUT_SECONDS}s; unlock/authorize the keychain private key or check Apple's timestamp service" >&2
    fi
    return "$status"
  fi
}

case "$SIGN_TIMESTAMP" in
  auto)
    timestamp_arg=(--timestamp=none)
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
      timestamp_arg=(--timestamp)
    fi
    ;;
  secure|yes|true|1)
    timestamp_arg=(--timestamp)
    ;;
  none|no|false|0)
    timestamp_arg=(--timestamp=none)
    ;;
  *)
    echo "invalid SIGN_TIMESTAMP value: $SIGN_TIMESTAMP" >&2
    exit 2
    ;;
esac

sign_args=(--force --sign "$SIGNING_IDENTITY" "${timestamp_arg[@]}")
app_sign_args=("${sign_args[@]}" --options runtime)
nested_sign_args=("${sign_args[@]}" --options runtime)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  if [[ -n "$ENTITLEMENTS_PATH" || -n "$HELPER_ENTITLEMENTS_PATH" || -n "$WIDGET_ENTITLEMENTS_PATH" ]]; then
    echo "sign_app_bundle: ad-hoc signing cannot provide a stable App Group; omitting entitlements" >&2
  fi
  ENTITLEMENTS_PATH=""
  HELPER_ENTITLEMENTS_PATH=""
  WIDGET_ENTITLEMENTS_PATH=""
  if [[ -n "$APP_PROVISIONING_PROFILE_SET" || -n "$HELPER_PROVISIONING_PROFILE_SET" || -n "$WIDGET_PROVISIONING_PROFILE_SET" ]]; then
    echo "sign_app_bundle: ad-hoc signing cannot carry a distribution provisioning profile; omitting profile embedding" >&2
  fi
  APP_PROVISIONING_PROFILE=""
  HELPER_PROVISIONING_PROFILE=""
  WIDGET_PROVISIONING_PROFILE=""
fi

if [[ -n "$ENTITLEMENTS_PATH" ]]; then
  if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
    echo "entitlements file not found: $ENTITLEMENTS_PATH" >&2
    exit 2
  fi
  app_sign_args+=(--entitlements "$ENTITLEMENTS_PATH")
fi

widget_sign_args=("${sign_args[@]}" --options runtime)
helper_sign_args=("${sign_args[@]}" --options runtime)
if [[ -n "$HELPER_ENTITLEMENTS_PATH" ]]; then
  if [[ ! -f "$HELPER_ENTITLEMENTS_PATH" ]]; then
    echo "helper entitlements file not found: $HELPER_ENTITLEMENTS_PATH" >&2
    exit 2
  fi
  helper_sign_args+=(--entitlements "$HELPER_ENTITLEMENTS_PATH")
fi

if [[ -n "$WIDGET_ENTITLEMENTS_PATH" ]]; then
  if [[ ! -f "$WIDGET_ENTITLEMENTS_PATH" ]]; then
    echo "widget entitlements file not found: $WIDGET_ENTITLEMENTS_PATH" >&2
    exit 2
  fi
  widget_sign_args+=(--entitlements "$WIDGET_ENTITLEMENTS_PATH")
fi

if [[ -d "$APP_FRAMEWORKS" ]]; then
  while IFS= read -r -d '' item; do
    codesign_with_timeout "${nested_sign_args[@]}" "$item"
  done < <(find "$APP_FRAMEWORKS" -type f \( -name "*.dylib" -o -perm -111 \) -print0)
fi

# The helper ships as a minimal app bundle (Contents/Helpers/<name>.app), not a
# bare Mach-O: a bare executable has no Info.plist, so the sandbox cannot
# initialize a container for it and a sandbox-entitled bare binary is killed at
# launch. Sign any nested executables inside the helper bundle first (mirrors
# the appex loop below; the helper has none today, but this keeps signing
# order correct if one is ever bundled), then sign the helper bundle itself
# with its own entitlements so the embedded Mach-O carries the sandbox grant.
if [[ -d "$APP_HELPERS" ]]; then
  while IFS= read -r -d '' item; do
    while IFS= read -r -d '' nested; do
      codesign_with_timeout "${nested_sign_args[@]}" "$nested"
    done < <(find "$item/Contents" -type f -perm -111 -print0 2>/dev/null || true)
    embed_provisioning_profile "$HELPER_PROVISIONING_PROFILE" "$item/Contents/embedded.provisionprofile" \
      "$HELPER_PROVISIONING_PROFILE_SET" "MCP helper"
    codesign_with_timeout "${helper_sign_args[@]}" "$item"
  done < <(find "$APP_HELPERS" -maxdepth 1 -type d -name "*.app" -print0)
fi

if [[ -d "$APP_PLUGINS" ]]; then
  # The macOS product currently ships exactly one extension.  Never apply the
  # widget's entitlements/profile to a newly-added appex by accident: every new
  # extension needs its own explicit bundle id, entitlement plan, profile, and
  # signing branch before it can enter a release artifact.
  while IFS= read -r -d '' item; do
    if [[ "$item" != "$WIDGET_BUNDLE" ]]; then
      echo "unexpected macOS app extension requires explicit signing configuration: $item" >&2
      exit 2
    fi
  done < <(find "$APP_PLUGINS" -maxdepth 1 -type d -name "*.appex" -print0)

  if [[ -d "$WIDGET_BUNDLE" ]]; then
    while IFS= read -r -d '' nested; do
      codesign_with_timeout "${nested_sign_args[@]}" "$nested"
    done < <(find "$WIDGET_BUNDLE/Contents" -type f -perm -111 -print0)
    embed_provisioning_profile "$WIDGET_PROVISIONING_PROFILE" \
      "$WIDGET_BUNDLE/Contents/embedded.provisionprofile" \
      "$WIDGET_PROVISIONING_PROFILE_SET" "widget extension"
    codesign_with_timeout "${widget_sign_args[@]}" "$WIDGET_BUNDLE"
  fi
fi

embed_provisioning_profile "$APP_PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile" \
  "$APP_PROVISIONING_PROFILE_SET" "macOS app"
codesign_with_timeout "${app_sign_args[@]}" "$APP_BUNDLE"
