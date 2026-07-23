#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from acknowledgments_data import PACKAGE_METADATA, ResolvedPackage, render_acknowledgments
from verify_acknowledgments import acknowledgments_failures


def _resolved_for_real_metadata() -> dict[str, ResolvedPackage]:
    """A resolved-package set covering every identity `PACKAGE_METADATA` knows,
    so `render_acknowledgments` can run without touching the real
    `Package.resolved` files (keeping these tests independent of repo state)."""
    return {
        identity: ResolvedPackage(identity=identity, version="9.9.9", location=f"https://example.invalid/{identity}.git")
        for identity in PACKAGE_METADATA
    }


class AcknowledgmentsVerifierTests(unittest.TestCase):
    def test_passes_when_resource_matches_resolved_graph(self) -> None:
        resolved = _resolved_for_real_metadata()
        rendered = render_acknowledgments(resolved)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ACKNOWLEDGMENTS.md"
            path.write_text(rendered, encoding="utf-8")

            self.assertEqual(acknowledgments_failures(resolved, path), [])

    def test_fails_when_resolved_dependency_has_no_metadata(self) -> None:
        resolved = _resolved_for_real_metadata()
        resolved["totally-new-dependency"] = ResolvedPackage(
            identity="totally-new-dependency",
            version="1.0.0",
            location="https://example.invalid/totally-new-dependency.git",
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ACKNOWLEDGMENTS.md"
            path.write_text("stale placeholder\n", encoding="utf-8")

            failures = acknowledgments_failures(resolved, path)

        self.assertTrue(any("totally-new-dependency" in failure for failure in failures))

    def test_fails_when_metadata_describes_a_removed_dependency(self) -> None:
        resolved = _resolved_for_real_metadata()
        removed_identity = next(iter(resolved))
        del resolved[removed_identity]
        rendered = render_acknowledgments(resolved)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ACKNOWLEDGMENTS.md"
            path.write_text(rendered, encoding="utf-8")

            failures = acknowledgments_failures(resolved, path)

        self.assertTrue(any(removed_identity in failure for failure in failures))

    def test_fails_when_bundled_resource_is_stale(self) -> None:
        resolved = _resolved_for_real_metadata()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ACKNOWLEDGMENTS.md"
            path.write_text("this is not the generated content\n", encoding="utf-8")

            failures = acknowledgments_failures(resolved, path)

        self.assertTrue(any("stale" in failure for failure in failures))

    def test_fails_when_bundled_resource_is_missing(self) -> None:
        resolved = _resolved_for_real_metadata()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "does-not-exist.md"

            failures = acknowledgments_failures(resolved, path)

        self.assertTrue(any("missing" in failure for failure in failures))

    def test_fails_when_a_version_bump_is_not_reflected_in_the_resource(self) -> None:
        resolved = _resolved_for_real_metadata()
        rendered = render_acknowledgments(resolved)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ACKNOWLEDGMENTS.md"
            path.write_text(rendered, encoding="utf-8")

            bumped = dict(resolved)
            some_identity = next(iter(bumped))
            bumped[some_identity] = ResolvedPackage(
                identity=some_identity, version="42.0.0", location=bumped[some_identity].location
            )

            failures = acknowledgments_failures(bumped, path)

        self.assertTrue(any("stale" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
