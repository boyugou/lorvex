#!/usr/bin/env python3
"""Verify complete core service implementations do not rely on unsupported defaults."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICES_DIR = ROOT / "Sources" / "LorvexCore" / "Services"
FULL_SERVICE_PREFIXES = ("SwiftLorvexCoreService",)
REAL_DEFAULT_IMPLEMENTATIONS = {"exportData", "exportDataForAI"}


def swift_func_names(source: str) -> set[str]:
    return set(re.findall(r"\bfunc\s+(\w+)\s*\(", source))


def protocol_func_names(source: str) -> set[str]:
    """Return function requirements declared inside protocol bodies only."""
    methods: set[str] = set()
    for match in re.finditer(r"\bprotocol\s+\w+[^\{]*\{", source):
        body_start = match.end()
        depth = 1
        cursor = body_start
        while cursor < len(source) and depth:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
            cursor += 1
        if depth == 0:
            methods.update(swift_func_names(source[body_start : cursor - 1]))
    return methods


def read_sources(paths: list[Path]) -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


def protocol_files(services_dir: Path = SERVICES_DIR) -> list[Path]:
    return sorted(
        path
        for path in services_dir.glob("Lorvex*Servicing.swift")
        if "+Defaults" not in path.name and path.name != "LorvexCoreServicing.swift"
    )


def unsupported_default_methods(services_dir: Path = SERVICES_DIR) -> set[str]:
    methods: set[str] = set()
    for path in services_dir.glob("Lorvex*Servicing+Defaults.swift"):
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(
            r"\bfunc\s+(\w+)\s*\([^{}]*\{[^{}]*unsupportedServiceOperation",
            source,
            flags=re.DOTALL,
        ):
            methods.add(match.group(1))
    return methods


def implementation_files(prefix: str, services_dir: Path = SERVICES_DIR) -> list[Path]:
    return sorted(services_dir.glob(f"{prefix}*.swift"))


def service_coverage_failures(services_dir: Path = SERVICES_DIR) -> list[str]:
    failures: list[str] = []
    required = protocol_func_names(read_sources(protocol_files(services_dir)))
    required -= REAL_DEFAULT_IMPLEMENTATIONS
    unsupported_defaults = unsupported_default_methods(services_dir)

    for prefix in FULL_SERVICE_PREFIXES:
        files = implementation_files(prefix, services_dir)
        implemented = swift_func_names(read_sources(files))
        missing_required = sorted(required - implemented)
        missing_unsupported_overrides = sorted(unsupported_defaults - implemented)

        if missing_required:
            failures.append(
                f"{prefix} is missing protocol method implementation(s): {missing_required}"
            )
        if missing_unsupported_overrides:
            failures.append(
                f"{prefix} would rely on unsupported default service operation(s): "
                f"{missing_unsupported_overrides}"
            )

    return failures


def main() -> int:
    failures = service_coverage_failures()
    if failures:
        print("Core service coverage verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Core service coverage verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
