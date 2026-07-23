#!/usr/bin/env bash
# Release preflight — delegates the canonical completion/release
# verification matrix to the manifest-backed runner.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

exec node scripts/release/preflight.mjs
