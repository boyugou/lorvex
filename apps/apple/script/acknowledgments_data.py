#!/usr/bin/env python3
"""Deterministic third-party dependency inventory and ACKNOWLEDGMENTS rendering.

Shared by `generate_acknowledgments.py` (writes the bundled resource) and
`verify_acknowledgments.py` (fails the build when the resource has drifted
from the resolved dependency graph). The set of packages actually linked into
the shipping app is read from `Package.resolved` — never hand-maintained —
so a dependency add/remove/bump only requires updating `PACKAGE_METADATA`
(and, for a new package, adding its license text under
`third_party_licenses/`) to keep the generated resource in sync.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LICENSE_TEXT_DIR = Path(__file__).resolve().parent / "third_party_licenses"
RESOLVED_FILES = (ROOT / "Package.resolved", ROOT / "core" / "Package.resolved")
ACKNOWLEDGMENTS_PATH = ROOT / "Sources" / "LorvexCore" / "Resources" / "ACKNOWLEDGMENTS.md"
APACHE_LICENSE_TEXT_PATH = LICENSE_TEXT_DIR / "APACHE-2.0.txt"


@dataclass(frozen=True)
class PackageLicense:
    """Static license metadata for one resolved SwiftPM dependency.

    `spdx` is the identifier reproduced in the generated document. `extra_text_file`
    (relative to `third_party_licenses/`) holds the package's own verbatim
    LICENSE/NOTICE text — required for every non-Apache-2.0 package (MIT/BSD
    text carries the copyright line itself) and for any Apache-2.0 package that
    ships a NOTICE file (Apache-2.0 section 4(d) requires reproducing it).
    `None` only for Apache-2.0 packages confirmed to ship no NOTICE file, where
    the shared Apache-2.0 appendix text alone satisfies the license.

    `needs_apache_appendix` marks a package whose full Apache-2.0 legal terms
    are supplied only by the shared appendix (`extra_text_file` is either
    `None` or a NOTICE-only excerpt). `swift-sdk`'s own LICENSE file already
    reproduces the complete Apache-2.0 text itself, so it is `False` there —
    listing it as appendix-covered would misattribute the Swift.org runtime
    library exception appended to the shared appendix text to a non-Swift.org
    project.
    """

    display_name: str
    spdx: str
    extra_text_file: str | None
    extra_text_label: str | None = None
    needs_apache_appendix: bool = False


# Keyed by the SwiftPM "identity" field in Package.resolved. Every identity
# resolved by either `Package.resolved` file must have an entry here or
# `verify_acknowledgments.py` fails the build — this is the single place a
# dependency add/bump/removal must be reflected.
PACKAGE_METADATA: dict[str, PackageLicense] = {
    "eventsource": PackageLicense(
        display_name="eventsource",
        spdx="MIT",
        extra_text_file="eventsource.LICENSE.txt",
        extra_text_label="License",
    ),
    "grdb.swift": PackageLicense(
        display_name="GRDB.swift",
        spdx="MIT",
        extra_text_file="GRDB.swift.LICENSE.txt",
        extra_text_label="License",
    ),
    "swift-atomics": PackageLicense(
        display_name="swift-atomics",
        spdx="Apache-2.0",
        extra_text_file=None,
        needs_apache_appendix=True,
    ),
    "swift-cmark": PackageLicense(
        display_name="swift-cmark",
        spdx="BSD-2-Clause",
        extra_text_file="swift-cmark.LICENSE.txt",
        extra_text_label="License",
    ),
    "swift-collections": PackageLicense(
        display_name="swift-collections",
        spdx="Apache-2.0",
        extra_text_file=None,
        needs_apache_appendix=True,
    ),
    "swift-log": PackageLicense(
        display_name="swift-log",
        spdx="Apache-2.0",
        extra_text_file="swift-log.NOTICE.txt",
        extra_text_label="NOTICE",
        needs_apache_appendix=True,
    ),
    "swift-markdown": PackageLicense(
        display_name="swift-markdown",
        spdx="Apache-2.0",
        extra_text_file="swift-markdown.NOTICE.txt",
        extra_text_label="NOTICE",
        needs_apache_appendix=True,
    ),
    "swift-nio": PackageLicense(
        display_name="swift-nio",
        spdx="Apache-2.0",
        extra_text_file="swift-nio.NOTICE.txt",
        extra_text_label="NOTICE",
        needs_apache_appendix=True,
    ),
    "swift-sdk": PackageLicense(
        display_name="swift-sdk (Model Context Protocol)",
        spdx="Apache-2.0 OR MIT",
        extra_text_file="swift-sdk.LICENSE.txt",
        extra_text_label="License",
    ),
    "swift-system": PackageLicense(
        display_name="swift-system",
        spdx="Apache-2.0",
        extra_text_file=None,
        needs_apache_appendix=True,
    ),
}


@dataclass(frozen=True)
class ResolvedPackage:
    identity: str
    version: str
    location: str


def load_resolved_packages(paths: tuple[Path, ...] = RESOLVED_FILES) -> dict[str, ResolvedPackage]:
    """Union of every pin across `paths`, keyed by identity.

    Raises `ValueError` if the same identity resolves to two different
    versions across the files (it must be pinned identically everywhere it is
    reachable, since SwiftPM links a single copy into the final app).
    """
    resolved: dict[str, ResolvedPackage] = {}
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(f"Package.resolved not found: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        for pin in data.get("pins", []):
            identity = pin.get("identity")
            state = pin.get("state", {})
            version = state.get("version") or state.get("revision")
            location = pin.get("location", "")
            if not isinstance(identity, str) or not identity:
                raise ValueError(f"{path} has a pin with no identity: {pin!r}")
            if not isinstance(version, str) or not version:
                raise ValueError(f"{path} pin {identity!r} has no version/revision: {pin!r}")
            existing = resolved.get(identity)
            if existing is not None and existing.version != version:
                raise ValueError(
                    f"{identity!r} resolves to conflicting versions across "
                    f"{RESOLVED_FILES}: {existing.version!r} vs {version!r}"
                )
            resolved[identity] = ResolvedPackage(identity=identity, version=version, location=location)
    return resolved


def render_acknowledgments(resolved: dict[str, ResolvedPackage]) -> str:
    """Render the bundled ACKNOWLEDGMENTS.md text deterministically.

    Fails loudly (raises `KeyError`) rather than silently omitting a package
    when `resolved` contains an identity `PACKAGE_METADATA` does not describe —
    every currently-linked dependency must have reviewed license metadata
    before it can ship.
    """
    apache_text = APACHE_LICENSE_TEXT_PATH.read_text(encoding="utf-8").strip()

    lines: list[str] = []
    lines.append("# Third-Party Acknowledgments")
    lines.append("")
    lines.append(
        "Lorvex for Apple platforms is Apache-2.0 licensed and built with the "
        "following third-party software. This document is generated by "
        "`script/generate_acknowledgments.py` from the resolved SwiftPM "
        "dependency graph (`Package.resolved`) and each package's own LICENSE / "
        "NOTICE file — do not hand-edit it; regenerate it instead."
    )
    lines.append("")

    for identity in sorted(resolved):
        package = resolved[identity]
        metadata = PACKAGE_METADATA[identity]
        lines.append(f"## {metadata.display_name} {package.version}")
        lines.append("")
        lines.append(f"- Repository: {package.location}")
        lines.append(f"- License: {metadata.spdx}")
        lines.append("")
        if metadata.extra_text_file:
            extra_text = (LICENSE_TEXT_DIR / metadata.extra_text_file).read_text(encoding="utf-8").strip()
            lines.append(f"### {metadata.extra_text_label}")
            lines.append("")
            lines.append("```")
            lines.append(extra_text)
            lines.append("```")
            lines.append("")
        if metadata.needs_apache_appendix:
            lines.append(
                "Licensed under the Apache License, Version 2.0; the full license "
                "text is reproduced once in the appendix below rather than per "
                "package."
            )
            lines.append("")

    lines.append("## Appendix: Apache License, Version 2.0")
    lines.append("")
    lines.append(
        "The following packages are licensed under the Apache License, Version "
        "2.0, whose full text (including the Swift.org runtime library "
        "exception these packages carry) is reproduced once here rather than "
        "once per package: "
        + ", ".join(
            sorted(
                PACKAGE_METADATA[identity].display_name
                for identity in resolved
                if PACKAGE_METADATA[identity].needs_apache_appendix
            )
        )
        + "."
    )
    lines.append("")
    lines.append("```")
    lines.append(apache_text)
    lines.append("```")
    lines.append("")

    return "\n".join(lines)


def known_identities_missing_metadata(resolved: dict[str, ResolvedPackage]) -> list[str]:
    return sorted(set(resolved) - set(PACKAGE_METADATA))


def stale_metadata_identities(resolved: dict[str, ResolvedPackage]) -> list[str]:
    return sorted(set(PACKAGE_METADATA) - set(resolved))
