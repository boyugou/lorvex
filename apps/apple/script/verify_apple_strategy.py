#!/usr/bin/env python3
"""Verify Apple-only product strategy invariants in local project files."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from release_strategy import APPLE_RELEASE_STRATEGY


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATH = ROOT / "Package.swift"
RELEASE_MANIFEST_PATH = ROOT / "dist" / "lorvex-apple-release-manifest.json"
MCP_CLIENT_CONFIG_PATH = ROOT / "dist" / "lorvex-apple-mcp-client.json"

FORBIDDEN_CROSS_PLATFORM_PATHS = [
    ROOT / "src-tauri",
    ROOT / "tauri.conf.json",
    ROOT / "tauri.conf.json5",
    ROOT / "package.json",
    ROOT / "package-lock.json",
    ROOT / "pnpm-lock.yaml",
    ROOT / "yarn.lock",
    ROOT / "bun.lockb",
]
FORBIDDEN_CROSS_PLATFORM_PATH_NAMES = {path.name for path in FORBIDDEN_CROSS_PLATFORM_PATHS}
FORBIDDEN_CROSS_PLATFORM_SCAN_ROOTS = [
    ROOT / "Sources",
    ROOT / "Config",
    ROOT / "script",
]
FORBIDDEN_WEB_UI_SUFFIXES = {
    ".css",
    ".html",
    ".js",
    ".jsx",
    ".mjs",
    ".ts",
    ".tsx",
}
ALLOWED_WEB_UI_FILENAMES = set()
FORBIDDEN_CLI_PRODUCT_NAMES = {
    "LorvexCLI",
    "LorvexCommand",
    "lorvex",
    "lvx",
}
FORBIDDEN_CLI_NAME_MARKERS = ("cli", "commandline")
ALLOWED_COMMAND_LINE_HELPERS = {"LorvexMCPHost"}
FORBIDDEN_RUST_MCP_NAME_MARKERS = ("rustmcp", "mcpserver", "mcpdaemon", "mcpsupervisor")
ALLOWED_MCP_SERVER_NAMES = {"LorvexMCPHost"}
THEME_SYSTEM_NAME_MARKERS = ("theme", "themes")
THEME_SYSTEM_ALLOWED_FILENAMES = {"LocalizationTests.swift", "PreferencesPreviewTests.swift"}
FORBIDDEN_SWIFT_CORE_PLACEHOLDER_PATTERNS = (
    r"\bunported\s*\(",
    r"not yet ported to the Swift core",
    r"not yet ported off the Rust",
)
FORBIDDEN_BRIDGE_ERA_FIXTURE_LITERALS = (
    "task-rust-bridge",
)
EMAIL_ADDRESS_PATTERN = re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b")
CLOUD_SYNC_OWNER_TARGETS = {
    "LorvexApple",
    "LorvexCloudSync",
    "LorvexMobile",
    "LorvexMobileApp",
    "LorvexVisionApp",
}
CLOUD_SYNC_CODE_PATTERN = re.compile(
    r"(?m)^\s*(?:@preconcurrency\s+)?import\s+(?:CloudKit|LorvexCloudSync)\b"
    r"|\b(?:CKContainer|CloudSyncEngineCoordinator)\b"
)


EXPECTED_MCP_CLIENT_STRATEGY = {
    "platform_scope": APPLE_RELEASE_STRATEGY["platform_scope"],
    "mcp_host": APPLE_RELEASE_STRATEGY["mcp_host"],
    "mcp_sdk": APPLE_RELEASE_STRATEGY["mcp_sdk"],
}


def package_products(source: str) -> list[str]:
    return re.findall(r'\.(?:executable|library)\s*\(\s*name:\s*"([^"]+)"', source)


def package_targets(source: str) -> list[str]:
    return re.findall(r'\.(?:executableTarget|target|testTarget)\s*\(\s*name:\s*"([^"]+)"', source)


def _swift_lexical_projection(source: str, *, strip_literals: bool) -> str:
    """Blank comments and optionally string literals while preserving offsets."""
    result = list(source)
    index = 0
    block_depth = 0
    line_comment = False
    string_delimiter: str | None = None

    def blank(position: int) -> None:
        if result[position] != "\n":
            result[position] = " "

    while index < len(source):
        if line_comment:
            if source[index] == "\n":
                line_comment = False
            else:
                blank(index)
            index += 1
            continue

        if block_depth:
            if source.startswith("/*", index):
                blank(index)
                blank(index + 1)
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                blank(index)
                blank(index + 1)
                block_depth -= 1
                index += 2
            else:
                blank(index)
                index += 1
            continue

        if string_delimiter is not None:
            if source.startswith(string_delimiter, index):
                if strip_literals:
                    for position in range(index, index + len(string_delimiter)):
                        blank(position)
                index += len(string_delimiter)
                string_delimiter = None
            else:
                if strip_literals:
                    blank(index)
                if source[index] == "\\" and not string_delimiter.startswith('"""'):
                    index += 1
                    if index < len(source):
                        if strip_literals:
                            blank(index)
                        index += 1
                else:
                    index += 1
            continue

        if source.startswith("//", index):
            blank(index)
            blank(index + 1)
            line_comment = True
            index += 2
            continue
        if source.startswith("/*", index):
            blank(index)
            blank(index + 1)
            block_depth = 1
            index += 2
            continue
        if source.startswith('"""', index):
            string_delimiter = '"""'
            if strip_literals:
                for position in range(index, index + 3):
                    blank(position)
            index += 3
            continue
        if source[index] == '"':
            string_delimiter = '"'
            if strip_literals:
                blank(index)
            index += 1
            continue
        index += 1

    return "".join(result)


