#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


def run(command: list[str]) -> str:
    return subprocess.check_output(command, text=True)


def is_macho(path: Path) -> bool:
    try:
        output = run(["file", str(path)])
    except subprocess.CalledProcessError:
        return False
    return "Mach-O" in output


def macho_load_paths(path: Path) -> list[str]:
    output = run(["otool", "-L", str(path)])
    paths: list[str] = []
    for line in output.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        paths.append(stripped.split(" (", 1)[0])
    return paths


def has_distribution_safe_path(load_path: str) -> bool:
    return (
        load_path.startswith("/System/Library/")
        or load_path.startswith("/usr/lib/")
        or load_path.startswith("@rpath/")
        or load_path.startswith("@loader_path/")
        or load_path.startswith("@executable_path/")
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_macho_distribution.py <AppBundle.app>", file=sys.stderr)
        return 2

    app_bundle = Path(sys.argv[1]).resolve()
    if not app_bundle.is_dir():
        print(f"app bundle not found: {app_bundle}", file=sys.stderr)
        return 2

    failures: list[str] = []
    checked = 0
    for path in sorted(p for p in app_bundle.rglob("*") if p.is_file()):
        if not is_macho(path):
            continue
        checked += 1
        for load_path in macho_load_paths(path):
            if not has_distribution_safe_path(load_path):
                failures.append(f"{path.relative_to(app_bundle)} loads {load_path}")

    if checked == 0:
        print(f"no Mach-O files found in {app_bundle}", file=sys.stderr)
        return 1

    if failures:
        print("Mach-O distribution verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Mach-O distribution verification passed ({checked} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
