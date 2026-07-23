#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update_and_install.sh [options]

Options:
  --no-pull    Skip `git pull --ff-only origin main`
  --open       Open the installed Lorvex.app after install
  -h, --help   Show this help
EOF
}

require_command() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    echo "Install hint: ${install_hint}" >&2
    exit 1
  fi
}

DO_PULL=1
DO_OPEN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pull)
      DO_PULL=0
      shift
      ;;
    --open)
      DO_OPEN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is macOS-only. Use scripts/update_and_install_linux.sh on Linux or scripts/update_and_install_windows.ps1 on Windows." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE_SRC="${REPO_ROOT}/app/src-tauri/target/release/bundle/macos/Lorvex.app"
SYSTEM_APP_DIR="/Applications"
HOME_APP_DIR="${HOME}/Applications"
INSTALL_TARGET_DIR="${SYSTEM_APP_DIR}"

export PATH="$HOME/.cargo/bin:$PATH"

require_command git "Install Xcode Command Line Tools and ensure git is on PATH."
require_command node "Install Node.js 22+."
require_command npm "Install npm 10+."
require_command cargo "Install the Rust toolchain with rustup."
require_command rustc "Install the Rust toolchain with rustup."
require_command ditto "macOS system utility missing; verify Command Line Tools are installed."
require_command codesign "macOS code signing tool missing; verify Xcode Command Line Tools are installed."

if [[ ! -w "${SYSTEM_APP_DIR}" ]]; then
  mkdir -p "${HOME_APP_DIR}"
  INSTALL_TARGET_DIR="${HOME_APP_DIR}"
fi

APP_BUNDLE_DST="${INSTALL_TARGET_DIR}/Lorvex.app"

echo "==> Repo: ${REPO_ROOT}"
cd "${REPO_ROOT}"

if [[ "${DO_PULL}" -eq 1 ]]; then
  echo "==> Pulling latest main"
  git pull --ff-only origin main
else
  echo "==> Skipping git pull"
fi

if [[ ! -f package-lock.json ]]; then
  echo "Missing package-lock.json; refusing to install mutable npm dependencies." >&2
  echo "This source-checkout install path requires the committed npm lockfile. Restore it or run an explicit development bootstrap outside this installer." >&2
  exit 1
fi

echo "==> Installing npm dependencies from package-lock.json"
npm ci

echo "==> Building app bundle"
# Use the workspace-installed Tauri CLI from repo root.
# This avoids `npx` trying to fetch packages over network when app/node_modules is absent.
# Audit #2299: trailing `-- --locked` forwards to cargo so Cargo.lock
# drift fails the build; pairs with exact-pinned critical-path deps
# in app/src-tauri/Cargo.toml.
npm run -w app tauri:build -- --bundles app -- --locked

if [[ ! -d "${APP_BUNDLE_SRC}" ]]; then
  echo "Build finished but app bundle not found: ${APP_BUNDLE_SRC}" >&2
  exit 1
fi

# Audit #2318: verify the built bundle is Developer-ID signed before
# overwriting /Applications. An unsigned or ad-hoc bundle (missing
# .env.build, stale APPLE_SIGNING_IDENTITY, expired signing material)
# would silently install and later fail Gatekeeper/distribution checks.
echo "==> Verifying bundle signature"
if ! codesign --verify --verbose=2 "${APP_BUNDLE_SRC}" >/dev/null 2>&1; then
  echo "ERROR: built bundle fails codesign verification; refusing to install." >&2
  echo "       Bundle: ${APP_BUNDLE_SRC}" >&2
  exit 1
fi
if ! codesign -dv "${APP_BUNDLE_SRC}" 2>&1 | grep -q 'Authority=Developer ID'; then
  echo "WARN: bundle is not Developer-ID-signed — do not distribute this build." >&2
  echo "      Check .env.build and APPLE_SIGNING_IDENTITY before distributing." >&2
fi

echo "==> Installing to ${APP_BUNDLE_DST}"
ditto "${APP_BUNDLE_SRC}" "${APP_BUNDLE_DST}"

# Skip re-signing: the Tauri build already signs with the Developer ID identity
# when signing is configured. Re-signing here would make the installed bundle
# diverge from the build artifact that was verified above.

if [[ "${DO_OPEN}" -eq 1 ]]; then
  echo "==> Opening ${APP_BUNDLE_DST}"
  open "${APP_BUNDLE_DST}"
fi

echo "Done."
