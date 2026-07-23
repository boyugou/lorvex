#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update_and_install_linux.sh [options]

Options:
  --no-pull             Skip `git pull --ff-only origin main`
  --bundle <type>       Linux bundle to build: deb | appimage | rpm (default: deb)
  --install             Install artifact after build (deb/rpm via package manager, appimage to ~/.local/bin)
  --open                Launch Lorvex after install/build
  -h, --help            Show this help
EOF
}

DO_PULL=1
DO_OPEN=0
DO_INSTALL=0
BUNDLE="deb"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    echo "Install prerequisites first, then rerun this script." >&2
    exit 1
  fi
}

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  echo "Install step requires elevated privileges, but sudo is not available." >&2
  echo "Rerun as root, or install sudo and rerun with --install." >&2
  exit 1
}

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
    --install)
      DO_INSTALL=1
      shift
      ;;
    --bundle)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --bundle" >&2
        usage
        exit 1
      fi
      BUNDLE="$2"
      shift 2
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

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script is Linux-only. Use scripts/update_and_install.sh on macOS or scripts/update_and_install_windows.ps1 on Windows." >&2
  exit 1
fi

require_cmd git
require_cmd node
require_cmd npm

case "$BUNDLE" in
  deb|appimage|rpm) ;;
  *)
    echo "Unsupported bundle: $BUNDLE (expected deb|appimage|rpm)" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PATH="$HOME/.cargo/bin:$PATH"

echo "==> Repo: ${REPO_ROOT}"
cd "${REPO_ROOT}"

if [[ ! -f "${REPO_ROOT}/app/package.json" || ! -d "${REPO_ROOT}/app/src-tauri" ]]; then
  echo "Repository layout check failed at ${REPO_ROOT}. Expected app/package.json and app/src-tauri/." >&2
  exit 1
fi

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

echo "==> Building Linux bundle (${BUNDLE})"
# Forward --locked after Tauri's Cargo separator so install smoke builds use
# the committed Cargo.lock instead of silently re-resolving dependencies.
npm run -w app tauri:build -- --bundles "${BUNDLE}" -- --locked

BUNDLE_DIR="${REPO_ROOT}/app/src-tauri/target/release/bundle/${BUNDLE}"
if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "Build finished but bundle directory not found: ${BUNDLE_DIR}" >&2
  exit 1
fi

case "${BUNDLE}" in
  deb) EXT="deb" ;;
  rpm) EXT="rpm" ;;
  appimage) EXT="AppImage" ;;
  *) EXT="" ;;
esac

mapfile -t ARTIFACTS < <(find "${BUNDLE_DIR}" -maxdepth 1 -type f -name "*.${EXT}" -print)
if [[ "${#ARTIFACTS[@]}" -eq 0 ]]; then
  echo "Build finished but no .${EXT} artifact found in: ${BUNDLE_DIR}" >&2
  exit 1
fi

ARTIFACT=""
ARTIFACT_MTIME=0
for candidate in "${ARTIFACTS[@]}"; do
  candidate_mtime="$(stat -c '%Y' "${candidate}")"
  if [[ -z "${ARTIFACT}" || "${candidate_mtime}" -gt "${ARTIFACT_MTIME}" ]]; then
    ARTIFACT="${candidate}"
    ARTIFACT_MTIME="${candidate_mtime}"
  fi
done
if [[ "${ARTIFACT}" != "${BUNDLE_DIR}/"* || ! -f "${ARTIFACT}" ]]; then
  echo "Resolved artifact path is invalid: ${ARTIFACT}" >&2
  exit 1
fi

echo "==> Built artifact: ${ARTIFACT}"

LAUNCH_PATH=""

if [[ "${DO_INSTALL}" -eq 1 ]]; then
  case "${BUNDLE}" in
    deb)
      if command -v dpkg >/dev/null 2>&1; then
        echo "==> Installing deb via dpkg"
        if ! run_as_root dpkg -i "${ARTIFACT}"; then
          if command -v apt-get >/dev/null 2>&1; then
            echo "==> Resolving missing dependencies via apt-get"
            run_as_root apt-get install -f -y
            run_as_root dpkg -i "${ARTIFACT}"
          else
            echo "dpkg install failed and apt-get is not available to resolve dependencies." >&2
            exit 1
          fi
        fi
      else
        echo "dpkg not found; cannot install deb automatically." >&2
        exit 1
      fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        echo "==> Installing rpm via dnf"
        run_as_root dnf install -y "${ARTIFACT}"
      elif command -v yum >/dev/null 2>&1; then
        echo "==> Installing rpm via yum"
        run_as_root yum install -y "${ARTIFACT}"
      elif command -v zypper >/dev/null 2>&1; then
        echo "==> Installing rpm via zypper"
        run_as_root zypper --non-interactive install "${ARTIFACT}"
      else
        echo "No supported rpm package manager found (dnf/yum/zypper)." >&2
        exit 1
      fi
      ;;
    appimage)
      INSTALL_DIR="${HOME}/.local/bin"
      INSTALL_PATH="${INSTALL_DIR}/Lorvex.AppImage"
      echo "==> Installing AppImage to ${INSTALL_PATH}"
      mkdir -p "${INSTALL_DIR}"
      cp "${ARTIFACT}" "${INSTALL_PATH}"
      chmod +x "${INSTALL_PATH}"
      LAUNCH_PATH="${INSTALL_PATH}"
      ;;
  esac
fi

if [[ "${DO_OPEN}" -eq 1 ]]; then
  if [[ -z "${LAUNCH_PATH}" ]]; then
    if command -v lorvex >/dev/null 2>&1; then
      LAUNCH_PATH="$(command -v lorvex)"
    elif command -v Lorvex >/dev/null 2>&1; then
      LAUNCH_PATH="$(command -v Lorvex)"
    elif [[ "${BUNDLE}" == "appimage" ]]; then
      LAUNCH_PATH="${ARTIFACT}"
    elif [[ -x "/usr/bin/lorvex" ]]; then
      LAUNCH_PATH="/usr/bin/lorvex"
    elif [[ -x "/usr/bin/Lorvex" ]]; then
      LAUNCH_PATH="/usr/bin/Lorvex"
    fi
  fi

  if [[ -n "${LAUNCH_PATH}" && -x "${LAUNCH_PATH}" ]]; then
    echo "==> Launching ${LAUNCH_PATH}"
    nohup "${LAUNCH_PATH}" >/dev/null 2>&1 &
  else
    echo "Install/build completed, but no executable launch path was found." >&2
  fi
fi

echo "Done."