def package_target_declarations(source: str) -> list[tuple[str, str, str]]:
    """Return target kind, name, and comment-free declaration body."""
    skeleton = _swift_lexical_projection(source, strip_literals=True)
    declarations: list[tuple[str, str, str]] = []
    call_pattern = re.compile(r"\.(executableTarget|testTarget|target)\s*\(")

    for match in call_pattern.finditer(skeleton):
        opening = skeleton.find("(", match.start())
        depth = 0
        closing: int | None = None
        for index in range(opening, len(skeleton)):
            if skeleton[index] == "(":
                depth += 1
            elif skeleton[index] == ")":
                depth -= 1
                if depth == 0:
                    closing = index
                    break
        if closing is None:
            continue

        body = _swift_lexical_projection(
            source[opening + 1 : closing],
            strip_literals=False,
        )
        name_match = re.search(r'\bname\s*:\s*"([^"]+)"', body)
        if name_match is not None:
            declarations.append((match.group(1), name_match.group(1), body))

    return declarations


def forbidden_cloud_sync_target_dependencies(package_source: str) -> list[str]:
    """Find production targets that transitively violate CloudSync ownership."""
    declarations = package_target_declarations(package_source)
    declared_names = {name for _, name, _ in declarations}
    dependency_names = declared_names | {"LorvexCloudSync"}
    dependencies: dict[str, set[str]] = {}
    for _, name, body in declarations:
        dependencies[name] = {
            candidate
            for candidate in dependency_names
            if re.search(rf'"{re.escape(candidate)}"', body)
        }

    def reaches_cloud_sync(name: str, visited: set[str]) -> bool:
        if name == "LorvexCloudSync":
            return True
        if name in visited:
            return False
        visited.add(name)
        return any(
            reaches_cloud_sync(dependency, visited)
            for dependency in dependencies.get(name, set())
        )

    forbidden: list[str] = []
    for kind, name, _ in declarations:
        if kind == "testTarget" or name in CLOUD_SYNC_OWNER_TARGETS:
            continue
        if reaches_cloud_sync(name, set()):
            forbidden.append(name)
    return sorted(forbidden)


