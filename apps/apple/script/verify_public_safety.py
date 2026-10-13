#!/usr/bin/env python3
"""Fails when a tracked file holds something that must never be published.

The repository is public, so every tracked file is published the moment it is
pushed. This gate reads every file `git ls-files` lists and rejects:

- email addresses (contact goes through the lorvex.app support page), except
  at the domains reserved for examples and tests;
- absolute home or temporary-directory paths of a developer machine, except
  the made-up account names tests use;
- private key blocks and App Store Connect app-specific passwords, except the
  all-`x` placeholder;
- credential files by name: signing profiles, key files, `secrets/`.

A line can opt out with the marker `public-safety: allow` when it holds a
pattern on purpose, such as a redaction list that names what it removes.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ALLOW_MARKER = "public-safety: allow"
CONTENT_RULES = [
    ("email address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")),
    ("home directory path", re.compile(r"/Users/[A-Za-z0-9._-]+/|/home/[a-z][a-z0-9_-]*/")),
    ("machine temporary path", re.compile(r"/private/tmp/claude-|/private/var/folders/")),  # public-safety: allow
    ("private key block", re.compile(r"BEGIN [A-Z ]*PRIVATE KEY")),
    ("app-specific password", re.compile(r"(?<![A-Za-z-])[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}(?![A-Za-z-])")),
]
# Reserved for documentation and tests (RFC 2606, RFC 6761); they name no one.
RESERVED_DOMAIN = re.compile(r"@(?:[A-Za-z0-9-]+\.)*(?:example\.(?:com|org|net)|[A-Za-z0-9-]+\.(?:example|test|invalid|localhost))$")
PATH_RULES = [
    ("credential file", re.compile(r"(^|/)secrets/|\.(p8|p12|pem|key|mobileprovision|provisionprofile|cer)$|(^|/)\.env$|(^|/)id_(rsa|ed25519|ecdsa)$")),
]


# Account names tests and docs use for a made-up machine.
PLACEHOLDER_USERS = {"alex", "alice", "bob", "dev", "example", "me", "tester", "user"}


def is_placeholder(rule: str, text: str) -> bool:
    """Whether a match is a stand-in that names no real person or machine."""
    if rule == "email address":
        return bool(RESERVED_DOMAIN.search(text))
    if rule == "home directory path":
        return text.strip("/").split("/")[-1].lower() in PLACEHOLDER_USERS
    if rule == "app-specific password":
        return set(text) <= {"x", "-"}
    return False


def line_findings(line: str) -> list[tuple[str, str]]:
    """Every non-placeholder match on `line`, as (rule name, matched text). Every
    match counts: a placeholder earlier on the line must not hide a real one
    after it."""
    found: list[tuple[str, str]] = []
    for name, rule in CONTENT_RULES:
        for match in rule.finditer(line):
            if not is_placeholder(name, match.group(0)):
                found.append((name, match.group(0)))
    return found


def tracked_files(root: pathlib.Path) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"], check=True, capture_output=True
    ).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def main() -> int:
    root = pathlib.Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True).stdout.strip()
    )
    failures: list[str] = []
    for rel in tracked_files(root):
        for name, rule in PATH_RULES:
            if rule.search(rel):
                failures.append(f"{rel}: {name}")
        path = root / rel
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if ALLOW_MARKER in line:
                continue
            for name, text_found in line_findings(line):
                failures.append(f"{rel}:{number}: {name}: {text_found[:60]}")
    if failures:
        print("verify_public_safety: tracked files hold content that must not be published:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("verify_public_safety: no email address, machine path, key or credential file in tracked files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
