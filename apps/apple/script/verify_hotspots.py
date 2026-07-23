#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]

# Guardrail against god-files, not a nudge toward fragmentation: a cohesive unit
# (an apply pipeline, a coordinator, a service extension) legitimately runs
# 400-600 lines in this data/sync-heavy, verbose-by-design Swift codebase.
# Firing must be a reliable signal that a file stopped being one cohesive
# concern, not a false alarm on a naturally-large one. A false positive here
# actively corrupts code (bad splits, trimmed comments, widened access); a false
# negative only permits human-catchable latent debt -- so err high. 800 sits
# above this codebase's cohesive-file tail (~400-700) and below the ~1000-line
# 'definitely a god-file' line (cf. SwiftLint error=1000), catching real monsters.
SWIFT_SOURCE_MAX_LINES = 800

# Both Swift package roots this gate guards: the app-layer targets and the
# on-disk pure-Swift core. Scanning only the app root while claiming to cover
# every Swift target would let a core god-file grow unseen.
SWIFT_SOURCES_ROOTS = [ROOT / "Sources", ROOT / "core" / "Sources"]

# Cohesive core files that predate this gate's core coverage and legitimately run
# over the cap as single concerns. CLAUDE.md forbids splitting a cohesive file
# just to satisfy the guardrail, so these are GRANDFATHERED at a ceiling just
# above their current size: they may not grow into worse god-files, and a genuine
# semantic split (Habits.swift is the strongest candidate) stays a separately
# reviewed decision rather than a mechanical one this gate forces. Keyed by path
# relative to the app package root (ROOT), matching the failure-message paths.
GRANDFATHERED_MAX_LINES = {
    "core/Sources/LorvexDomain/Habits.swift": 1000,
    "core/Sources/LorvexSync/ApplyTask.swift": 850,
    "core/Sources/LorvexSync/PendingInboxDrain.swift": 850,
}


def line_count(path: Path) -> int:
    return path.read_text(encoding="utf-8").count("\n") + 1


def swift_source_roots(sources_root: Path) -> list[Path]:
    if not sources_root.exists():
        return []
    return sorted(path for path in sources_root.iterdir() if path.is_dir())


def hotspot_failures(
    *,
    root: Path = ROOT,
    sources_roots: list[Path] = SWIFT_SOURCES_ROOTS,
) -> list[str]:
    failures: list[str] = []

    for sources_root in sources_roots:
        for source_root in swift_source_roots(sources_root):
            for path in sorted(source_root.rglob("*.swift")):
                rel = str(path.relative_to(root))
                cap = GRANDFATHERED_MAX_LINES.get(rel, SWIFT_SOURCE_MAX_LINES)
                lines = line_count(path)
                if lines > cap:
                    note = (
                        "Split state, handlers, or subviews into focused files."
                        if rel not in GRANDFATHERED_MAX_LINES
                        else "This grandfathered core file grew past its ceiling; split it now."
                    )
                    failures.append(f"{rel} has {lines} lines; cap is {cap}. {note}")

    return failures


def main() -> int:
    failures = hotspot_failures()

    if failures:
        print("Hotspot verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        "Hotspot verification passed: "
        f"every app and core Swift source target <= {SWIFT_SOURCE_MAX_LINES} lines "
        f"({len(GRANDFATHERED_MAX_LINES)} cohesive core files grandfathered at a bounded ceiling)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
