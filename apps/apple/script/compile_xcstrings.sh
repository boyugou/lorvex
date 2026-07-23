#!/usr/bin/env bash
# Compile String Catalogs (`*.xcstrings`) into per-language `.lproj/*.strings`
# (plus `.stringsdict` for plurals) inside each SwiftPM resource bundle.
#
# `swift build` copies the raw `*.xcstrings` into a target's `<Package>_<Target>.bundle`
# but never compiles it, so the compiled string tables the loader needs are absent:
# `Bundle.module`'s `.lproj` lookup returns nil, `NSLocalizedString`/`String(localized:)`
# fall back to the English source for every locale, and plural formats render the raw
# `%lld`. `xcstringstool` (shipped with Xcode) emits those tables. This step must run
# AFTER the `swift build` that produces the bundles, so the bundle directories it
# writes into already exist.
#
# Usage:
#   compile_xcstrings.sh [--best-effort] [ROOT ...]
#
# With no ROOT, every `*.xcstrings` under the SwiftPM debug build products
# (`<apple>/.build/**/debug/**/*.bundle`) is compiled in place — the set the
# LorvexAppleTests localization suite loads. With one or more ROOTs, every
# `*.xcstrings` found beneath each ROOT is compiled instead (build_and_run.sh passes
# the staged `.app` Resources directory and the SwiftPM `--show-bin-path` directory,
# which may be a release build).
#
# Strict by default: a missing `xcstringstool` or zero catalogs found is a hard error,
# because verify_all.sh's `swift test` depends on the compiled tables and must not
# silently skip. `--best-effort` downgrades both prerequisite failures to a non-fatal
# warning (exit 0) for build_and_run.sh's packaging side-path, whose established
# contract is to keep going — shipping English-only — when the toolchain cannot
# compile catalogs. A genuine compile failure on a present tool is always fatal.
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

if ! XCSTRINGSTOOL="$(xcrun --find xcstringstool 2>/dev/null)"; then
  fail_or_warn "xcstringstool not found (ships with Xcode) — String Catalogs were not compiled; every locale falls back to the English source."
fi

catalogs=()
if [[ "${#ROOTS[@]}" -eq 0 ]]; then
  while IFS= read -r catalog; do
    catalogs+=("$catalog")
  done < <(find "$ROOT_DIR/.build" -path '*debug*' -name '*.xcstrings' 2>/dev/null)
else
  for root in "${ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r catalog; do
      catalogs+=("$catalog")
    done < <(find "$root" -name '*.xcstrings')
  done
fi

if [[ "${#catalogs[@]}" -eq 0 ]]; then
  fail_or_warn "no *.xcstrings catalogs found under ${ROOTS[*]:-$ROOT_DIR/.build} — run the SwiftPM build first so the resource bundles exist."
fi

for catalog in "${catalogs[@]}"; do
  echo "==> Compiling localizations: ${catalog#"$ROOT_DIR/"}"
  "$XCSTRINGSTOOL" compile "$catalog" --output-directory "$(dirname "$catalog")"
done
