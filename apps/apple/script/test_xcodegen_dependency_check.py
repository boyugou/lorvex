#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

from xcodegen_dependency_check import dependency_entry, dependency_failures

ROOT = Path(__file__).resolve().parents[1]
PROJECT_YML = ROOT / "Config" / "XcodeGen" / "project.yml"


class XcodeGenDependencyCheckTests(unittest.TestCase):
    def test_dependency_failures_accepts_embedded_dependency(self) -> None:
        source = """
targets:
  LorvexMobileApp:
    dependencies:
      - target: LorvexWatchApp
        embed: true
  LorvexWatchApp:
    type: application
"""

        self.assertEqual(
            dependency_failures(
                source,
                "LorvexMobileApp",
                "LorvexWatchApp",
                require_embed=True,
            ),
            [],
        )

    def test_dependency_failures_rejects_missing_dependency(self) -> None:
        source = """
targets:
  LorvexMobileApp:
    dependencies:
      # - target: LorvexWatchApp
      #   embed: true
"""

        self.assertEqual(
            dependency_failures(
                source,
                "LorvexMobileApp",
                "LorvexWatchApp",
                require_embed=True,
            ),
            ["LorvexMobileApp is missing dependency target LorvexWatchApp"],
        )

    def test_dependency_failures_rejects_unembedded_dependency(self) -> None:
        source = """
targets:
  LorvexMobileApp:
    dependencies:
      - target: LorvexWatchApp
"""

        self.assertEqual(
            dependency_failures(
                source,
                "LorvexMobileApp",
                "LorvexWatchApp",
                require_embed=True,
            ),
            ["LorvexMobileApp dependency LorvexWatchApp must set embed: true"],
        )


class WidgetFrameworkEmbeddingTests(unittest.TestCase):
    """Guards against the launch crash where a widget framework linked by an
    embedded framework is itself not embedded.

    LorvexWidgetViews (embedded in LorvexMobileApp) links LorvexWidgetIntents.
    If the host app does not also list LorvexWidgetIntents, XcodeGen never copies
    it into the app's Frameworks directory and the app crashes on launch with
    dyld "Library not loaded: @rpath/LorvexWidgetIntents.framework". For an
    application target depending on a framework target, XcodeGen embeds by
    default, so the invariant is simply that every such framework is *listed*.
    """

    def test_mobile_app_embeds_every_widget_framework_in_the_link_graph(self) -> None:
        source = PROJECT_YML.read_text(encoding="utf-8")
        required = [
            "LorvexWidgetKitSupport",
            "LorvexWidgetViews",
            "LorvexWidgetIntents",
            "LorvexWidgetExtension",
        ]
        missing = [
            name
            for name in required
            if dependency_entry(source, "LorvexMobileApp", name) is None
        ]
        self.assertEqual(
            missing,
            [],
            f"LorvexMobileApp must depend on (and thus embed) {missing}; "
            "a widget framework left out of the host app crashes it on launch.",
        )


if __name__ == "__main__":
    unittest.main()
