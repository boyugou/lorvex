#!/usr/bin/env python3
"""Guard against SQLite ordered-set aggregate syntax that requires SQLite >= 3.44.

`GROUP_CONCAT(x ORDER BY y)` and `json_group_array(x ORDER BY y)` (the ORDER BY
*inside* the aggregate's argument list) are only accepted from SQLite 3.44.0
(Nov 2023). The app links the system SQLite, which is 3.43.2 on current macOS
(15.x) and iOS 17.0-17.3 — so this syntax makes a FRESH database fail at schema
load and at the first task insert (a launch blocker that simulators with newer
SQLite, plus persisted app-group DBs, completely hide).

Portable form: aggregate over an ordered subquery —
  json_group_array(x) FROM (SELECT x ... ORDER BY y)

This gate scans the shared schema (all parity copies), the pure-Swift core, and
the app sources/tests for the non-portable inline form and fails if any remain.
Run on a SQLite < 3.44 host, `cd core && swift test` is the live proof.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGETS = [
    ROOT / "schema",
    ROOT / "apps/apple/Sources",
    ROOT / "apps/apple/core/Sources",
    ROOT / "apps/apple/core/Tests",
]
# Start of an ordered-set aggregate call, up to and including its opening paren.
AGGREGATE_OPEN = re.compile(
    r"\b(?:json_group_array|json_group_object|group_concat)\s*\(",
    re.IGNORECASE,
)
ORDER_BY = re.compile(r"\bORDER\s+BY\b", re.IGNORECASE)
SCAN_SUFFIXES = {".sql", ".swift"}


def _skip_string_literal(text: str, index: int, quote: str) -> int:
    """Return the index just past a SQL quoted literal that opens at ``index``.

    ``index`` points at the opening quote. Doubled quotes (``''`` / ``""``) are
    SQL's in-literal escape, so they are consumed as content, not a close.
    """
    length = len(text)
    cursor = index + 1
    while cursor < length:
        if text[cursor] == quote:
            if cursor + 1 < length and text[cursor + 1] == quote:
                cursor += 2
                continue
            return cursor + 1
        cursor += 1
    return length


def _inline_ordered_aggregate_hits(text: str) -> list[tuple[int, str]]:
    """Find ordered-set aggregates that carry an ``ORDER BY`` directly in their
    argument list — the SQLite >= 3.44 syntax that breaks older engines.

    The scan is paren-balanced and skips quoted literals, so it detects the
    nested-paren inline form ``json_group_array(json_object('k', v) ORDER BY y)``
    (the common shape a flat ``[^()]*`` scan misses) while ignoring the portable
    form ``json_group_array(x) FROM (SELECT x ... ORDER BY y)``, whose ``ORDER
    BY`` lives in a sibling subquery outside the aggregate's own parentheses.

    Returns ``(offset, snippet)`` pairs, where ``offset`` is the aggregate call's
    start and ``snippet`` is the call text up to the offending ``ORDER BY``.
    """
    hits: list[tuple[int, str]] = []
    length = len(text)
    for match in AGGREGATE_OPEN.finditer(text):
        depth = 1  # we are already inside the aggregate's opening paren
        cursor = match.end()
        while cursor < length and depth > 0:
            char = text[cursor]
            if char in "'\"":
                cursor = _skip_string_literal(text, cursor, char)
                continue
            if char == "(":
                depth += 1
                cursor += 1
                continue
            if char == ")":
                depth -= 1
                cursor += 1
                continue
            if depth == 1:
                order_by = ORDER_BY.match(text, cursor)
                if order_by:
                    snippet = " ".join(text[match.start():order_by.end()].split())
                    hits.append((match.start(), snippet))
                    break
            cursor += 1
    return hits


def main() -> int:
    hits = []
    for base in TARGETS:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix not in SCAN_SUFFIXES or not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for offset, snippet in _inline_ordered_aggregate_hits(text):
                line = text.count("\n", 0, offset) + 1
                hits.append(f"{path.relative_to(ROOT)}:{line}: {snippet}")
    if hits:
        print("SQLite portability check FAILED — inline ordered-set aggregate "
              "(requires SQLite >= 3.44; breaks fresh installs on iOS 17.0-17.3 / "
              "current macOS). Rewrite as an aggregate over an ORDER BY subquery:")
        for h in hits:
            print("  " + h)
        return 1
    print("SQLite portability check passed: no inline ordered-set aggregates "
          "(GROUP_CONCAT/json_group_array(... ORDER BY ...)).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
