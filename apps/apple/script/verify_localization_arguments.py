#!/usr/bin/env python3
"""Check that the code passes each localized string the arguments its catalog text formats.

Usage:
  verify_localization_arguments.py [--skip-build] [--scratch-path PATH] [--verbose]

A `String(localized:defaultValue:…)` or `LocalizedStringResource` call passes
its interpolated values to the catalog's text for the key as printf arguments,
in the order they appear in the default value, each with the printf type of its
Swift type (`Int` is `%lld`, `UInt32` is `%u`, `Double` is `%lf`, any other
value `%@`). The catalog's source-language text must format exactly those
arguments: an argument it reads that the call does not pass, or reads with
another type, prints garbage or crashes, and one it never reads is dropped from
the sentence. The catalog verifier already holds every translation to the
source language's arguments, so this check covers every shipped language.

Only the compiler knows the argument types, so the check builds the package for
macOS with the compiler's localized-string extraction
(`-emit-localized-strings`) into its own scratch path (`.build/localized-strings`
by default, incremental after the first run), then reads the `.stringsdata`
file it writes for each source file. `--skip-build` reads the files of the last
build. Code that only compiles for iOS or watchOS is not extracted by a macOS
build; the report counts the catalog keys the source names that the build did
not extract, and `--verbose` lists them.

A call's catalog is the one its `bundle:` argument names, the same ownership the
catalog verifier uses. Exits 1 when any call's arguments differ from its
catalog text's.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from verify_localization_catalog import (  # noqa: E402
    APP_NATIVE_BUNDLE_TOKENS,
    APP_RESOURCE_BUNDLE_TOKENS,
    CATALOG_PATH,
    DEFAULT_SOURCE_LANGUAGE,
    MODULE_CATALOGS,
    MODULE_RESOURCE_BUNDLE_TOKENS,
    NATIVE_STRING_BUNDLE_TOKENS,
    ROOT,
    _iter_keyed_localization_call_details,
    format_placeholders,
    localization_format_placeholders,
)

SOURCES = ROOT / "Sources"
DEFAULT_SCRATCH_PATH = ROOT / ".build" / "localized-strings"
CALL_OPENERS = (
    re.compile(r"String\s*\(\s*localized:\s*"),
    re.compile(r"LocalizedStringResource\s*\("),
)

# printf length modifiers that name the same argument size on Apple's 64-bit
# platforms, and conversions that read the same argument. `%s` is not `%@`: it
# reads a C string pointer, not the object a Swift value is passed as.
_EQUIVALENT_TOKENS = {
    "ld": "lld",
    "li": "lld",
    "lli": "lld",
    "i": "d",
    "lu": "llu",
    "lf": "f",
    "lF": "f",
    "F": "f",
}


def normalized_type(token: str) -> str:
    """The argument a printf token reads, so equivalent spellings compare equal."""
    return _EQUIVALENT_TOKENS.get(token, token)


def _display_path(path: Path) -> str:
    """`path` relative to the package root when it lies inside it."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


@dataclass(frozen=True)
class ExtractedString:
    """One localized-string call as the compiler extracted it."""

    source: Path
    line: int
    key: str
    value: str


# MARK: - Build and extraction


def build(scratch_path: Path) -> None:
    """Build the package for macOS with localized-string extraction into `scratch_path`."""
    output = scratch_path / "stringsdata"
    output.mkdir(parents=True, exist_ok=True)
    command = [
        "swift", "build", "-j", "4",
        "--package-path", str(ROOT),
        "--scratch-path", str(scratch_path),
        "-Xswiftc", "-emit-localized-strings",
        "-Xswiftc", "-emit-localized-strings-path",
        "-Xswiftc", str(output),
    ]
    completed = subprocess.run(command, cwd=ROOT)
    if completed.returncode != 0:
        raise SystemExit(f"swift build failed (exit {completed.returncode})")


