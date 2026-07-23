#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_hotspots import hotspot_failures, swift_source_roots


class HotspotVerifierTests(unittest.TestCase):
    def test_swift_source_roots_include_every_target_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            (sources / "LorvexApple").mkdir(parents=True)
            (sources / "LorvexWidgetViews").mkdir()
            (sources / "LorvexSystemIntents").mkdir()
            (sources / "README.md").write_text("", encoding="utf-8")

            self.assertEqual(
                [path.name for path in swift_source_roots(sources)],
                ["LorvexApple", "LorvexSystemIntents", "LorvexWidgetViews"],
            )

    def test_hotspot_failures_scan_new_apple_platform_targets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources"
            system_intents = sources / "LorvexSystemIntents"
            widget_views = sources / "LorvexWidgetViews"
            system_intents.mkdir(parents=True)
            widget_views.mkdir()
            (system_intents / "SmallIntent.swift").write_text("struct SmallIntent {}\n", encoding="utf-8")
            (widget_views / "LargeWidgetView.swift").write_text(
                "\n".join(f"// line {index}" for index in range(900)) + "\n",
                encoding="utf-8",
            )

            failures = hotspot_failures(
                root=root,
                sources_roots=[sources],
            )

            self.assertEqual(len(failures), 1)
            self.assertIn("Sources/LorvexWidgetViews/LargeWidgetView.swift", failures[0])

    def test_hotspot_failures_scan_both_package_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app_target = root / "Sources" / "LorvexApple"
            core_target = root / "core" / "Sources" / "LorvexDomain"
            app_target.mkdir(parents=True)
            core_target.mkdir(parents=True)
            (app_target / "Ok.swift").write_text("struct Ok {}\n", encoding="utf-8")
            (core_target / "Big.swift").write_text(
                "\n".join(f"// line {index}" for index in range(900)) + "\n",
                encoding="utf-8",
            )

            failures = hotspot_failures(
                root=root,
                sources_roots=[root / "Sources", root / "core" / "Sources"],
            )

            self.assertEqual(len(failures), 1)
            self.assertIn("core/Sources/LorvexDomain/Big.swift", failures[0])


if __name__ == "__main__":
    unittest.main()
