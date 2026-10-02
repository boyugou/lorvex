#!/usr/bin/env bash
# Make sure every SwiftPM resource bundle holds compiled string tables: the
# per-language `.lproj/*.strings` (plus `.stringsdict` for plurals) that
# `Bundle.module` lookups, `String(localized:)`, and plural formats read.
#
# What `swift build` leaves in a bundle depends on the SwiftPM build system. Swift
# Build (products under `.build/out/Products/<Configuration>`) compiles each String
# Catalog into those tables itself. The native build system (products under
# `.build/<triple>/<configuration>`) copies the raw `*.xcstrings` and compiles
# nothing, so every lookup falls back to the English source and plurals render the
# raw `%lld`. This script compiles every raw catalog it finds with `xcstringstool`
# (shipped with Xcode) and accepts bundles the build already compiled, so it is
# correct under both. It must run AFTER the `swift build` that produces the bundles.
#
# Usage:
#   compile_xcstrings.sh [--best-effort] [ROOT ...]
#
# With no ROOT, the active build system's debug products (`swift build
# --show-bin-path`) are checked: the bundles the LorvexAppleTests localization suite
# loads. With one or more ROOTs, everything beneath each ROOT is checked instead
# (build_and_run.sh passes the staged `.app` Resources directory and the SwiftPM
# `--show-bin-path` directory, which may be a release build).
#
# Strict by default: finding neither a raw catalog nor a compiled table (the build
# has not run), or a raw catalog with no `xcstringstool` to compile it, is a hard
# error, because verify_all.sh's `swift test` depends on the compiled tables and
# must not silently skip. `--best-effort` downgrades both to a non-fatal warning
# (exit 0) for build_and_run.sh's packaging side-path, whose established contract
# is to keep going — shipping English-only — when the toolchain cannot compile
# catalogs. A genuine compile failure on a present tool is always fatal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BEST_EFFORT=0
ROOTS=()
for arg in "$@"; do
  case "$arg" in
    --best-effort) BEST_EFFORT=1 ;;
    -*)
      echo "compile_xcstrings: unknown option: $arg" >&2
      exit 2
      ;;
    *) ROOTS+=("$arg") ;;
  esac
done

fail_or_warn() {
  if [[ "$BEST_EFFORT" -eq 1 ]]; then
    echo "WARNING: $1" >&2
    exit 0
  fi
  echo "compile_xcstrings: $1" >&2
  exit 1
}

if [[ "${#ROOTS[@]}" -eq 0 ]]; then
  if ! BIN_DIR="$(cd "$ROOT_DIR" && swift build --show-bin-path 2>/dev/null)"; then
    fail_or_warn "could not locate the SwiftPM build products (swift build --show-bin-path failed)."
  fi
  ROOTS=("$BIN_DIR")
fi

catalogs=()
compiled_tables=0
for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r catalog; do
    catalogs+=("$catalog")
  done < <(find "$root" -name '*.xcstrings')
  compiled_tables=$((compiled_tables + $(find "$root" -path '*.lproj/Localizable.strings' | wc -l)))
done

if [[ "${#catalogs[@]}" -eq 0 ]]; then
  if [[ "$compiled_tables" -gt 0 ]]; then
    echo "==> String Catalogs already compiled by the build ($compiled_tables string tables under ${ROOTS[*]})"
    exit 0
  fi
  fail_or_warn "no String Catalogs and no compiled string tables under ${ROOTS[*]} — run the SwiftPM build first so the resource bundles exist."
fi

if ! XCSTRINGSTOOL="$(xcrun --find xcstringstool 2>/dev/null)"; then
  fail_or_warn "xcstringstool not found (ships with Xcode) — String Catalogs were not compiled; every locale falls back to the English source."
fi

for catalog in "${catalogs[@]}"; do
  echo "==> Compiling localizations: ${catalog#"$ROOT_DIR/"}"
  "$XCSTRINGSTOOL" compile "$catalog" --output-directory "$(dirname "$catalog")"
done
