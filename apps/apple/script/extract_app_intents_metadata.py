#!/usr/bin/env python3
"""Write the App Intents metadata for one SwiftPM-built macOS executable.

The App Intents runtime (Shortcuts actions, Siri and App Shortcuts, widget
configuration, interactive widget buttons, controls) discovers a bundle's
intents through `Contents/Resources/Metadata.appintents`. Xcode writes it in
its ExtractAppIntentsMetadata build phase; the macOS app is a pure-SwiftPM
build, so release staging (`build_and_run.sh`) compiles with the Swift
compiler's const-value extraction on (`-emit-const-values` with the protocol
list in `Config/AppIntentsConstValueProtocols.json`) and runs this script once
per executable that carries intents.

For the executable target named by `--target` it:

1. Collects the root-package targets linked into the executable: the
   target-dependency closure from `swift package describe`. Only their
   `.swiftconstvalues` files and sources reach the processor, because it
   records every conformance it is given, linked or not.
2. Runs `appintentsmetadataprocessor` over the staged binary, writing
   `Metadata.appintents` into `--resources`.
3. Writes every string the metadata names (a `key` in a `table`) into the
   bundle's own `<language>.lproj/<table>.strings`, taken from the linked
   targets' String Catalogs. The system resolves metadata strings in the bundle
   that holds the metadata; the catalogs themselves ship inside nested SwiftPM
   resource bundles it never reads.
4. Compiles a linked target's `AppShortcuts.xcstrings` into the bundle's
   `.lproj` directories, where the system reads App Shortcut phrases.

It fails when the metadata lacks an `--expect`ed type, when a linked target has
no const values (the build ran without extraction), or when a metadata string
is missing from every linked catalog or lacks a shipped language.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
APP_SHORTCUTS_CATALOG = "AppShortcuts.xcstrings"


def run(command: list[str], **kwargs) -> str:
    return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs).stdout


def linked_targets(description: dict, root: str) -> list[dict]:
    """The root-package targets in `root`'s target-dependency closure."""
    targets = {target["name"]: target for target in description["targets"]}
    if root not in targets:
        raise SystemExit(f"extract_app_intents_metadata: no target named {root}")
    order: list[str] = []
    pending = [root]
    while pending:
        name = pending.pop()
        if name in order or name not in targets:
            continue
        order.append(name)
        pending.extend(targets[name].get("target_dependencies", []))
    return [targets[name] for name in order]


def const_value_files(bin_path: Path, package: str, module: str) -> list[Path]:
    """The module's `.swiftconstvalues`, in either SwiftPM build layout."""
    roots = [
        # Swift Build layout: .build/out/Intermediates.noindex/<Package>.build/<Config>/<Module>-*.build
        bin_path.parents[1] / "Intermediates.noindex" / f"{package}.build" / bin_path.name,
        # Native layout: .build/<triple>/<config>/<Module>.build
        bin_path,
    ]
    files: list[Path] = []
    for root in roots:
        for build_dir in [*root.glob(f"{module}-*.build"), root / f"{module}.build"]:
            if build_dir.is_dir():
                files.extend(sorted(build_dir.rglob("*.swiftconstvalues")))
    return files


def toolchain_dir() -> Path:
    return Path(run(["xcrun", "--find", "swift"]).strip()).parents[2]


def xcode_build_version() -> str:
    for line in run(["xcodebuild", "-version"]).splitlines():
        if line.startswith("Build version"):
            return line.split()[-1]
    raise SystemExit("extract_app_intents_metadata: could not read the Xcode build version")


def metadata_strings(node, found: dict[tuple[str, str], str]) -> None:
    """Collect every `LocalizedStringResource` the metadata encodes."""
    if isinstance(node, dict):
        if isinstance(node.get("key"), str) and isinstance(node.get("table"), str):
            found.setdefault((node["table"], node["key"]), node.get("defaultValue") or node["key"])
        for value in node.values():
            metadata_strings(value, found)
    elif isinstance(node, list):
        for value in node:
            metadata_strings(value, found)


def catalog_value(entry: dict, language: str) -> str | None:
    unit = entry.get("localizations", {}).get(language, {})
    if "variations" in unit:
        raise SystemExit(
            "extract_app_intents_metadata: a metadata string has plural or device "
            f"variations, which a .strings table cannot carry ({language})")
    value = unit.get("stringUnit", {}).get("value")
    return value if isinstance(value, str) else None


