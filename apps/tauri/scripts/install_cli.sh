#!/usr/bin/env bash
set -euo pipefail

# Install the Lorvex CLI binary to a local bin directory.

usage() {
    cat <<'USAGE'
Usage: bash scripts/install_cli.sh [options]

Installs the Lorvex CLI (lorvex-cli) to <PREFIX>/bin. Builds it first
if target/release/lorvex is missing.

Options:
  --prefix <path>     Install prefix; the binary lands at
                      <PREFIX>/bin/lorvex. Default: /usr/local
  -h, --help          Show this help and exit.

Examples:
  bash scripts/install_cli.sh
  bash scripts/install_cli.sh --prefix ~/.local
USAGE
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="/usr/local"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
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

INSTALL_DIR="$PREFIX/bin"
BIN_PATH="$REPO_ROOT/target/release/lorvex"

if [ ! -f "$BIN_PATH" ]; then
    echo "Release binary not found. Building first..."
    bash "$REPO_ROOT/scripts/build_cli.sh"
fi

DEST="$INSTALL_DIR/lorvex"
# Audit #2313: skip the copy when the installed binary is byte-
# identical to the freshly-built one. Avoids touching mtime (which
# can trigger filesystem-watcher reloads and macOS code-signing
# re-validation) on every `install_cli.sh` invocation.
if [ -f "$DEST" ] && cmp -s "$BIN_PATH" "$DEST"; then
    echo "Lorvex CLI already up to date at $DEST — skipping copy."
else
    # Warn if a different \`lorvex\` is already on PATH (Homebrew,
    # prior \`cargo install\`, another prefix). Silent downgrade is a
    # footgun when MCP configs point at the other location.
    EXISTING="$(command -v lorvex 2>/dev/null || true)"
    if [ -n "$EXISTING" ] && [ "$EXISTING" != "$DEST" ]; then
        echo "Note: a different 'lorvex' is already on your PATH: $EXISTING"
        echo "      This script will install to $DEST. MCP configs that reference"
        echo "      the other path will need to be re-installed:  lorvex mcp install --for all"
    fi
    echo "Installing Lorvex CLI to $DEST..."
    mkdir -p "$INSTALL_DIR"
    # Audit #2931-M8: prefer `install -m 0755` over `cp` + `chmod`.
    # `install` writes to a temp file and renames atomically — a
    # mid-copy disk-full or SIGINT can't leave a half-written binary
    # at $DEST. The single invocation also collapses the
    # cp-then-chmod race window where another process could exec a
    # not-yet-executable file.
    install -m 0755 "$BIN_PATH" "$DEST"
fi

echo ""
echo "Installed: $INSTALL_DIR/lorvex"
echo ""

# Verify it's on PATH
if command -v lorvex >/dev/null 2>&1; then
    echo "Lorvex CLI is on your PATH."
    # Audit #2321: previously piped a JSON doctor run into `head -1`,
    # which printed a lone `{` — confusing to new users. Use the real
    # `lorvex --version` string.
    VERSION_LINE="$(lorvex --version 2>/dev/null || echo 'lorvex --version failed; run lorvex doctor')"
    echo "  $VERSION_LINE"
else
    echo "Warning: lorvex is not on your PATH."
    echo "  Add this to your shell profile:"
    echo "    export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
echo "Next steps:"
echo "  lorvex setup                          # initialize database"
echo "  lorvex mcp install --for claude-code  # configure MCP for Claude Code"
echo "  lorvex doctor                         # verify installation"