def forbidden_cloud_sync_source_paths(
    source_root: Path | None = None,
    root: Path = ROOT,
) -> list[str]:
    """Find non-owner source modules that import or construct CloudSync."""
    scan_root = source_root or root / "Sources"
    if not scan_root.exists():
        return []

    forbidden: list[str] = []
    for path in scan_root.rglob("*.swift"):
        relative_to_sources = path.relative_to(scan_root)
        if not relative_to_sources.parts:
            continue
        if relative_to_sources.parts[0] in CLOUD_SYNC_OWNER_TARGETS:
            continue
        code = _swift_lexical_projection(
            path.read_text(encoding="utf-8"),
            strip_literals=True,
        )
        if CLOUD_SYNC_CODE_PATTERN.search(code):
            forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def normalized_identifier(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def forbidden_cli_surface_names(names: set[str]) -> list[str]:
    forbidden: list[str] = []
    for name in sorted(names):
        if name in ALLOWED_COMMAND_LINE_HELPERS:
            continue
        normalized_name = normalized_identifier(name)
        if name in FORBIDDEN_CLI_PRODUCT_NAMES:
            forbidden.append(name)
            continue
        if any(marker in normalized_name for marker in FORBIDDEN_CLI_NAME_MARKERS):
            forbidden.append(name)
    return forbidden


def forbidden_rust_mcp_surface_names(names: set[str]) -> list[str]:
    forbidden: list[str] = []
    for name in sorted(names):
        if name in ALLOWED_MCP_SERVER_NAMES:
            continue
        normalized_name = normalized_identifier(name)
        if any(marker in normalized_name for marker in FORBIDDEN_RUST_MCP_NAME_MARKERS):
            forbidden.append(name)
    return forbidden


def forbidden_rust_mcp_source_paths() -> list[str]:
    forbidden: list[str] = []
    roots = [ROOT / "Sources"]
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_dir() and path.suffix not in {".swift", ".rs"}:
                continue
            name = path.stem if path.is_file() else path.name
            if name in ALLOWED_MCP_SERVER_NAMES:
                continue
            normalized_name = normalized_identifier(name)
            if any(marker in normalized_name for marker in FORBIDDEN_RUST_MCP_NAME_MARKERS):
                forbidden.append(str(path.relative_to(ROOT)))
    return sorted(forbidden)


def forbidden_cross_platform_paths() -> list[str]:
    forbidden: set[str] = set()
    for path in FORBIDDEN_CROSS_PLATFORM_PATHS:
        if path.exists():
            forbidden.add(str(path.relative_to(ROOT)))

    for root in FORBIDDEN_CROSS_PLATFORM_SCAN_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.name in FORBIDDEN_CROSS_PLATFORM_PATH_NAMES:
                forbidden.add(str(path.relative_to(ROOT)))

    return sorted(forbidden)


def forbidden_web_ui_source_paths(
    roots: list[Path] | None = None,
    root: Path = ROOT,
) -> list[str]:
    forbidden: list[str] = []
    scan_roots = roots or [root / "Sources", root / "Config"]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if path.is_dir() or path.name in ALLOWED_WEB_UI_FILENAMES:
                continue
            if path.suffix.lower() in FORBIDDEN_WEB_UI_SUFFIXES:
                forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def forbidden_theme_system_paths(
    roots: list[Path] | None = None,
    root: Path = ROOT,
) -> list[str]:
    forbidden: list[str] = []
    scan_roots = roots or [root / "Sources", root / "Tests"]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if path.name in THEME_SYSTEM_ALLOWED_FILENAMES:
                continue
            if not path.is_dir() and path.suffix != ".swift":
                continue
            name = path.stem.lower() if path.is_file() else path.name.lower()
            if any(marker in name for marker in THEME_SYSTEM_NAME_MARKERS):
                forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def forbidden_swift_core_placeholder_sources(
    roots: list[Path] | None = None,
    root: Path = ROOT,
) -> list[str]:
    forbidden: list[str] = []
    scan_roots = roots or [root / "Sources" / "LorvexCore" / "Services"]
    patterns = [
        re.compile(pattern)
        for pattern in FORBIDDEN_SWIFT_CORE_PLACEHOLDER_PATTERNS
    ]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("SwiftLorvexCoreService*.swift"):
            if path.is_dir():
                continue
            source = path.read_text(encoding="utf-8")
            if any(pattern.search(source) for pattern in patterns):
                forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def forbidden_bridge_era_fixture_sources(
    roots: list[Path] | None = None,
    root: Path = ROOT,
) -> list[str]:
    forbidden: list[str] = []
    scan_roots = roots or [root / "Sources", root / "Tests"]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*.swift"):
            source = path.read_text(encoding="utf-8")
            if any(literal in source for literal in FORBIDDEN_BRIDGE_ERA_FIXTURE_LITERALS):
                forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def forbidden_email_reference_paths(
    roots: list[Path] | None = None,
    root: Path = ROOT,
) -> list[str]:
    forbidden: list[str] = []
    scan_roots = roots or [root / "docs", root / "README.md", root / "CLAUDE.md"]
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        paths = [scan_root] if scan_root.is_file() else scan_root.rglob("*")
        for path in paths:
            if path.is_dir() or path.suffix.lower() not in {".md", ".txt"}:
                continue
            if EMAIL_ADDRESS_PATTERN.search(path.read_text(encoding="utf-8")):
                forbidden.append(str(path.relative_to(root)))
    return sorted(forbidden)


def mcp_client_strategy_failures(config: object) -> list[str]:
    if not isinstance(config, dict):
        return [f"MCP client config must be a JSON object: {config!r}"]

    lorvex = config.get("lorvex")
    if not isinstance(lorvex, dict):
        return [f"MCP client config missing lorvex metadata: {lorvex!r}"]

    strategy = lorvex.get("strategy")
    if strategy != EXPECTED_MCP_CLIENT_STRATEGY:
        return [f"MCP client config strategy mismatch: {strategy!r}"]
    return []


def release_manifest_strategy_failures(manifest: object) -> list[str]:
    if not isinstance(manifest, dict):
        return [f"release manifest must be a JSON object: {manifest!r}"]

    strategy = manifest.get("strategy")
    if strategy != APPLE_RELEASE_STRATEGY:
        return [f"release strategy mismatch: {strategy!r}"]
    return []


def main() -> int:
    failures: list[str] = []
    package_source = PACKAGE_PATH.read_text(encoding="utf-8")

    if "https://github.com/modelcontextprotocol/swift-sdk.git" not in package_source:
        failures.append("Package.swift does not depend on modelcontextprotocol/swift-sdk")
    if '.product(name: "MCP", package: "swift-sdk")' not in package_source:
        failures.append("Package.swift does not wire the MCP product from swift-sdk")
    if "tauri" in package_source.lower():
        failures.append("Package.swift contains a Tauri reference; Apple edition must stay native Swift")

    if ".macOS(" not in package_source:
        failures.append("Package.swift does not declare macOS as a supported platform")
    for platform in [".iOS(", ".visionOS(", ".watchOS("]:
        if platform not in package_source:
            failures.append(f"Package.swift does not declare {platform.removesuffix('(')} support")
    for forbidden in [".linux", ".windows", "Windows", "Linux"]:
        if forbidden in package_source:
            failures.append(f"Package.swift contains forbidden non-Apple platform marker: {forbidden}")

    products = set(package_products(package_source))
    targets = set(package_targets(package_source))
    forbidden_products = forbidden_cli_surface_names(products)
    if forbidden_products:
        failures.append(f"Package.swift declares forbidden CLI product(s): {forbidden_products}")
    forbidden_targets = forbidden_cli_surface_names(targets)
    if forbidden_targets:
        failures.append(f"Package.swift declares forbidden CLI target(s): {forbidden_targets}")
    forbidden_mcp_products = forbidden_rust_mcp_surface_names(products)
    if forbidden_mcp_products:
        failures.append(
            f"Package.swift declares forbidden Rust MCP server fallback product(s): {forbidden_mcp_products}"
        )
    forbidden_mcp_targets = forbidden_rust_mcp_surface_names(targets)
    if forbidden_mcp_targets:
        failures.append(
            f"Package.swift declares forbidden Rust MCP server fallback target(s): {forbidden_mcp_targets}"
        )
    if "LorvexMCPHost" not in products:
        failures.append("Package.swift does not declare the Swift-native LorvexMCPHost product")
    if "LorvexMCPHost" not in targets:
        failures.append("Package.swift does not declare the Swift-native LorvexMCPHost target")

    cloud_sync_dependency_targets = forbidden_cloud_sync_target_dependencies(package_source)
    if cloud_sync_dependency_targets:
        failures.append(
            "non-app production target(s) depend on LorvexCloudSync; only the main app "
            "may own CloudKit synchronization: "
            + ", ".join(cloud_sync_dependency_targets)
        )

    cloud_sync_source_paths = forbidden_cloud_sync_source_paths()
    if cloud_sync_source_paths:
        failures.append(
            "non-app source(s) import or construct CloudSync/CloudKit; MCP, widgets, "
            "App Intents, watch, and other helpers must write only through local core/outbox: "
            + ", ".join(cloud_sync_source_paths)
        )

    cross_platform_paths = forbidden_cross_platform_paths()
    if cross_platform_paths:
        failures.append(
            "forbidden cross-platform/Tauri artifact(s) exist in Apple edition: "
            + ", ".join(cross_platform_paths)
        )

    web_ui_paths = forbidden_web_ui_source_paths()
    if web_ui_paths:
        failures.append(
            "forbidden web UI source artifact(s); keep Apple edition SwiftUI/AppKit-native: "
            + ", ".join(web_ui_paths)
        )

    theme_paths = forbidden_theme_system_paths()
    if theme_paths:
        failures.append(
            "forbidden custom theme-system source path(s); use system appearance instead: "
            + ", ".join(theme_paths)
        )
    rust_mcp_paths = forbidden_rust_mcp_source_paths()
    if rust_mcp_paths:
        failures.append(
            "forbidden Rust MCP server fallback source path(s); keep MCP Swift-native: "
            + ", ".join(rust_mcp_paths)
        )
    swift_core_placeholders = forbidden_swift_core_placeholder_sources()
    if swift_core_placeholders:
        failures.append(
            "forbidden Swift core placeholder source(s); implement concrete service methods "
            "or remove dead bridge-era helpers: "
            + ", ".join(swift_core_placeholders)
        )
    bridge_era_fixture_sources = forbidden_bridge_era_fixture_sources()
    if bridge_era_fixture_sources:
        failures.append(
            "Apple source/test fixtures still use bridge-era Rust task ids: "
            + ", ".join(bridge_era_fixture_sources)
        )
    email_reference_paths = forbidden_email_reference_paths()
    if email_reference_paths:
        failures.append(
            "Apple docs contain email-like contact/credential placeholders; use GitHub-only "
            "contact routes and opaque account placeholders instead: "
            + ", ".join(email_reference_paths)
        )

    if RELEASE_MANIFEST_PATH.is_file():
        manifest = json.loads(RELEASE_MANIFEST_PATH.read_text(encoding="utf-8"))
        failures.extend(release_manifest_strategy_failures(manifest))

    if MCP_CLIENT_CONFIG_PATH.is_file():
        mcp_config = json.loads(MCP_CLIENT_CONFIG_PATH.read_text(encoding="utf-8"))
        failures.extend(mcp_client_strategy_failures(mcp_config))

    if failures:
        print("Apple strategy verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Apple strategy verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
