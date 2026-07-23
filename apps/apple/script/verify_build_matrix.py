#!/usr/bin/env python3
"""Verify the full local gate builds every Apple executable product."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from metadata_env import load_metadata


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATH = ROOT / "Package.swift"
VERIFY_ALL_PATH = ROOT / "script" / "verify_all.sh"
BUILD_AND_RUN_PATH = ROOT / "script" / "build_and_run.sh"
ARCHIVE_LOCAL_PATH = ROOT / "script" / "archive_local.sh"
ALLOWED_UNBUILT_EXECUTABLE_PRODUCTS: set[str] = set()
# The leading "./" requires the *executed* invocation: a bare
# `script/xcodegen_dependency_check.py` (the form used only in the py_compile
# argument list) does not satisfy it, so the check can't pass while the gate is
# merely compiled but never run.
REQUIRED_VERIFY_ALL_COMMANDS = (
    "./script/verify_packaging.sh",
    "./script/xcodegen_dependency_check.py",
)


def swiftpm_executable_products(package_source: str) -> set[str]:
    return set(re.findall(r'\.executable\s*\(\s*name:\s*"([^"]+)"', package_source))


def verify_all_build_products(script_source: str, metadata: dict[str, str]) -> set[str]:
    products: set[str] = set()
    for raw in re.findall(r"swift build --product ([^\n]+)", script_source):
        token = raw.strip().split()[0]
        if token.startswith('"$') and token.endswith('"'):
            variable_name = token[2:-1]
            if variable_name in metadata:
                products.add(metadata[variable_name])
        elif token.startswith("$"):
            variable_name = token[1:]
            if variable_name in metadata:
                products.add(metadata[variable_name])
        else:
            products.add(token.strip('"'))
    return products


def global_pkill_failures(script_name: str, script_source: str) -> list[str]:
    """Reject a global ``pkill -x <name>`` in a script that launches the app.

    ``pkill -x <name>`` kills *every* process with that name on the machine —
    including a real, already-running instance the developer started themselves
    (e.g. their own daily-use Lorvex.app), not just what this run spawned. A
    script that launches the app must instead track and reap only the PID(s) it
    itself launches. Comment lines are excluded from the scan so documenting the
    unsafe pattern in prose (to explain why the code avoids it) cannot trip it.
    """
    code_source = "\n".join(
        line for line in script_source.splitlines() if not line.strip().startswith("#")
    )
    if re.search(r"pkill\s+-x\b", code_source):
        return [
            f"{script_name} must not use a global `pkill -x` for cleanup; it can "
            "kill an already-running instance of the app that this run did not "
            "launch. Track and kill only the PID(s) this run itself spawns."
        ]
    return []


def verify_all_launch_cleanup_failures(script_source: str) -> list[str]:
    """Cleanup must kill only the PID(s) this gate run itself launches.

    A global ``pkill -x <name>`` kills *every* process with that name on the
    machine, including a real, already-running instance the developer
    started themselves (e.g. their own daily-use Lorvex.app) — not just
    whatever this gate run spawned. The only process ``verify_all.sh`` ever
    launches is the app started by ``build_and_run.sh --verify``'s smoke
    check (``$APP_NAME``); every other build-matrix product here is only
    ever ``swift build``-compiled, never executed, so it needs no
    launch-cleanup of its own — dropping it is correct, not a gap.

    Returns failure messages; an empty list means the cleanup mechanism is
    both safe (no blanket ``pkill -x``) and still covers the one process it
    must (tracks ``$APP_NAME``'s PID via ``pgrep`` and reaps it with a bare
    ``kill``). Comment lines are excluded from the scan, so documenting the
    unsafe pattern in prose (to explain why the code avoids it) cannot
    itself trip the check.
    """
    code_source = "\n".join(
        line for line in script_source.splitlines() if not line.strip().startswith("#")
    )

    failures: list[str] = global_pkill_failures("verify_all.sh", script_source)
    if 'pgrep -x "$APP_NAME"' not in code_source:
        failures.append(
            'verify_all.sh no longer tracks $APP_NAME\'s launched PID (`pgrep -x '
            '"$APP_NAME"`); the smoke launch in `build_and_run.sh --verify` still '
            "leaves a process running that this gate's cleanup must reap."
        )
    elif not re.search(r"(?<![A-Za-z])kill\b", code_source):
        failures.append(
            "verify_all.sh tracks $APP_NAME's PID but never kills it; add a bare "
            "`kill` (not `pkill`) on the tracked PID(s) in the cleanup trap."
        )
    return failures


def required_apple_products(metadata: dict[str, str]) -> set[str]:
    return {
        metadata.get("APP_PRODUCT_NAME", metadata["APP_NAME"]),
        metadata["MOBILE_APP_NAME"],
        metadata["VISION_APP_NAME"],
        metadata["WATCH_APP_NAME"],
        metadata["MCP_HOST_PRODUCT"],
        metadata["WIDGET_EXECUTABLE"],
        "LorvexWidgetBundle",
        "LorvexWatchComplication",
    }


def build_matrix_failures(
    package_source: str,
    script_source: str,
    metadata: dict[str, str],
) -> list[str]:
    package_products = swiftpm_executable_products(package_source)
    built_products = verify_all_build_products(script_source, metadata)
    required_products = required_apple_products(metadata)

    failures: list[str] = []
    missing_package_products = sorted(required_products - package_products)
    if missing_package_products:
        failures.append(
            f"Package.swift missing required executable product(s): {missing_package_products}"
        )

    missing_builds = sorted(required_products - built_products)
    if missing_builds:
        failures.append(f"verify_all.sh does not build product(s): {missing_builds}")

    unbuilt_package_products = sorted(
        package_products - built_products - ALLOWED_UNBUILT_EXECUTABLE_PRODUCTS
    )
    if unbuilt_package_products:
        failures.append(
            "verify_all.sh does not build executable product(s) declared in Package.swift: "
            f"{unbuilt_package_products}"
        )

    failures.extend(verify_all_launch_cleanup_failures(script_source))

    missing_commands = [
        command for command in REQUIRED_VERIFY_ALL_COMMANDS if command not in script_source
    ]
    if missing_commands:
        failures.append(f"verify_all.sh misses required gate command(s): {missing_commands}")

    return failures


def main() -> int:
    metadata = load_metadata()
    failures = build_matrix_failures(
        PACKAGE_PATH.read_text(encoding="utf-8"),
        VERIFY_ALL_PATH.read_text(encoding="utf-8"),
        metadata,
    )
    # build_and_run.sh and archive_local.sh also launch the app; hold them to the
    # same no-global-`pkill -x` rule so a regression in either is caught here.
    for script_name, script_path in (
        ("build_and_run.sh", BUILD_AND_RUN_PATH),
        ("archive_local.sh", ARCHIVE_LOCAL_PATH),
    ):
        failures.extend(
            global_pkill_failures(script_name, script_path.read_text(encoding="utf-8"))
        )
    if failures:
        print("Build matrix verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Build matrix verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