def extracted_strings(scratch_path: Path, sources: Path = SOURCES) -> list[ExtractedString]:
    """Every call the `.stringsdata` files under `scratch_path` record for a file under `sources`.

    The build writes one record file per compiled source file: into the
    requested directory, or beside the target's object files when SwiftPM
    builds through Swift Build. A source file with several record files is
    read from the newest. A record whose source file no longer exists is left
    out, since an incremental build never removes the record of a deleted file.
    """
    newest: dict[Path, tuple[float, dict]] = {}
    for path in scratch_path.rglob("*.stringsdata"):
        document = json.loads(path.read_text(encoding="utf-8"))
        source = Path(document.get("source", ""))
        if not source.is_absolute() or not source.exists():
            continue
        try:
            source.relative_to(sources)
        except ValueError:
            continue
        modified = path.stat().st_mtime
        if source not in newest or modified > newest[source][0]:
            newest[source] = (modified, document)
    strings: list[ExtractedString] = []
    for source, (_modified, document) in sorted(newest.items()):
        for entries in (document.get("tables") or {}).values():
            for entry in entries:
                location = entry.get("location") or {}
                strings.append(ExtractedString(
                    source=source,
                    line=int(location.get("startingLine", 0)),
                    key=entry["key"],
                    value=entry.get("value", entry["key"]),
                ))
    return strings


def colliding_source_names(sources: Path = SOURCES) -> list[str]:
    """Basenames shared by two source files that both localize strings.

    The compiler names each `.stringsdata` file after its source file's
    basename, so such files overwrite each other's records.
    """
    by_name: dict[str, list[Path]] = {}
    for path in sources.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        if any(opener.search(text) for opener in CALL_OPENERS):
            by_name.setdefault(path.name, []).append(path)
    return sorted(name for name, paths in by_name.items() if len(paths) > 1)


# MARK: - Catalog ownership


def catalog_for_token() -> dict[str, Path]:
    """The catalog each `bundle:` token's calls resolve against."""
    owners = {token: CATALOG_PATH for token in APP_NATIVE_BUNDLE_TOKENS | APP_RESOURCE_BUNDLE_TOKENS}
    for helper, catalog, _roots in MODULE_CATALOGS:
        for token in NATIVE_STRING_BUNDLE_TOKENS.get(helper, set()) | MODULE_RESOURCE_BUNDLE_TOKENS.get(helper, set()):
            owners[token] = catalog
    return owners


def source_calls(source: Path) -> list[tuple[str, int, str | None]]:
    """`(key, line of the key literal, bundle token)` for each localized-string call in `source`.

    The token is None when the call's `bundle:` argument is not a plain
    identifier chain.
    """
    text = source.read_text(encoding="utf-8")
    calls: list[tuple[str, int, str | None]] = []
    for opener in CALL_OPENERS:
        details = _iter_keyed_localization_call_details(text, opener)
        for match, (key, token, body, _start) in zip(opener.finditer(text), details):
            if key is None:
                continue
            key_offset = match.end() + body.index('"')
            calls.append((key, text.count("\n", 0, key_offset) + 1, token))
    return calls


# MARK: - Comparison


def catalog_arguments(localization: dict) -> dict[int, str]:
    """The printf arguments a localization reads, by position, across all its forms."""
    plural = (localization.get("variations") or {}).get("plural")
    if isinstance(plural, dict):
        arguments: dict[int, str] = {}
        for variant in plural.values():
            text = ((variant or {}).get("stringUnit") or {}).get("value")
            if isinstance(text, str):
                for position, token in format_placeholders(text):
                    arguments.setdefault(position, token)
        return arguments
    placeholders, _failures = localization_format_placeholders(localization)
    return dict(placeholders)


