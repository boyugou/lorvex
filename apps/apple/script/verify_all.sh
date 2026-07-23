#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_metadata.sh"
cd "$ROOT_DIR"

# The only process this gate ever launches is $APP_NAME, via
# `build_and_run.sh --verify`'s smoke launch below; $APP_PRODUCT_NAME,
# $MOBILE_APP_NAME, and $VISION_APP_NAME are only ever `swift build`-compiled
# here, never executed, so there is nothing to clean up for them. A global
# `pkill -x "$APP_NAME"` would kill every process with that name on the
# machine, including a real, already-running instance of the shipped app
# (e.g. a developer's own daily-use Lorvex.app) that this run never touched —
# so track and kill only the PID(s) this run itself spawns.
LAUNCHED_APP_PIDS=()

record_launched_app_pids() {
  local pids_before="$1" pid
  for pid in $(pgrep -x "$APP_NAME" 2>/dev/null || true); do
    if ! grep -qx "$pid" <<<"$pids_before"; then
      LAUNCHED_APP_PIDS+=("$pid")
    fi
  done
}

cleanup() {
  local pid
  for pid in "${LAUNCHED_APP_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

swift build --product "$APP_PRODUCT_NAME"
swift build --product "$MOBILE_APP_NAME"
swift build --product "$VISION_APP_NAME"
swift build --product LorvexWidgetBundle
swift build --product "$WIDGET_EXECUTABLE"
swift build --product LorvexWatchApp
swift build --product LorvexWatchComplication
swift build --product "$MCP_HOST_PRODUCT"
# Realize every resource bundle the test suite loads before compiling catalogs.
# The product builds above do not cover LorvexCarPlay (its `Localizable.xcstrings`
# ships only as a LorvexAppleTests dependency), so `--build-tests` builds the full
# test dependency closure and its `<Package>_<Target>.bundle` set. `swift test`
# below reuses this build incrementally.
swift build --build-tests
# Compile the String Catalogs (`*.xcstrings`) into per-language `.lproj/*.strings`
# tables inside the freshly built resource bundles. `swift build` copies the raw
# catalog but never compiles it, so without this step the LocalizationTests below
# load no compiled tables on a cold checkout (`.lproj` lookup → nil, plurals render
# raw `%lld`, non-English falls back to English). Strict (no `--best-effort`): a
# missing `xcstringstool` or zero catalogs fails the gate rather than shipping an
# untested localization path.
./script/compile_xcstrings.sh
swift test
# The Swift core package is the parity oracle for the app backend; its tests
# must pass on every full gate.
( cd core && swift test )
python3 -m py_compile \
  script/generate_acknowledgments.py \
  script/generate_apple_platform_manifest.py \
  script/generate_mcp_client_config.py \
  script/generate_release_manifest.py \
  script/quality_gates.py \
  script/xcodegen_dependency_check.py \
  script/verify_acknowledgments.py \
  script/verify_app_metadata.py \
  script/verify_apple_platform_manifest.py \
  script/verify_apple_strategy.py \
  script/verify_build_matrix.py \
  script/verify_backup_v1_contract.py \
  script/verify_cloudkit_sync_readiness.py \
  script/verify_codesign_entitlements.py \
  script/verify_core_service_coverage.py \
  script/verify_hotspots.py \
  script/verify_ios_ipa.py \
  script/verify_localization_catalog.py \
  script/verify_sqlite_portability.py \
  script/verify_macho_closure.py \
  script/verify_macho_distribution.py \
  script/verify_mas_release_readiness.py \
  script/verify_mas_provisioning.py \
  script/verify_mcp_client_config.py \
  script/verify_mcp_tool_catalog.py \
  script/verify_migration_ladder.py \
  script/verify_privacy_manifests.py \
  script/verify_repo_hygiene.py \
  script/verify_release_manifest.py \
  script/verify_schema_freeze.py \
  script/verify_source_entitlements.py \
  script/verify_source_hygiene.py \
  script/verify_sync_payload_contract.py \
  script/verify_system_entrypoints.py \
  script/verify_user_docs.py \
  script/test_*.py
python3 -m unittest discover -s script -p 'test_*.py'
# schema/ is the Apple app's own schema authority: assert the bundled LorvexCore
# copies (schema.sql, the migration ladder, checksums.lock) are byte-identical to
# it before anything else builds against them. This is an Apple-only integrity
# check — Apple and Tauri are only directionally aligned (shared concepts via
# spec/), not byte-locked, so the Tauri schema copy is never compared here.
./script/verify_schema_embed.sh
# The semantic ladder rules over the canonical schema/migrations/ (contiguous
# numbering, checksum agreement, launch-regime gating).
./script/verify_migration_ladder.py
# Versioned wire-field inventory: a payload field/entity change must bump
# LorvexVersion.payloadSchemaVersion and append the next immutable contract.
./script/verify_sync_payload_contract.py
# First-public backup wire freeze: the v5 DTO sources, native graph v2, and the
# production-shaped golden fixture are immutable even while the app's internal
# models continue to evolve behind explicit per-version adapters.
./script/verify_backup_v1_contract.py
# Schema-freeze tripwire: dormant advisory pre-launch, arms at first public
# release to fail mutation of either a released SQLite baseline checksum or a
# released sync-payload contract.
./script/verify_schema_freeze.py
./script/verify_repo_hygiene.py
# Reject over-broad grants in the source .entitlements plists (sandbox-disable,
# network, files.all, temporary-exceptions) before they can be signed into a build.
./script/verify_source_entitlements.py
# Apple source-shape/UI-polish invariants (typography tokens, calm empty-state
# panels, inline header controls, retired capture surfaces). These are
# repository-hygiene scans, kept out of `swift test` so the Apple suite never
# walks source trees; one rule spans the monorepo (incl. apps/tauri) but tolerates
# an absent/relocated Tauri tree.
./script/verify_source_hygiene.py
./script/verify_app_metadata.py
./script/verify_apple_strategy.py
./script/verify_build_matrix.py
# Assert the XcodeGen project embeds the watch app in the iOS app (the release
# archive relies on this); the check must run, not merely be py_compiled above.
./script/xcodegen_dependency_check.py --owner "$MOBILE_APP_NAME" --dependency "$WATCH_APP_NAME" --require-embed
./script/verify_cloudkit_sync_readiness.py
./script/verify_mcp_tool_catalog.py
./script/verify_mcp_tool_manifest.py
./script/verify_localization_catalog.py
./script/verify_acknowledgments.py
./script/verify_privacy_manifests.py
./script/verify_system_entrypoints.py
python3 ./script/verify_core_service_coverage.py
./script/verify_hotspots.py
./script/verify_sqlite_portability.py
./script/verify_user_docs.py
./script/verify_xcodegen_project.sh
./script/generate_apple_platform_manifest.py
./script/verify_apple_platform_manifest.py "$ROOT_DIR/dist/lorvex-apple-platform-manifest.json"
./script/mcp_stdio_smoke.py

# ---------------------------------------------------------------------------
# Packaging tier, split by credential need.
#
# Unsigned packaging + distribution audits ALWAYS run (no signing identity
# needed): stage the macOS app with package_local.sh, then check the packaged
# bundle for codesign/entitlements, Mach-O distribution correctness, and dynamic
# load closure, plus the static packaging checks in verify_packaging.sh. Hosted
# CI can and does exercise these on every gate.
#
# The GUI smoke launch and the real signing/notarize path are gated behind
# LORVEX_VERIFY_SKIP_PACKAGING=1 (CI sets it): build_and_run.sh --verify launches
# the app and is flaky on headless runners, while archive_local.sh's real-
# identity path and notarize_archive.sh --preflight need signing identities that
# only live on the owner's machine. A local `verify_all.sh` with no flag runs
# the full set.
# ---------------------------------------------------------------------------
./script/package_local.sh
# Run codesign / Mach-O distribution checks against the packaged app bundle.
# These are also run inside archive_local.sh; running them here ensures they
# execute on every gate, not just during archiving.
PACKAGED_APP="$ROOT_DIR/dist/$APP_NAME.app"
if [[ ! -d "$PACKAGED_APP" ]]; then
  echo "verify_all: expected packaged app bundle missing at $PACKAGED_APP" >&2
  echo "verify_all: package_local.sh above should have produced it; refusing to skip the" >&2
  echo "verify_all: codesign/Mach-O checks (a drifted bundle path must fail, not pass)." >&2
  exit 1
fi
"$ROOT_DIR/script/verify_codesign_entitlements.py" "$PACKAGED_APP"
"$ROOT_DIR/script/verify_macho_distribution.py" "$PACKAGED_APP"
"$ROOT_DIR/script/verify_macho_closure.py" "$PACKAGED_APP"
./script/verify_packaging.sh

if [[ "${LORVEX_VERIFY_SKIP_PACKAGING:-}" == "1" ]]; then
  echo "verify_all: LORVEX_VERIFY_SKIP_PACKAGING=1 — skipping the GUI smoke launch and the signing/notarize path (no credentials on this runner)."
else
  APP_PIDS_BEFORE_SMOKE_LAUNCH="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
  ./script/build_and_run.sh --verify
  record_launched_app_pids "$APP_PIDS_BEFORE_SMOKE_LAUNCH"
  ./script/archive_local.sh
  ./script/notarize_archive.sh --preflight
fi
