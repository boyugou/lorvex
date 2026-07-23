#!/usr/bin/env bash
#
# Deploy the CloudKit schema to the development environment.
#
# This CLI is development-only. Production CloudKit schema is effectively
# irreversible once a container holds user data, and this text-schema path
# has none of the review/rollback safety of the CloudKit Console. Production
# promotion is a human step: after the development schema below has been
# validated and reviewed, promote it by hand through the CloudKit Console
# (https://icloud.developer.apple.com/dashboard/) — never through this
# script or LORVEX_CLOUDKIT_ENVIRONMENT=production.
#
# Prerequisites:
#   1. Xcode 13+ installed (provides xcrun cktool)
#   2. A management token saved in Keychain:
#      xcrun cktool save-token --type management
#   3. Or set CLOUDKIT_MANAGEMENT_TOKEN environment variable
#
# Usage:
#   bash cloudkit/deploy-schema.sh
#   bash cloudkit/deploy-schema.sh --help
#
# To reset the development schema back to production's shape first:
#   bash cloudkit/deploy-schema.sh --reset

set -euo pipefail
# Audit #2988-L7: explicitly disable trace mode. The CloudKit
# management token is read by `xcrun cktool` from Keychain or the
# `CLOUDKIT_MANAGEMENT_TOKEN` env var; if a contributor enabled
# `set -x` to debug a failure, every command — including environment
# context — would be echoed to stdout/stderr and could land in CI
# logs. Forcing `+x` here is defense-in-depth: any future `set -x`
# that lands accidentally is undone before the token-handling steps
# run.
set +x

usage() {
  cat <<'EOF'
Usage: bash cloudkit/deploy-schema.sh [--reset|--help]

Deploy schema.ckdb to the CloudKit development environment.

Options:
  --reset  Reset Development to Production's schema, delete Development data,
           then validate and import schema.ckdb.
  --help   Show this help and exit without contacting CloudKit.
EOF
}

MODE="deploy"
if [ "$#" -gt 1 ]; then
  echo "Error: expected no arguments, --reset, or --help." >&2
  usage >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  case "$1" in
    --reset)
      MODE="reset"
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      usage >&2
      exit 2
      ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/schema.ckdb"
# Audit #2931-M24: read CloudKit identity from env so a fork or a
# secondary container (sandbox, App Store separate ID) can point at
# its own CloudKit context without editing this script. The defaults
# match the production Lorvex container so the no-arg path stays
# compatible with the existing release workflow.
TEAM_ID="${LORVEX_CLOUDKIT_TEAM_ID:-VP5XSC3VN6}"
CONTAINER_ID="${LORVEX_CLOUDKIT_CONTAINER_ID:-iCloud.com.lorvex.apple}"
ENVIRONMENT="${LORVEX_CLOUDKIT_ENVIRONMENT:-development}"

# Hard guard: this script only ever talks to the development environment.
# Reject anything else — including "production" — before any cktool call
# (validate, import, or reset) runs, so a stray or misconfigured
# LORVEX_CLOUDKIT_ENVIRONMENT can never reach a production write. There is
# intentionally no escape-hatch flag for this: production promotion happens
# by hand through the CloudKit Console after review.
if [ "$ENVIRONMENT" != "development" ]; then
  echo "Error: cloudkit/deploy-schema.sh only supports the development environment." >&2
  echo "       Got LORVEX_CLOUDKIT_ENVIRONMENT='$ENVIRONMENT'." >&2
  echo "       Production schema changes are promoted by hand through the" >&2
  echo "       CloudKit Console: https://icloud.developer.apple.com/dashboard/" >&2
  exit 1
fi

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "Error: schema.ckdb not found at $SCHEMA_FILE"
  exit 1
fi

if [ "$MODE" = "reset" ]; then
  # reset-schema itself is Development-only. Xcode 26.6 deliberately exposes
  # no --environment option for this command; the environment guard above also
  # prevents a contradictory script configuration from reaching any cktool
  # operation.
  echo "==> Resetting $ENVIRONMENT schema..."
  xcrun cktool reset-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID"
  echo "==> Reset complete."
fi

echo "==> Validating schema..."
xcrun cktool validate-schema \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" \
  --file "$SCHEMA_FILE"

echo "==> Importing schema to $ENVIRONMENT..."
xcrun cktool import-schema \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" \
  --file "$SCHEMA_FILE"

echo "==> Schema deployed to $ENVIRONMENT."
echo ""
echo "NOTE: To promote to production, use the CloudKit Console web UI:"
echo "  https://icloud.developer.apple.com/dashboard/"
