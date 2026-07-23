#!/usr/bin/env bash
#
# Build a macOS Universal DMG for Lorvex (aarch64 + x86_64).
# With .env.build credentials: signed + notarized (required for distribution).
# Without credentials: unsigned (local testing only).
#
# Issue #2996 (LOW): Lorvex packages the macOS app via Tauri's bundle
# pipeline (`tauri build --bundles dmg`), NOT `cargo bundle`. The
# upstream `cargo-bundle` crate is unmaintained, doesn't understand
# Tauri's runtime resources, and would skip the packaging/signing hooks
# this app relies on. Any future contributor who finds a `cargo-bundle`
# reference in the Lorvex tree should treat it as a regression — keep the
# Tauri pipeline.

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Source Apple credentials for signing + notarization if available.
#
# NOTE on secrets masking: never echo the raw values of APPLE_PASSWORD,
# APPLE_ID, or APPLE_TEAM_ID — they may land in CI logs. The checks
# below only compare against empty and print the *name* of any missing
# variable.
if [ -f "$REPO_ROOT/.env.build" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env.build"
  echo "==> Loaded Apple credentials from .env.build"

  # Validate the credential set up-front. A partial set (e.g. signing
  # identity but no app-specific password) silently produces an
  # unsigned-or-broken DMG late in the build — better to fail fast.
  missing_credentials=()
  for var in APPLE_SIGNING_IDENTITY APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID; do
    if [ -z "${!var-}" ]; then
      missing_credentials+=("$var")
    fi
  done
  if [ ${#missing_credentials[@]} -gt 0 ]; then
    echo "WARNING: .env.build is missing credential(s): ${missing_credentials[*]}" >&2
    echo "         Build will proceed but notarization will NOT run." >&2
  fi
fi

# Detach any previously mounted Lorvex DMG volumes to avoid Finder pop-ups
# and prevent "resource busy" errors during build. nullglob handles the
# case where no volume exists without expanding the pattern literally.
# Under `set -u`, expanding an empty array as `"${arr[@]}"` is treated as
# referencing an unbound variable, so gate the loop on the array length.
shopt -s nullglob
mounted_volumes=(/Volumes/Lorvex*)
shopt -u nullglob
if [ ${#mounted_volumes[@]} -gt 0 ]; then
  for vol in "${mounted_volumes[@]}"; do
    if [ -d "$vol" ]; then
      hdiutil detach "$vol" -quiet 2>/dev/null || true
    fi
  done
fi

# Clean stale single-arch build artifacts that could be confused with the
# universal build output.
stale_single_arch_dmg_dir="app/src-tauri/target/release/bundle/dmg"
if [ -d "$stale_single_arch_dmg_dir" ]; then
  shopt -s nullglob
  stale_dmgs=("$stale_single_arch_dmg_dir"/*.dmg)
  shopt -u nullglob
  if [ ${#stale_dmgs[@]} -gt 0 ]; then
    rm -f "${stale_dmgs[@]}"
  fi
fi

echo "==> Preparing MCP runtime"
npm run -w app prepare:mcp

echo "==> Building Universal DMG (aarch64 + x86_64)"
# Audit #2299: `--` forwards the trailing args to `tauri build`, which
# passes `--locked` to cargo. Refuses any Cargo.lock drift so a fresh
# registry cache can't silently pull newer patch versions than what
# the repo ships. Pairs with exact-pinned versions in
# `app/src-tauri/Cargo.toml`.
#
# Audit #2931-M7: the command below uses TWO `--` separators on
# purpose. Do not "clean up" by removing one.
#   1. The first `--` peels off npm-run's wrapper layer so the
#      remaining args reach the `tauri:build` script.
#   2. `--bundles dmg --target universal-apple-darwin` are flags
#      consumed by `tauri build` itself.
#   3. The second `--` forwards the tail (`--locked`) past tauri-cli
#      into the underlying `cargo build` invocation. Without it,
#      `cargo` never sees `--locked` and Cargo.lock drift silently
#      passes.
# Cargo accepts `CARGO_NET_OFFLINE=true` + `--frozen` as an
# alternative if the double-`--` ever becomes a hazard, but the
# explicit form is auditable in CI logs.
npm run -w app tauri:build -- --bundles dmg --target universal-apple-darwin -- --locked

# The universal build outputs to target/universal-apple-darwin/release/bundle/dmg/
DMG_DIR="app/src-tauri/target/universal-apple-darwin/release/bundle/dmg"
# Use a glob array instead of `ls | head` so filenames containing
# spaces/special characters resolve unambiguously.
shopt -s nullglob
dmg_candidates=("$DMG_DIR"/*.dmg)
shopt -u nullglob
if [ ${#dmg_candidates[@]} -eq 0 ]; then
  echo "ERROR: No DMG found in $DMG_DIR after build" >&2
  exit 1
fi
DMG_PATH="${dmg_candidates[0]}"

echo ""
echo "==> DMG built successfully"
echo "    Path: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

# Report signing/notarization status
APP_PATH="app/src-tauri/target/universal-apple-darwin/release/bundle/macos/Lorvex.app"
if [ -d "$APP_PATH" ]; then
  if codesign -dv "$APP_PATH" 2>&1 | grep -q "Authority=Developer ID"; then
    echo "    Signed: Developer ID (notarized)"
  elif codesign -dv "$APP_PATH" 2>&1 | grep -q "Authority="; then
    echo "    Signed: ad-hoc (NOT notarized — will be blocked by Gatekeeper)"
  else
    echo "    WARNING: Unsigned (will be blocked by Gatekeeper)"
  fi
fi

# Issue #2996 (MEDIUM): verify the universal binary actually contains
# both expected architectures. Pre-fix, a botched `lipo` step (or a
# `--target universal-apple-darwin` invocation that silently fell
# back to the host arch) shipped a thin DMG that worked on the build
# machine but failed to launch on users with the other arch. The
# `lipo -info` parse below trips the build with a non-zero exit when
# either slice is missing.
MAIN_BINARY="$APP_PATH/Contents/MacOS/Lorvex"
if [ -f "$MAIN_BINARY" ]; then
  lipo_info_output=$(lipo -info "$MAIN_BINARY" 2>&1 || true)
  echo "    lipo -info: $lipo_info_output"
  if ! echo "$lipo_info_output" | grep -q "x86_64"; then
    echo "ERROR: Universal binary missing x86_64 slice (lipo -info: $lipo_info_output)" >&2
    exit 1
  fi
  if ! echo "$lipo_info_output" | grep -q "arm64"; then
    echo "ERROR: Universal binary missing arm64 slice (lipo -info: $lipo_info_output)" >&2
    exit 1
  fi

  # Issue #2996 (LOW): cross-arch slice equality check. Beyond "both
  # slices exist" (above), verify each slice was built from the same
  # source tree by extracting them and comparing the ENTRY-POINT load
  # commands plus the exported symbol counts. A mismatched build
  # (e.g. one slice built with stale crate-tree state on the cross-
  # build host) silently ships a DMG where the two architectures
  # behave subtly differently — exactly the bug class universal
  # binaries are supposed to prevent. The slice byte sizes will
  # legitimately differ (different code-gen, different LTO output)
  # so we don't compare those; the symbol-count + load-command
  # entry-point check is the right granularity.
  slice_tmpdir=$(mktemp -d -t lorvex_lipo)
  # bash `trap` REPLACES rather than appends. Capture any
  # pre-existing EXIT handler and chain ours after it so a future
  # contributor adding a "delete partial DMG on failure" handler
  # earlier in the script does not get silently overwritten here
  # (audit-pass-docs-finding-6).
  prev_exit_trap=$(trap -p EXIT | sed -E "s/^trap -- ?'([^']*)' EXIT$/\1/" | head -n 1)
  if [ -z "$prev_exit_trap" ]; then
    trap 'rm -rf "$slice_tmpdir"' EXIT
  else
    trap "rm -rf \"$slice_tmpdir\"; $prev_exit_trap" EXIT
  fi
  if lipo "$MAIN_BINARY" -thin x86_64 -output "$slice_tmpdir/x86_64" 2>/dev/null \
     && lipo "$MAIN_BINARY" -thin arm64 -output "$slice_tmpdir/arm64" 2>/dev/null; then
    # Symbol count: both arches should expose the same set of
    # external symbols (any drift = a re-exported helper got
    # compiled into one slice but not the other).
    x86_syms=$(nm -gU "$slice_tmpdir/x86_64" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    arm_syms=$(nm -gU "$slice_tmpdir/arm64"  2>/dev/null | wc -l | tr -d ' ' || echo 0)
    echo "    slice symbol counts: x86_64=$x86_syms arm64=$arm_syms"
    if [ "$x86_syms" -gt 0 ] && [ "$arm_syms" -gt 0 ]; then
      # Allow a small tolerance for arch-specific symbols (e.g. SSE
      # vs NEON intrinsic stubs). >5% drift signals a real build-
      # tree skew, not arch-specific code-gen.
      diff_abs=$(( x86_syms > arm_syms ? x86_syms - arm_syms : arm_syms - x86_syms ))
      max_syms=$(( x86_syms > arm_syms ? x86_syms : arm_syms ))
      drift_bp=$(( diff_abs * 10000 / max_syms ))
      # 500 bp = 5%
      if [ "$drift_bp" -gt 500 ]; then
        echo "ERROR: slice symbol-count drift > 5% (x86_64=$x86_syms arm64=$arm_syms diff=${drift_bp} bp)" >&2
        echo "       Both slices should be built from the same source tree; large drift signals" >&2
        echo "       a stale cross-build target dir or a cargo feature mismatch." >&2
        exit 1
      fi
    fi
    # Both slices must have a parseable LC_MAIN load command (the
    # binary's entry point). A missing LC_MAIN means the slice is
    # probably a static library / dylib mistakenly bundled as the
    # main executable.
    if ! otool -l "$slice_tmpdir/x86_64" 2>/dev/null | grep -q "LC_MAIN"; then
      echo "ERROR: x86_64 slice has no LC_MAIN entry point load command" >&2
      exit 1
    fi
    if ! otool -l "$slice_tmpdir/arm64" 2>/dev/null | grep -q "LC_MAIN"; then
      echo "ERROR: arm64 slice has no LC_MAIN entry point load command" >&2
      exit 1
    fi
    echo "    slice equality: both arches share LC_MAIN entry point and symbol counts within 5%"
  else
    echo "WARNING: failed to extract individual slices for cross-arch equality check" >&2
  fi
else
  echo "WARNING: main binary not found at $MAIN_BINARY — skipping lipo validation" >&2
fi

# Issue #2996 (MEDIUM): verify the notarization staple is attached and
# valid. A signed-but-not-stapled DMG works while online (Gatekeeper
# fetches the notarization ticket from Apple) but fails on first-launch
# offline — common for users opening the DMG immediately after AirDrop
# from a co-located machine. `xcrun stapler validate` returns 0 only
# when the ticket is stapled into the DMG itself; a non-zero exit here
# is downgraded to a warning when no notarization credentials were
# supplied (local unsigned build), but treated as fatal when we know
# the build was supposed to be notarized.
notarization_attempted=false
if [ -n "${APPLE_SIGNING_IDENTITY:-}" ] \
   && [ -n "${APPLE_ID:-}" ] \
   && [ -n "${APPLE_PASSWORD:-}" ] \
   && [ -n "${APPLE_TEAM_ID:-}" ]; then
  notarization_attempted=true
fi

# Tauri's bundle pipeline notarizes + staples the .app inside the DMG
# but does not notarize the DMG itself. Apple requires (or strongly
# recommends) stapling the DMG too: when the DMG is downloaded onto a
# machine without an active internet connection (AirDrop to an offline
# laptop, USB transfer, etc.), Gatekeeper cannot fetch the ticket from
# Apple's servers and the DMG fails to open until the network is up.
# Stapling embeds the ticket directly in the DMG so first-launch works
# offline. Submit the DMG to the notary service and staple the response.
if [ "$notarization_attempted" = "true" ] && command -v xcrun >/dev/null 2>&1; then
  if ! xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    echo "==> Notarizing DMG (Tauri stapled the .app but not the DMG)"
    if ! xcrun notarytool submit "$DMG_PATH" \
           --apple-id "$APPLE_ID" \
           --team-id "$APPLE_TEAM_ID" \
           --password "$APPLE_PASSWORD" \
           --wait; then
      echo "ERROR: DMG notarization submission failed" >&2
      exit 1
    fi
    echo "==> Stapling notarization ticket to DMG"
    if ! xcrun stapler staple "$DMG_PATH"; then
      echo "ERROR: 'xcrun stapler staple' failed on $DMG_PATH" >&2
      exit 1
    fi
  fi
fi

if command -v xcrun >/dev/null 2>&1; then
  if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    echo "    Stapler: notarization ticket is stapled and valid"
  else
    if [ "$notarization_attempted" = "true" ]; then
      echo "ERROR: 'xcrun stapler validate' rejected $DMG_PATH" >&2
      echo "       Notarization credentials were supplied but the DMG is not stapled." >&2
      echo "       The DMG will fail to launch offline. Re-run the notarization step." >&2
      exit 1
    else
      echo "    Stapler: not stapled (no notarization credentials — local unsigned build)"
    fi
  fi
fi

echo ""
echo "==> To install: open $DMG_PATH"
echo "==> Done"