def argument_failures(call: ExtractedString, catalog_label: str, localization: dict) -> list[str]:
    """How the call's arguments differ from those its catalog text reads."""
    code = dict(format_placeholders(call.value))
    catalog = catalog_arguments(localization)
    prefix = f"{_display_path(call.source)}:{call.line} '{call.key}' ({catalog_label})"
    failures: list[str] = []
    for position in sorted(set(code) | set(catalog)):
        passed, read = code.get(position), catalog.get(position)
        if read is None:
            failures.append(f"{prefix}: the code passes argument {position} (%{passed}), which the catalog text never shows")
        elif passed is None:
            failures.append(f"{prefix}: the catalog text reads argument {position} (%{read}), which the code does not pass")
        elif normalized_type(passed) != normalized_type(read):
            failures.append(f"{prefix}: argument {position} is %{passed} in the code but %{read} in the catalog text")
    return failures


def verify(strings: list[ExtractedString]) -> tuple[list[str], set[tuple[str, str]]]:
    """Failures for every extracted call, and the `(catalog, key)` pairs checked."""
    owners = catalog_for_token()
    catalogs: dict[Path, dict] = {}
    tokens_by_source: dict[Path, dict[tuple[str, int], str | None]] = {}
    failures: list[str] = []
    checked: set[tuple[str, str]] = set()
    for call in strings:
        if call.source not in tokens_by_source:
            tokens_by_source[call.source] = {
                (key, line): token for key, line, token in source_calls(call.source)}
        token = tokens_by_source[call.source].get((call.key, call.line))
        catalog_path = owners.get(token or "")
        if catalog_path is None:
            continue
        catalog = catalogs.setdefault(catalog_path, json.loads(catalog_path.read_text(encoding="utf-8")))
        label = _display_path(catalog_path)
        entry = (catalog.get("strings") or {}).get(call.key)
        if entry is None:
            continue  # a missing key is the catalog verifier's finding
        source_language = catalog.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
        localization = (entry.get("localizations") or {}).get(source_language)
        if not isinstance(localization, dict):
            continue
        checked.add((label, call.key))
        failures.extend(argument_failures(call, label, localization))
    return failures, checked


def unextracted_calls(strings: list[ExtractedString], sources: Path = SOURCES) -> list[str]:
    """The calls under `sources` a catalog owns that the build did not extract.

    These sit in code the macOS build does not compile (`#if os(iOS)`,
    `#if os(watchOS)`), so this check cannot see their arguments.
    """
    owners = catalog_for_token()
    extracted = {(call.source, call.key, call.line) for call in strings}
    missing: list[str] = []
    for path in sorted(sources.rglob("*.swift")):
        for key, line, token in source_calls(path):
            if owners.get(token or "") is not None and (path, key, line) not in extracted:
                missing.append(f"{_display_path(path)}:{line} '{key}'")
    return missing


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--skip-build", action="store_true", help="read the last build's extraction")
    parser.add_argument("--scratch-path", type=Path, default=DEFAULT_SCRATCH_PATH)
    parser.add_argument("--verbose", action="store_true", help="list the calls the build did not extract")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    collisions = colliding_source_names()
    if collisions:
        print(
            "Source files that localize strings share a basename, so their extraction records "
            f"overwrite each other; rename one of each: {collisions}",
            file=sys.stderr,
        )
        return 1
    scratch_path = args.scratch_path.resolve()
    if not args.skip_build:
        build(scratch_path)
    strings = extracted_strings(scratch_path)
    if not strings:
        print(f"No extraction records under {scratch_path}; run without --skip-build.", file=sys.stderr)
        return 1
    failures, checked = verify(strings)
    missing = unextracted_calls(strings)
    for failure in failures:
        print(failure, file=sys.stderr)
    if args.verbose:
        for call in missing:
            print(f"not compiled for macOS: {call}")
    summary = (
        f"{len(checked)} catalog entries checked against {len(strings)} extracted calls; "
        f"{len(missing)} calls are not compiled for macOS and were not checked"
    )
    if failures:
        print(f"{len(failures)} argument mismatch(es). {summary}.", file=sys.stderr)
        return 1
    print(f"Localized-string arguments match their catalog text. {summary}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
