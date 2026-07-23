#!/usr/bin/env bash
# Wrapper around `node --test scripts/tests/contracts/index.test.mjs`
# that propagates failure counts into the process exit code.
#
# `node --test` in Node 22 has a known regression where the runner can
# emit `# fail N` (N>0) on TAP stdout while still exiting 0, which made
# the `verify:repo-governance` chain silently pass even when 40+
# contract assertions were broken (audit pass 12 follow-up — surfaced
# by the same sweep that caught the IPC-handler-parity false-positive).
# This wrapper:
#   1. captures the runner's TAP output verbatim,
#   2. echoes it through to the user,
#   3. greps for the `# fail [1-9]+` summary line that the TAP-13
#      reporter always emits at the end of a run, and
#   4. exits 1 if any failures are reported, regardless of `node --test`'s
#      own exit code.
#
# `set -euo pipefail` so a node crash (segfault, out-of-memory) still
# fails the wrapper even if the TAP output is empty / truncated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${REPO_ROOT}"

# Capture combined stdout+stderr so the user sees errors thrown during
# import (e.g. a missing fixture) AND the per-test TAP lines.
output="$(node --test scripts/tests/contracts/index.test.mjs 2>&1)" || node_exit=$?
node_exit=${node_exit:-0}

# Echo the runner's full output so failures stay visible in CI logs.
printf '%s\n' "${output}"

# Bubble up node's own non-zero exit (e.g. import-time syntax error)
# before falling through to the TAP-summary check.
if [[ "${node_exit}" -ne 0 ]]; then
  echo "[run_contract_verifiers] node --test exited ${node_exit}" >&2
  exit "${node_exit}"
fi

# `node --test` in Node 22 can report failures on TAP stdout while
# still exiting 0; treat any non-zero `# fail N` count as a hard fail.
if grep -qE '^# fail [1-9][0-9]*$' <<<"${output}"; then
  fail_line="$(grep -E '^# fail [1-9][0-9]*$' <<<"${output}" | head -n1)"
  echo "" >&2
  echo "[run_contract_verifiers] contract-verifier failure count is non-zero (\"${fail_line}\")." >&2
  echo "[run_contract_verifiers] see TAP output above for the specific assertions; \`node --test\` 22 silently exits 0 on test failure, this wrapper escalates." >&2
  exit 1
fi
