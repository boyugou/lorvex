#!/usr/bin/env bash
# audit_marker_count.sh — fail when any new `Audit #` reference appears in
# the Rust source tree.
#
# Audit #N rationale markers were a long-running #2931-era
# convention for cross-referencing the audit issue that motivated a
# given comment. #3022 M7 stripped the residual 111 occurrences after
# the convention was deprecated; this guard exists so a future PR cannot
# silently reintroduce them.
#
# We grep both the Rust source tree and the React frontend (TS/TSX
# under `app/src/`). Non-source files (`Cargo.toml`, `scripts/*.sh`)
# intentionally remain unchecked because their audit refs serve a
# different purpose (build-system rationale comments) and stripping
# them is out of scope.
#
# Exit 0 with no output when the tree is clean, 1 otherwise. Stdout
# carries the offending lines so CI logs make the source obvious.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

RUST_ROOTS=(
  lorvex-domain
  lorvex-store
  lorvex-runtime
  lorvex-sync
  lorvex-cli
  mcp-server
  app/src-tauri/src
)

# `grep -r --include` returns 1 when no matches — that's the success path.
#
# #3051 H4 broadened previous capital-only pattern to `[Aa]udit *#`.
# Pass 10 found more variants the lowercase fix still missed: `AUDIT #`
# (all-caps), `Audit-#` (hyphen), `Audit:#` (colon), `Audit\t#` (tab).
# `(?i)` toggles case-insensitive grep -E so we cover ALL caps shapes
# in one pattern, and `[\s\-:]*` allows any whitespace OR hyphen OR
# colon between the word and the `#` — covering every observed form.
RUST_HITS="$(grep -rEn '(^|[^A-Za-z])(audit)[\s\-:]*#' --include='*.rs' -i "${RUST_ROOTS[@]}" 2>/dev/null || true)"
TS_HITS="$(grep -rEn '(^|[^A-Za-z])(audit)[\s\-:]*#' --include='*.ts' --include='*.tsx' -i app/src 2>/dev/null || true)"

HITS="$RUST_HITS"
if [[ -n "$TS_HITS" ]]; then
  HITS="${HITS}${HITS:+$'\n'}${TS_HITS}"
fi

if [[ -n "$HITS" ]]; then
  echo "scripts/verify/audit_marker_count.sh: found source files reintroducing 'Audit #' references." >&2
  echo "These should be stripped — substantive rationale stays, the 'Audit #N' prefix does not (see #3022 M7)." >&2
  echo "$HITS" >&2
  exit 1
fi

exit 0
