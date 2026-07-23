#!/usr/bin/env bash
set -euo pipefail

echo "=== Dev Session Preflight ==="
echo ""

# Check for uncommitted changes
if ! git diff --quiet HEAD 2>/dev/null; then
  echo "⚠ UNCOMMITTED CHANGES:"
  git status --short
  echo ""
fi

# Fetch latest
echo "--- Fetching origin ---"
git fetch origin --prune
echo ""

# Show recent commits on main
echo "--- Recent commits (origin/main) ---"
git log --oneline --decorate origin/main -n 12
echo ""

# Show local vs remote divergence
LOCAL=$(git rev-parse HEAD 2>/dev/null)
REMOTE=$(git rev-parse origin/main 2>/dev/null)
if [ "$LOCAL" != "$REMOTE" ]; then
  AHEAD=$(git rev-list origin/main..HEAD --count 2>/dev/null || echo "?")
  BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "?")
  echo "⚠ Local is ${AHEAD} ahead, ${BEHIND} behind origin/main"
  echo ""
fi

# Show open issues
echo "--- Open Issues ---"
# Audit #2931-M9: capture stderr so we can distinguish "gh is missing"
# from "gh is installed but auth/network is broken". The previous
# `2>/dev/null || echo "(gh CLI not available)"` swallowed every
# failure under the same misleading message and a user with a stale
# token would chase the wrong root cause.
GH_ERR_FILE="$(mktemp -t gh-preflight-stderr.XXXXXX)"
trap 'rm -f "$GH_ERR_FILE"' EXIT
if ! gh issue list --state open --limit 20 2>"$GH_ERR_FILE"; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "(gh CLI not available — install via https://cli.github.com)"
  else
    echo "(gh CLI failed; replaying error output below)"
    cat "$GH_ERR_FILE" >&2
  fi
fi
echo ""

# Show open PRs
echo "--- Open PRs ---"
if ! gh pr list --state open --limit 10 2>"$GH_ERR_FILE"; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "(gh CLI not available — install via https://cli.github.com)"
  else
    echo "(gh CLI failed; replaying error output below)"
    cat "$GH_ERR_FILE" >&2
  fi
fi
echo ""

echo "=== Preflight complete ==="
