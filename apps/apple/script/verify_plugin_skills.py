#!/usr/bin/env python3
"""Check the Claude Code plugin's skills against the MCP tool surface.

A skill is prose that names tools and their arguments. When a tool or an
argument is renamed, the skill keeps pointing at nothing and no test fails
until an assistant follows it. This gate reads every
`plugins/lorvex/skills/<name>/SKILL.md` and requires:

- front matter with a `name` equal to the skill's directory and a one-line
  `description` that says when to use the skill;
- every backticked snake_case identifier to be a tool, an argument, or a value
  in `mcp_tool_manifest.json` (the committed lock of the host's input schemas,
  nested object fields and enum values included), or else a word the app's
  Swift sources use: the memory sections the skills read and the fields a tool
  returns.

A rename therefore fails `verify_mcp_tool_manifest.py` first, and this gate
names each skill the rename leaves stale.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
APP_ROOT = SCRIPT_DIR.parent
REPO_ROOT = APP_ROOT.parents[1]
SKILLS_DIR = REPO_ROOT / "plugins" / "lorvex" / "skills"
MANIFEST_PATH = SCRIPT_DIR / "mcp_tool_manifest.json"
SOURCE_ROOTS = (APP_ROOT / "Sources", APP_ROOT / "core" / "Sources")

IDENTIFIER = re.compile(r"`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`")
WORD = re.compile(r"[a-z][a-z0-9_]*")
FRONT_MATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def manifest_vocabulary(manifest: dict) -> set[str]:
    """Every tool name, argument name, nested field, and enum value in the lock."""
    words: set[str] = set(manifest)
    for tool in manifest.values():
        for name, token in tool.get("properties", {}).items():
            words.add(name)
            words.update(WORD.findall(token))
        words.update(tool.get("required", []))
    return words


def front_matter(text: str) -> dict[str, str] | None:
    match = FRONT_MATTER.match(text)
    if not match:
        return None
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, separator, value = line.partition(":")
        if separator:
            fields[key.strip()] = value.strip().strip('"')
    return fields


def spelled_in_sources(names: set[str], roots: tuple[Path, ...]) -> set[str]:
    """The names among `names` that some Swift source uses as a whole word."""
    found: set[str] = set()
    pending = {name: re.compile(rf"\b{re.escape(name)}\b") for name in names}
    for root in roots:
        for path in sorted(root.rglob("*.swift")) if root.is_dir() else []:
            if not pending:
                return found
            text = path.read_text(encoding="utf-8", errors="replace")
            for name in [name for name, pattern in pending.items() if pattern.search(text)]:
                found.add(name)
                del pending[name]
    return found


def skill_failures(
    skills_dir: Path = SKILLS_DIR,
    manifest_path: Path = MANIFEST_PATH,
    source_roots: tuple[Path, ...] = SOURCE_ROOTS,
) -> list[str]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    vocabulary = manifest_vocabulary(manifest)
    failures: list[str] = []
    unknown: dict[str, set[str]] = {}
    directories = sorted(path for path in skills_dir.iterdir() if path.is_dir())
    if not directories:
        failures.append(f"{skills_dir}: no skills found")
    for directory in directories:
        label = f"{directory.parent.name}/{directory.name}/SKILL.md"
        skill_file = directory / "SKILL.md"
        if not skill_file.is_file():
            failures.append(f"{directory.name}: no SKILL.md")
            continue
        text = skill_file.read_text(encoding="utf-8")
        fields = front_matter(text)
        if fields is None:
            failures.append(f"{label}: no front matter")
        else:
            if fields.get("name") != directory.name:
                failures.append(
                    f"{label}: front matter name {fields.get('name')!r} is not {directory.name!r}")
            if not fields.get("description"):
                failures.append(f"{label}: front matter has no one-line description")
        for name in set(IDENTIFIER.findall(text)) - vocabulary:
            unknown.setdefault(name, set()).add(label)
    known_elsewhere = spelled_in_sources(set(unknown), source_roots)
    for name in sorted(set(unknown) - known_elsewhere):
        for label in sorted(unknown[name]):
            failures.append(
                f"{label}: `{name}` is not a tool, an argument, or a value the app defines")
    return failures


def main() -> int:
    failures = skill_failures()
    if failures:
        print("Plugin skill verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    count = sum(1 for path in SKILLS_DIR.iterdir() if path.is_dir())
    print(f"Plugin skill verification passed: {count} skills name only tools, arguments, and values the app defines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
