#!/usr/bin/env python3
from __future__ import annotations

import unittest
import tempfile
from pathlib import Path

from verify_apple_strategy import (
    forbidden_bridge_era_fixture_sources,
    forbidden_cloud_sync_source_paths,
    forbidden_cloud_sync_target_dependencies,
    forbidden_email_reference_paths,
    forbidden_swift_core_placeholder_sources,
    forbidden_theme_system_paths,
    forbidden_web_ui_source_paths,
    mcp_client_strategy_failures,
    release_manifest_strategy_failures,
)
from release_strategy import APPLE_RELEASE_STRATEGY


class VerifyAppleStrategyTests(unittest.TestCase):
    def test_cloud_sync_dependency_check_rejects_non_app_target(self) -> None:
        package_source = """
        let package = Package(targets: [
            .target(
                name: "LorvexMCPHost",
                dependencies: ["LorvexCore", "LorvexCloudSync"]
            ),
            .target(
                name: "LorvexWidgetExtension",
                dependencies: ["LorvexCore"]
            ),
        ])
        """

        self.assertEqual(
            forbidden_cloud_sync_target_dependencies(package_source),
            ["LorvexMCPHost"],
        )

    def test_cloud_sync_dependency_check_rejects_transitive_non_app_target(self) -> None:
        package_source = """
        let package = Package(targets: [
            .target(
                name: "SharedRuntime",
                dependencies: ["LorvexCloudSync"]
            ),
            .executableTarget(
                name: "LorvexMCPHost",
                dependencies: ["LorvexCore", "SharedRuntime"]
            ),
            .target(name: "LorvexCloudSync", dependencies: []),
            .target(name: "LorvexCore", dependencies: []),
        ])
        """

        self.assertEqual(
            forbidden_cloud_sync_target_dependencies(package_source),
            ["LorvexMCPHost", "SharedRuntime"],
        )

    def test_cloud_sync_dependency_check_accepts_app_owners_and_tests(self) -> None:
        package_source = """
        let package = Package(targets: [
            .target(
                name: "LorvexMobile",
                dependencies: ["LorvexCore", "LorvexCloudSync"]
            ),
            .executableTarget(
                name: "LorvexApple",
                dependencies: ["LorvexCloudSync"]
            ),
            .testTarget(
                name: "LorvexAppleTests",
                dependencies: ["LorvexCloudSync"]
            ),
            // dependencies: ["LorvexCloudSync"]
            .target(name: "LorvexSystemIntents", dependencies: ["LorvexCore"]),
        ])
        """

        self.assertEqual(
            forbidden_cloud_sync_target_dependencies(package_source),
            [],
        )

    def test_cloud_sync_source_check_rejects_non_app_cloudkit_ownership(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mcp_sources = root / "Sources" / "LorvexMCPHost"
            widget_sources = root / "Sources" / "LorvexWidgetExtension"
            watch_sources = root / "Sources" / "LorvexWatch"
            mcp_sources.mkdir(parents=True)
            widget_sources.mkdir(parents=True)
            watch_sources.mkdir(parents=True)
            (mcp_sources / "Host.swift").write_text(
                "import LorvexCloudSync\n",
                encoding="utf-8",
            )
            (widget_sources / "Widget.swift").write_text(
                "let coordinator: CloudSyncEngineCoordinator?\n",
                encoding="utf-8",
            )
            (watch_sources / "Watch.swift").write_text(
                "@preconcurrency import CloudKit\n",
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_cloud_sync_source_paths(
                    source_root=root / "Sources",
                    root=root,
                ),
                [
                    "Sources/LorvexMCPHost/Host.swift",
                    "Sources/LorvexWatch/Watch.swift",
                    "Sources/LorvexWidgetExtension/Widget.swift",
                ],
            )

    def test_cloud_sync_source_check_accepts_owner_and_ignores_comments_and_strings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app_sources = root / "Sources" / "LorvexApple"
            intent_sources = root / "Sources" / "LorvexSystemIntents"
            app_sources.mkdir(parents=True)
            intent_sources.mkdir(parents=True)
            (app_sources / "Bootstrap.swift").write_text(
                "import CloudKit\nlet coordinator: CloudSyncEngineCoordinator?\n",
                encoding="utf-8",
            )
            (intent_sources / "Intent.swift").write_text(
                """
                // import CloudKit
                /* CloudSyncEngineCoordinator must stay in the main app. */
                let documentation = "CKContainer is intentionally unavailable here"
                """,
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_cloud_sync_source_paths(
                    source_root=root / "Sources",
                    root=root,
                ),
                [],
            )

    def test_mcp_client_strategy_accepts_swift_native_apple_config(self) -> None:
        self.assertEqual(
            mcp_client_strategy_failures(
                {
                    "lorvex": {
                        "strategy": {
                            "platform_scope": "apple-only",
                            "mcp_host": "swift-native",
                            "mcp_sdk": "modelcontextprotocol/swift-sdk",
                        }
                    }
                }
            ),
            [],
        )

    def test_mcp_client_strategy_rejects_missing_lorvex_metadata(self) -> None:
        self.assertEqual(
            mcp_client_strategy_failures({"mcpServers": {}}),
            ["MCP client config missing lorvex metadata: None"],
        )

    def test_mcp_client_strategy_rejects_non_swift_mcp_host(self) -> None:
        self.assertEqual(
            mcp_client_strategy_failures(
                {
                    "lorvex": {
                        "strategy": {
                            "platform_scope": "apple-only",
                            "mcp_host": "rust",
                            "mcp_sdk": "modelcontextprotocol/swift-sdk",
                        }
                    }
                }
            ),
            [
                "MCP client config strategy mismatch: "
                "{'platform_scope': 'apple-only', 'mcp_host': 'rust', "
                "'mcp_sdk': 'modelcontextprotocol/swift-sdk'}"
            ],
        )

    def test_release_manifest_strategy_accepts_apple_only_swift_native_metadata(self) -> None:
        self.assertEqual(
            release_manifest_strategy_failures(
                {
                    "strategy": APPLE_RELEASE_STRATEGY
                }
            ),
            [],
        )

    def test_release_manifest_strategy_rejects_non_swift_mcp_host(self) -> None:
        self.assertEqual(
            release_manifest_strategy_failures(
                {
                    "strategy": {
                        "platform_scope": "apple-only",
                        "mcp_host": "rust",
                        "mcp_sdk": "modelcontextprotocol/swift-sdk",
                    }
                }
            ),
            [
                "release strategy mismatch: "
                "{'platform_scope': 'apple-only', 'mcp_host': 'rust', "
                "'mcp_sdk': 'modelcontextprotocol/swift-sdk'}"
            ],
        )

    def test_forbidden_web_ui_source_paths_rejects_react_and_css_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            sources.mkdir(parents=True)
            (sources / "NativeView.swift").write_text("struct NativeView {}\n", encoding="utf-8")
            (sources / "LegacyPane.tsx").write_text("export const LegacyPane = () => null\n", encoding="utf-8")
            (sources / "legacy.css").write_text(".legacy { color: red; }\n", encoding="utf-8")

            self.assertEqual(
                forbidden_web_ui_source_paths(roots=[root / "Sources"], root=root),
                [
                    "Sources/LorvexApple/LegacyPane.tsx",
                    "Sources/LorvexApple/legacy.css",
                ],
            )

    def test_forbidden_web_ui_source_paths_accepts_swift_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            sources.mkdir(parents=True)
            (sources / "NativeView.swift").write_text("struct NativeView {}\n", encoding="utf-8")

            self.assertEqual(
                forbidden_web_ui_source_paths(roots=[root / "Sources"], root=root),
                [],
            )

    def test_forbidden_theme_system_paths_rejects_theme_files_not_command_palette(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            sources.mkdir(parents=True)
            (sources / "AppTheme.swift").write_text("enum AppTheme {}\n", encoding="utf-8")
            (sources / "CommandPaletteView.swift").write_text("struct CommandPaletteView {}\n", encoding="utf-8")

            self.assertEqual(
                forbidden_theme_system_paths(roots=[root / "Sources"], root=root),
                ["Sources/LorvexApple/AppTheme.swift"],
            )

    def test_forbidden_swift_core_placeholder_sources_rejects_bridge_era_unported_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            services = root / "Sources" / "LorvexCore" / "Services"
            services.mkdir(parents=True)
            (services / "SwiftLorvexCoreService+Unsupported.swift").write_text(
                """
                extension SwiftLorvexCoreService {
                  func unported(_ name: String) -> LorvexCoreError {
                    .unsupportedOperation("\\(name) is not yet ported to the Swift core.")
                  }
                }
                """,
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_swift_core_placeholder_sources(roots=[services], root=root),
                ["Sources/LorvexCore/Services/SwiftLorvexCoreService+Unsupported.swift"],
            )

    def test_forbidden_swift_core_placeholder_sources_accepts_real_service_extensions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            services = root / "Sources" / "LorvexCore" / "Services"
            services.mkdir(parents=True)
            (services / "SwiftLorvexCoreService+Tasks.swift").write_text(
                """
                extension SwiftLorvexCoreService {
                  public func loadToday() async throws -> TodaySnapshot {
                    try await loadTodaySnapshot()
                  }
                }
                """,
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_swift_core_placeholder_sources(roots=[services], root=root),
                [],
            )

    def test_forbidden_bridge_era_fixture_sources_rejects_stale_rust_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "Tests"
            tests.mkdir()
            (tests / "SeedTests.swift").write_text(
                '#expect(task.id == "task-rust-bridge")\n',
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_bridge_era_fixture_sources(roots=[tests], root=root),
                ["Tests/SeedTests.swift"],
            )

    def test_forbidden_bridge_era_fixture_sources_accepts_swift_core_fixture_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "Tests"
            tests.mkdir()
            (tests / "SeedTests.swift").write_text(
                '#expect(task.id == "task-swift-core")\n',
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_bridge_era_fixture_sources(roots=[tests], root=root),
                [],
            )

    def test_forbidden_email_reference_paths_rejects_docs_placeholders(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docs = root / "docs"
            docs.mkdir()
            (docs / "release.md").write_text(
                'APPLE_ID="developer@example.com"\n',
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_email_reference_paths(roots=[docs], root=root),
                ["docs/release.md"],
            )

    def test_forbidden_email_reference_paths_accepts_opaque_account_placeholders(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docs = root / "docs"
            docs.mkdir()
            (docs / "release.md").write_text(
                'APPLE_ID="APPLE_ACCOUNT_ID"\n',
                encoding="utf-8",
            )

            self.assertEqual(
                forbidden_email_reference_paths(roots=[docs], root=root),
                [],
            )


if __name__ == "__main__":
    unittest.main()
