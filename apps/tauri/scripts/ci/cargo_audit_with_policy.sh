#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Cargo.lock path>" >&2
  exit 2
fi

lockfile=$1

# This list mirrors deny.toml [advisories].ignore. cargo-audit does not read
# deny.toml, so CI passes the same accepted advisory ledger as explicit
# --ignore flags while still running with --deny warnings.
accepted_advisories=(
  RUSTSEC-2024-0370
  RUSTSEC-2024-0411
  RUSTSEC-2024-0412
  RUSTSEC-2024-0413
  RUSTSEC-2024-0415
  RUSTSEC-2024-0416
  RUSTSEC-2024-0418
  RUSTSEC-2024-0419
  RUSTSEC-2024-0420
  RUSTSEC-2024-0429
  RUSTSEC-2025-0075
  RUSTSEC-2025-0080
  RUSTSEC-2025-0081
  RUSTSEC-2025-0098
  RUSTSEC-2025-0100
)

ignore_args=()
for advisory in "${accepted_advisories[@]}"; do
  ignore_args+=(--ignore "${advisory}")
done

cargo audit --deny warnings "${ignore_args[@]}" --file "${lockfile}"
