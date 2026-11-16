#!/usr/bin/env bash
# Shared App Store Connect authentication for validation, upload, and polling.
# Prefer the API key used by Xcode provisioning. Legacy app-specific passwords
# remain in the environment and are never included literally in command args.

configure_altool_auth() {
  ALTOOL_AUTH_ARGS=()
  if [[ -n "${ASC_KEY_ID:-}" || -n "${ASC_ISSUER_ID:-}" ]]; then
    if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
      echo "App Store Connect API authentication requires both ASC_KEY_ID and ASC_ISSUER_ID." >&2
      return 2
    fi
    ALTOOL_AUTH_ARGS=(--api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID")
    if [[ -n "${ASC_KEY_PATH:-}" ]]; then
      if [[ ! -f "$ASC_KEY_PATH" || ! -r "$ASC_KEY_PATH" ]]; then
        echo "ASC_KEY_PATH must name a readable API private-key file." >&2
        return 2
      fi
      ALTOOL_AUTH_ARGS+=(--p8-file-path "$ASC_KEY_PATH")
    fi
    return 0
  fi

  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_PASSWORD:-${APPLE_PASSWORD:-}}" ]]; then
    echo "Configure ASC_KEY_ID/ASC_ISSUER_ID, or APPLE_ID with an app-specific password." >&2
    return 2
  fi
  export APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-$APPLE_PASSWORD}"
  ALTOOL_AUTH_ARGS=(--username "$APPLE_ID" --password "@env:APPLE_APP_PASSWORD")
}
