#!/usr/bin/env python3
"""Cuts the GitHub release for a notarized DMG build, the way docs/release.md describes.

    script/github_release.py notes <build> > notes.md     # a skeleton, to fill in
    script/github_release.py publish <build> notes.md [--dry-run]

`notes` prints release notes in the shape of the existing releases, with the SHA-256 of the
DMG in `dist/` and the commit of the `Build <build>` commit filled in, and a marked place for
what changed. `publish` checks the DMG (its checksum file, Apple's notarization verdict, its
staple), refuses notes that still hold the marker or miss the checksum or commit, copies the
DMG and checksum under the two names every release uses, creates the release `v<version>+<build>`
at the build's commit with `--latest`, and deletes the older builds' release pages of that
marketing version (their tags stay, naming the commits they were built from).

Run it from anywhere inside the repository after `script/package_dmg.sh` has written the DMG.
`--dry-run` does every check and prints what it would do without touching GitHub.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
DIST = APP_DIR / "dist"
REPO_ROOT = APP_DIR.parents[1]
PLACEHOLDER = "<!-- WHAT CHANGED: replace this line with the bullets, then delete the marker -->"
DMG_PATTERN = re.compile(r"^Lorvex-macOS-(\d+\.\d+\.\d+)\+(\d+)-arm64\.dmg$")
ASSET_DMG = "Lorvex-macOS-arm64.dmg"
ASSET_SHA = "Lorvex-macOS-arm64.dmg.sha256"

NOTES_TEMPLATE = """\
Lorvex for Mac, built from the same source as the TestFlight build {version} ({build}).

## Install

1. Download `{dmg}` below.
2. Open it and drag Lorvex to Applications.

Requires a Mac with Apple silicon and macOS 26 or later. The app is signed with a Developer ID certificate and notarized by Apple.

## What changed since {version} ({previous})

{placeholder}

## Good to know

