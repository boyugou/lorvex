#!/usr/bin/env bash
set -euo pipefail

# Build the Lorvex CLI binary in release mode.

usage() {
    cat <<'USAGE'
Usage: bash scripts/build_cli.sh [options]

Builds the Lorvex CLI (lorvex-cli) binary in release mode.

Options:
  --target <triple>   Cross-compile for the given Rust target triple
                      (e.g. aarch64-apple-darwin, x86_64-unknown-linux-gnu).
                      Omit to build for the current platform.
  -h, --help          Show this help and exit.

Examples:
  bash scripts/build_cli.sh
  bash scripts/build_cli.sh --target aarch64-apple-darwin
USAGE
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Audit #2931-L2: collect cargo target args in an array so `--target
# <triple>` is forwarded to cargo as two distinct argv entries even
# when the triple contains shell metacharacters. Using a string
# (`TARGET_FLAG="--target $2"`) plus an unquoted `$TARGET_FLAG`
# expansion relied on word-splitting and tripped shellcheck SC2086.
TARGET_ARGS=()
TARGET_TRIPLE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_ARGS=("--target" "$2")
            TARGET_TRIPLE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "Building Lorvex CLI (release)..."
# Audit #2312: `--locked` refuses any Cargo.lock drift, so a fresh
# registry cache can't silently pull newer patch versions than what
# the repo ships. This is the CLI that users install via signed
# builds; reproducibility matters.
cargo build --release --locked --manifest-path "$REPO_ROOT/lorvex-cli/Cargo.toml" "${TARGET_ARGS[@]}"

# Determine output path
if [ -n "$TARGET_TRIPLE" ]; then
    BIN_PATH="$REPO_ROOT/target/$TARGET_TRIPLE/release/lorvex"
else
    BIN_PATH="$REPO_ROOT/target/release/lorvex"
fi

if [ -f "$BIN_PATH" ]; then
    SIZE=$(du -h "$BIN_PATH" | awk '{print $1}')
    echo ""
    echo "Build complete:"
    echo "  Binary: $BIN_PATH"
    echo "  Size:   $SIZE"
    echo ""
    echo "To install locally:"
    echo "  cp $BIN_PATH /usr/local/bin/lorvex"
    echo ""
    echo "To set up MCP for Claude Code:"
    echo "  $BIN_PATH mcp install --for claude-code"
elif [ -f "${BIN_PATH}.exe" ]; then
    SIZE=$(du -h "${BIN_PATH}.exe" | awk '{print $1}')
    echo ""
    echo "Build complete:"
    echo "  Binary: ${BIN_PATH}.exe"
    echo "  Size:   $SIZE"
else
    echo "Warning: expected binary not found at $BIN_PATH" >&2
    exit 1
fi