def write_metadata_tables(
    strings: dict[tuple[str, str], str], targets: list[dict], resources: Path
) -> None:
    """Write each metadata string into `<language>.lproj/<table>.strings`."""
    catalogs: dict[str, list[dict]] = {}
    for target in targets:
        for resource in target.get("resources", []):
            path = Path(resource["path"])
            if path.suffix == ".xcstrings" and path.name != APP_SHORTCUTS_CATALOG:
                catalogs.setdefault(path.stem, []).append(json.loads(path.read_text()))

    # Every language any of a table's catalogs ships, so a string the
    # metadata names is translated wherever its table is.
    table_languages = {
        table: {catalog["sourceLanguage"] for catalog in group}
        | {
            language
            for catalog in group
            for entry in catalog["strings"].values()
            for language in entry.get("localizations", {})
        }
        for table, group in catalogs.items()
    }

    tables: dict[tuple[str, str], dict[str, str]] = {}
    failures: list[str] = []
    for (table, key), default_value in sorted(strings.items()):
        candidates = [catalog for catalog in catalogs.get(table, []) if key in catalog["strings"]]
        if not candidates:
            failures.append(f"{table}: {key} is in no linked target's {table}.xcstrings")
            continue
        catalog = candidates[0]
        entry = catalog["strings"][key]
        for language in sorted(table_languages[table]):
            value = catalog_value(entry, language)
            if value is None and language == catalog["sourceLanguage"]:
                value = default_value
            if value is None:
                failures.append(f"{table}: {key} has no {language} translation")
                continue
            tables.setdefault((language, table), {})[key] = value
    if failures:
        raise SystemExit("extract_app_intents_metadata:\n  " + "\n  ".join(failures))

    for (language, table), entries in tables.items():
        directory = resources / f"{language}.lproj"
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / f"{table}.strings").open("wb") as handle:
            plistlib.dump(entries, handle, fmt=plistlib.FMT_BINARY)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", required=True, help="the executable target")
    parser.add_argument("--binary", required=True, type=Path, help="the staged executable")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--resources", required=True, type=Path, help="the bundle's Contents/Resources")
    parser.add_argument("--bin-path", required=True, type=Path, help="`swift build --show-bin-path`")
    parser.add_argument("--deployment-target", required=True)
    parser.add_argument(
        "--expect", action="append", default=[],
        help="an intent, entity, or query type the metadata must contain")
    args = parser.parse_args()

    description = json.loads(run(["swift", "package", "describe", "--type", "json"], cwd=ROOT_DIR))
    targets = linked_targets(description, args.target)

    const_values: list[Path] = []
    sources: list[Path] = []
    for target in targets:
        module = target.get("c99name", target["name"])
        files = const_value_files(args.bin_path, description["name"], module)
        if not files:
            raise SystemExit(
                f"extract_app_intents_metadata: no .swiftconstvalues for {module} under "
                f"{args.bin_path}; build with -emit-const-values")
        const_values.extend(files)
        target_dir = ROOT_DIR / target["path"]
        sources.extend(target_dir / source for source in target.get("sources", []))

    archs = run(["lipo", "-archs", str(args.binary)]).split()
    if archs != ["arm64"]:
        raise SystemExit(f"extract_app_intents_metadata: expected an arm64 binary, got {archs}")

    has_app_shortcuts = any(
        Path(resource["path"]).name == APP_SHORTCUTS_CATALOG
        for target in targets for resource in target.get("resources", []))

    # App Shortcut phrases resolve through the bundle's AppShortcuts.strings;
    # compile them before the processor, which reads the bundle's phrases.
    for target in targets:
        for resource in target.get("resources", []):
            if Path(resource["path"]).name == APP_SHORTCUTS_CATALOG:
                run(["xcrun", "xcstringstool", "compile", resource["path"],
                     "--output-directory", str(args.resources)])

    with tempfile.TemporaryDirectory() as scratch:
        source_list = Path(scratch) / "sources.txt"
        source_list.write_text("".join(f"{path}\n" for path in sources))
        const_list = Path(scratch) / "constvalues.txt"
        const_list.write_text("".join(f"{path}\n" for path in const_values))
        command = [
            "xcrun", "appintentsmetadataprocessor",
            "--toolchain-dir", str(toolchain_dir()),
            "--module-name", targets[0].get("c99name", args.target),
            "--sdk-root", run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip(),
            "--xcode-version", xcode_build_version(),
            "--platform-family", "macOS",
            "--deployment-target", args.deployment_target,
            "--bundle-identifier", args.bundle_id,
            "--output", str(args.resources),
            "--target-triple", f"arm64-apple-macos{args.deployment_target}",
            "--binary-file", str(args.binary),
            "--source-file-list", str(source_list),
            "--swift-const-vals-list", str(const_list),
            "--compile-time-extraction",
            "--deployment-aware-processing",
            "--force",
        ]
        if not has_app_shortcuts:
            command.append("--no-app-shortcuts-localization")
        processed = subprocess.run(command, capture_output=True, text=True)
        if processed.returncode != 0:
            sys.stderr.write(processed.stdout + processed.stderr)
            raise SystemExit(f"extract_app_intents_metadata: the processor failed for {args.target}")
        warnings = [line for line in processed.stderr.splitlines() if "warning:" in line]
        for line in warnings:
            print(line, file=sys.stderr)

    actions_data = args.resources / "Metadata.appintents" / "extract.actionsdata"
    metadata = json.loads(actions_data.read_text())
    declared = (
        set(metadata.get("actions", {}))
        | {entity for entity in metadata.get("entities", {})}
        | {query for query in metadata.get("queries", {})}
    )
    missing = [name for name in args.expect if name not in declared]
    if missing:
        raise SystemExit(
            f"extract_app_intents_metadata: {args.target} metadata lacks {', '.join(missing)}")

    strings: dict[tuple[str, str], str] = {}
    metadata_strings(metadata, strings)
    write_metadata_tables(strings, targets, args.resources)

    print(
        f"==> App Intents metadata for {args.target}: {len(metadata.get('actions', {}))} intents, "
        f"{len(metadata.get('entities', {}))} entities, {len(strings)} strings"
        + (", App Shortcut phrases" if has_app_shortcuts else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
