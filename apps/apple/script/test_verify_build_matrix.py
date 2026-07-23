#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_build_matrix import (
    build_matrix_failures,
    swiftpm_executable_products,
    verify_all_build_products,
    verify_all_launch_cleanup_failures,
)


TEST_METADATA = {
    "APP_NAME": "LorvexApple",
    "MOBILE_APP_NAME": "LorvexMobileApp",
    "VISION_APP_NAME": "LorvexVisionApp",
    "WATCH_APP_NAME": "LorvexWatchApp",
    "MCP_HOST_PRODUCT": "LorvexMCPHost",
    "WIDGET_EXECUTABLE": "LorvexFocusWidget",
}

# The safe cleanup pattern verify_all.sh actually uses: track $APP_NAME's
# newly-launched PID via `pgrep`, then reap it with a bare `kill` — never a
# global `pkill -x` that could kill an already-running instance the gate
# itself never spawned.
SAFE_CLEANUP_SNIPPET = """
        pgrep -x "$APP_NAME" 2>/dev/null || true
        kill "$pid" >/dev/null 2>&1 || true
"""


class VerifyBuildMatrixTests(unittest.TestCase):
    def test_swiftpm_executable_products_extracts_product_names(self) -> None:
        source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .library(name: "LorvexCore", targets: ["LorvexCore"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        """

        self.assertEqual(
            swiftpm_executable_products(source),
            {"LorvexApple", "LorvexVisionApp"},
        )

    def test_verify_all_build_products_expands_metadata_variables(self) -> None:
        script = """
        swift build --product "$APP_NAME"
        swift build --product "$VISION_APP_NAME"
        swift build --product LorvexWidgetBundle
        """

        self.assertEqual(
            verify_all_build_products(script, TEST_METADATA),
            {"LorvexApple", "LorvexVisionApp", "LorvexWidgetBundle"},
        )

    def test_launch_cleanup_accepts_the_safe_tracked_pid_pattern(self) -> None:
        self.assertEqual(verify_all_launch_cleanup_failures(SAFE_CLEANUP_SNIPPET), [])

    def test_launch_cleanup_rejects_a_global_pkill(self) -> None:
        script = """
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        """ + SAFE_CLEANUP_SNIPPET

        failures = verify_all_launch_cleanup_failures(script)
        self.assertEqual(len(failures), 1)
        self.assertIn("pkill -x", failures[0])

    def test_launch_cleanup_rejects_dropping_app_name_tracking_entirely(self) -> None:
        # No mention of $APP_NAME's PID at all: the smoke launch in
        # `build_and_run.sh --verify` would leak a running process forever.
        failures = verify_all_launch_cleanup_failures("swift build --product \"$APP_NAME\"\n")
        self.assertEqual(len(failures), 1)
        self.assertIn("pgrep -x", failures[0])

    def test_launch_cleanup_rejects_tracking_without_ever_killing(self) -> None:
        script = 'pgrep -x "$APP_NAME" 2>/dev/null || true\n'  # tracked, never killed

        failures = verify_all_launch_cleanup_failures(script)
        self.assertEqual(len(failures), 1)
        self.assertIn("never kills", failures[0])

    def test_build_matrix_accepts_complete_contract(self) -> None:
        package_source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"]),
        """
        script_source = (
            SAFE_CLEANUP_SNIPPET
            + """
        swift build --product "$APP_NAME"
        swift build --product "$MOBILE_APP_NAME"
        swift build --product "$VISION_APP_NAME"
        swift build --product "$WIDGET_EXECUTABLE"
        swift build --product "$WATCH_APP_NAME"
        swift build --product "$MCP_HOST_PRODUCT"
        swift build --product LorvexWidgetBundle
        swift build --product LorvexWatchComplication
        python3 -m py_compile script/xcodegen_dependency_check.py
        ./script/xcodegen_dependency_check.py --owner LorvexMobileApp --dependency LorvexWatchApp --require-embed
        ./script/verify_packaging.sh
        """
        )

        self.assertEqual(build_matrix_failures(package_source, script_source, TEST_METADATA), [])

    def test_build_matrix_rejects_missing_product_build(self) -> None:
        package_source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"]),
        """
        script_source = (
            SAFE_CLEANUP_SNIPPET
            + """
        swift build --product "$APP_NAME"
        swift build --product "$MOBILE_APP_NAME"
        swift build --product "$WIDGET_EXECUTABLE"
        swift build --product "$WATCH_APP_NAME"
        swift build --product "$MCP_HOST_PRODUCT"
        swift build --product LorvexWidgetBundle
        swift build --product LorvexWatchComplication
        """
        )

        self.assertEqual(
            build_matrix_failures(package_source, script_source, TEST_METADATA),
            [
                "Package.swift missing required executable product(s): ['LorvexVisionApp']",
                "verify_all.sh does not build product(s): ['LorvexVisionApp']",
                "verify_all.sh misses required gate command(s): ['./script/verify_packaging.sh', "
                "'./script/xcodegen_dependency_check.py']",
            ],
        )

    def test_build_matrix_rejects_any_unbuilt_executable_product(self) -> None:
        package_source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"]),
        .executable(name: "LorvexMenuBarHelper", targets: ["LorvexMenuBarHelper"]),
        """
        script_source = (
            SAFE_CLEANUP_SNIPPET
            + """
        swift build --product "$APP_NAME"
        swift build --product "$MOBILE_APP_NAME"
        swift build --product "$VISION_APP_NAME"
        swift build --product "$WIDGET_EXECUTABLE"
        swift build --product "$WATCH_APP_NAME"
        swift build --product "$MCP_HOST_PRODUCT"
        swift build --product LorvexWidgetBundle
        swift build --product LorvexWatchComplication
        python3 -m py_compile script/xcodegen_dependency_check.py
        ./script/xcodegen_dependency_check.py --owner LorvexMobileApp --dependency LorvexWatchApp --require-embed
        ./script/verify_packaging.sh
        """
        )

        self.assertEqual(
            build_matrix_failures(package_source, script_source, TEST_METADATA),
            [
                "verify_all.sh does not build executable product(s) declared in Package.swift: "
                "['LorvexMenuBarHelper']"
            ],
        )

    def test_build_matrix_rejects_missing_required_gate_command(self) -> None:
        package_source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"]),
        """
        script_source = (
            SAFE_CLEANUP_SNIPPET
            + """
        swift build --product "$APP_NAME"
        swift build --product "$MOBILE_APP_NAME"
        swift build --product "$VISION_APP_NAME"
        swift build --product "$WIDGET_EXECUTABLE"
        swift build --product "$WATCH_APP_NAME"
        swift build --product "$MCP_HOST_PRODUCT"
        swift build --product LorvexWidgetBundle
        swift build --product LorvexWatchComplication
        python3 -m py_compile script/xcodegen_dependency_check.py
        ./script/xcodegen_dependency_check.py --owner LorvexMobileApp --dependency LorvexWatchApp --require-embed
        """
        )

        self.assertEqual(
            build_matrix_failures(package_source, script_source, TEST_METADATA),
            ["verify_all.sh misses required gate command(s): ['./script/verify_packaging.sh']"],
        )

    def test_build_matrix_rejects_a_regression_to_global_pkill(self) -> None:
        package_source = """
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"]),
        """
        script_source = (
            """
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        """
            + """
        swift build --product "$APP_NAME"
        swift build --product "$MOBILE_APP_NAME"
        swift build --product "$VISION_APP_NAME"
        swift build --product "$WIDGET_EXECUTABLE"
        swift build --product "$WATCH_APP_NAME"
        swift build --product "$MCP_HOST_PRODUCT"
        swift build --product LorvexWidgetBundle
        swift build --product LorvexWatchComplication
        python3 -m py_compile script/xcodegen_dependency_check.py
        ./script/xcodegen_dependency_check.py --owner LorvexMobileApp --dependency LorvexWatchApp --require-embed
        ./script/verify_packaging.sh
        """
        )

        failures = build_matrix_failures(package_source, script_source, TEST_METADATA)
        self.assertEqual(len(failures), 2)
        self.assertIn("pkill -x", failures[0])
        self.assertIn("pgrep -x", failures[1])


if __name__ == "__main__":
    unittest.main()