- **Sync:** this build syncs through your iCloud account with Lorvex on your iPhone, iPad, and other Macs.
- **Updates:** this build does not update itself. New builds are posted on this releases page.
- **AI assistant:** connect Claude or another MCP client from **Settings → Assistant**; see the [MCP setup guide](https://github.com/boyugou/lorvex/blob/main/apps/apple/docs/setup/ASSISTANT_MCP_SETUP.md).

## Verify the download

```
shasum -a 256 {dmg}
```

should print `{sha}`.

Built from commit `{commit}`.
"""


def dmg_for_build(build: int, dist: Path = DIST) -> tuple[Path, str]:
    """The DMG `package_dmg.sh` wrote for `build`, and its marketing version."""
    matches = []
    for path in sorted(dist.glob("Lorvex-macOS-*-arm64.dmg")):
        found = DMG_PATTERN.match(path.name)
        if found and int(found.group(2)) == build:
            matches.append((path, found.group(1)))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one DMG for build {build} in {dist}, found {[p.name for p, _ in matches]}"
        )
    return matches[0]


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def notes_problems(notes: str, sha: str, commit_short: str) -> list[str]:
    """What is wrong with release notes before they are published."""
    problems = []
    if PLACEHOLDER in notes or "WHAT CHANGED" in notes:
        problems.append("the notes still hold the WHAT CHANGED marker")
    if sha not in notes:
        problems.append("the notes do not carry the DMG's SHA-256")
    if commit_short not in notes:
        problems.append(f"the notes do not name the build commit {commit_short}")
    if re.search(r"[\w.+-]+@[\w-]+\.[\w.-]+", re.sub(r"https?://\S+", "", notes)):
        problems.append("the notes contain an email address")
    return problems


def releases_to_delete(tags: list[str], version: str, build: int) -> list[str]:
    """The older builds' release tags of the same marketing version."""
    found = []
    for tag in tags:
        match = re.fullmatch(r"v(\d+\.\d+\.\d+)\+(\d+)", tag)
        if match and match.group(1) == version and int(match.group(2)) < build:
            found.append(tag)
    return sorted(found)


def run(command: list[str], *, capture: bool = True, check: bool = True) -> str:
    result = subprocess.run(
        command, cwd=REPO_ROOT, check=check, capture_output=capture, text=True
    )
    return result.stdout.strip() if capture else ""


def build_commit(build: int) -> str:
    """The full hash of the `Build <build>` commit."""
    found = run(["git", "log", "--format=%H", "--grep", f"^Build {build}$", "-n", "1"])
    if not found:
        raise SystemExit(f"no commit titled 'Build {build}' was found")
    return found


def previous_build(build: int, version: str) -> int:
    tags = run(["git", "tag", "--list", f"v{version}+*"]).splitlines()
    earlier = [int(t.rsplit("+", 1)[1]) for t in tags if int(t.rsplit("+", 1)[1]) < build]
    return max(earlier) if earlier else build - 1


def command_notes(build: int) -> int:
    dmg, version = dmg_for_build(build)
    commit = build_commit(build)
    sys.stdout.write(
        NOTES_TEMPLATE.format(
            version=version,
            build=build,
            previous=previous_build(build, version),
            placeholder=PLACEHOLDER,
            dmg=ASSET_DMG,
            sha=sha256_of(dmg),
            commit=commit[:7],
        )
    )
    return 0


def verify_dmg(dmg: Path, sha: str) -> None:
    recorded = dmg.with_name(dmg.name + ".sha256")
    if recorded.exists() and recorded.read_text().split()[0] != sha:
        raise SystemExit(f"{recorded.name} does not match the DMG it sits beside")
    verdict = subprocess.run(
        ["spctl", "-a", "-t", "open", "--context", "context:primary-signature", "-v", str(dmg)],
        capture_output=True,
        text=True,
    )
    if verdict.returncode != 0 or "Notarized Developer ID" not in verdict.stderr + verdict.stdout:
        raise SystemExit(f"Gatekeeper does not accept {dmg.name} as a notarized Developer ID image")
    stapled = subprocess.run(["xcrun", "stapler", "validate", str(dmg)], capture_output=True, text=True)
    if stapled.returncode != 0:
        raise SystemExit(f"{dmg.name} has no valid notarization ticket stapled to it")


def command_publish(build: int, notes_path: Path, dry_run: bool) -> int:
    dmg, version = dmg_for_build(build)
    sha = sha256_of(dmg)
    commit = build_commit(build)
    notes = notes_path.read_text(encoding="utf-8")
    problems = notes_problems(notes, sha, commit[:7])
    if problems:
        raise SystemExit("not publishing: " + "; ".join(problems))
    verify_dmg(dmg, sha)

    tag = f"v{version}+{build}"
    existing = run(["gh", "release", "list", "--limit", "100", "--json", "tagName", "--jq", ".[].tagName"])
    tags = existing.splitlines()
    if tag in tags:
        raise SystemExit(f"{tag} already has a release; repackaging replaces its assets with `gh release upload --clobber`")
    stale = releases_to_delete(tags, version, build)

    with tempfile.TemporaryDirectory() as staging_name:
        staging = Path(staging_name)
        shutil.copyfile(dmg, staging / ASSET_DMG)
        (staging / ASSET_SHA).write_text(f"{sha}  {ASSET_DMG}\n")
        create = [
            "gh", "release", "create", tag,
            "--target", commit,
            "--title", f"Lorvex {version} ({build})",
            "--notes-file", str(notes_path),
            "--latest",
            str(staging / ASSET_DMG), str(staging / ASSET_SHA),
        ]
        print(f"release {tag} at {commit[:7]}; sha256 {sha[:12]}...; older pages to delete: {stale or 'none'}")
        if dry_run:
            print("dry run: " + " ".join(create))
            return 0
        run(create, capture=False)
    for old in stale:
        run(["gh", "release", "delete", old, "--yes"], capture=False)
    print(run(["gh", "release", "view", tag, "--json", "url", "--jq", ".url"]))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    notes = commands.add_parser("notes", help="print a skeleton of the release notes")
    notes.add_argument("build", type=int)
    publish = commands.add_parser("publish", help="create the release and retire the older pages")
    publish.add_argument("build", type=int)
    publish.add_argument("notes", type=Path)
    publish.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    if arguments.command == "notes":
        return command_notes(arguments.build)
    return command_publish(arguments.build, arguments.notes, arguments.dry_run)


if __name__ == "__main__":
    sys.exit(main())
