#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_user_docs import (
    APPLE_NATIVE_ARCH,
    CLAUDE_GUIDE,
    CHECKS,
    CI_RELEASE_TRIGGER_POLICY,
    DISTRIBUTION,
    FEATURES,
    MCP_TOOL_COUNT_PATTERNS,
    ROADMAP,
    ROOT,
    documented_mcp_tool_examples,
    mcp_integration_section,
    mcp_tool_count_doc_failures,
    mcp_tool_doc_failures,
)
from expected_mcp_tools import EXPECTED_MCP_TOOLS


class VerifyUserDocsTests(unittest.TestCase):
    @staticmethod
    def mcp_count_documents(count: int) -> dict:
        return {
            ROADMAP: (
                f"- **MCP catalog at {count} tools.** Current state.\n"
                f"  85 reference tools against Apple's catalog (now {count}): two gaps.\n"
                f"  across the Apple MCP catalog (currently {count} tools) checked.\n"
                f"- **Full Tauri MCP parity + beyond.** The current Apple catalog has {count} tools.\n"
                f"  additions leave the current catalog at {count} tools.\n"
            ),
            FEATURES: f"MCP tool count: {count}. Scoped tools follow.\n",
            APPLE_NATIVE_ARCH: (
                f"- It exposes {count} tools spanning tasks, focus, lists, habits, calendar, reviews,\n"
                "  memory, and system diagnostics.\n"
            ),
        }

    def test_mcp_tool_count_docs_accept_current_count(self) -> None:
        count = len(EXPECTED_MCP_TOOLS)
        documents = self.mcp_count_documents(count)

        self.assertEqual(mcp_tool_count_doc_failures(documents), [])

    def test_mcp_tool_count_docs_reject_missing_canonical_statement(self) -> None:
        count = len(EXPECTED_MCP_TOOLS)
        documents = self.mcp_count_documents(count)
        documents[ROADMAP] = documents[ROADMAP].replace(
            f"- **MCP catalog at {count} tools.** Current state.\n",
            "",
        )

        self.assertEqual(
            mcp_tool_count_doc_failures(documents),
            ['MCP tool count statement "catalog headline" missing from ROADMAP.md'],
        )

    def test_mcp_tool_count_docs_reject_wrong_count(self) -> None:
        count = len(EXPECTED_MCP_TOOLS)
        wrong_count = count - 1
        documents = self.mcp_count_documents(count)
        documents[FEATURES] = f"MCP tool count: {wrong_count}.\n"

        self.assertEqual(
            mcp_tool_count_doc_failures(documents),
            [
                'MCP tool count statement "feature matrix count" in '
                "apps/apple/docs/reference/FEATURES.md "
                f"is {wrong_count}; expected {count} from "
                "apps/apple/script/expected_mcp_tools.py"
            ],
        )

    def test_mcp_tool_count_docs_reject_secondary_roadmap_drift(self) -> None:
        count = len(EXPECTED_MCP_TOOLS)
        wrong_count = count - 1
        documents = self.mcp_count_documents(count)
        documents[ROADMAP] = documents[ROADMAP].replace(
            f"(currently {count} tools)",
            f"(currently {wrong_count} tools)",
        )

        self.assertEqual(
            mcp_tool_count_doc_failures(documents),
            [
                'MCP tool count statement "parameter audit count" in ROADMAP.md '
                f"is {wrong_count}; expected {count} from "
                "apps/apple/script/expected_mcp_tools.py"
            ],
        )

    def test_mcp_tool_count_guard_covers_canonical_docs(self) -> None:
        self.assertEqual(
            set(MCP_TOOL_COUNT_PATTERNS),
            {ROADMAP, FEATURES, APPLE_NATIVE_ARCH},
        )

    def test_documented_mcp_tool_examples_extracts_tool_table_names(self) -> None:
        text = """
        ### Tool Catalog

        | Domain | Example tools |
        |---|---|
        | **Tasks** | `create_task`, `update_task` |

        ### Next Section

        `not_a_tool_table_entry`
        """

        self.assertEqual(documented_mcp_tool_examples(text), {"create_task", "update_task"})

    def test_mcp_integration_section_stops_before_widgets_section(self) -> None:
        text = """
        ## MCP & AI Integration

        `create_task`

        ## Widgets & Watch

        `task_create`
        """

        self.assertEqual(mcp_integration_section(text).count("task_create"), 0)

    def test_mcp_tool_doc_failures_rejects_unknown_tool_name(self) -> None:
        text = """
        ### Tool Catalog

        | Domain | Example tools |
        |---|---|
        | **Tasks** | `task_create`, `create_task` |
        """

        self.assertEqual(
            mcp_tool_doc_failures(text),
            [
                "USER_GUIDE MCP tool catalog documents unknown tool(s): ['task_create']",
                "USER_GUIDE MCP tool catalog still uses legacy tool name(s): ['task_create']",
            ],
        )

    def test_mcp_tool_doc_failures_rejects_legacy_name_in_integration_body(self) -> None:
        text = """
        ## MCP & AI Integration

        Ask your client to call `task_create` and `weekly_brief`.

        ### Tool Catalog

        | Domain | Example tools |
        |---|---|
        | **Tasks** | `create_task` |
        """

        self.assertEqual(
            mcp_tool_doc_failures(text),
            [
                "USER_GUIDE MCP integration section still uses legacy tool name(s): "
                "['task_create', 'weekly_brief']"
            ],
        )

    def test_mcp_tool_doc_failures_accepts_current_tool_names(self) -> None:
        text = """
        ### Tool Catalog

        | Domain | Example tools |
        |---|---|
        | **Tasks** | `create_task`, `update_task`, `get_task` |
        """

        self.assertEqual(
            mcp_tool_doc_failures(text),
            [],
        )

    def test_claude_guide_contract_tracks_model_agnostic_and_apple_only_policy(self) -> None:
        self.assertIn(CLAUDE_GUIDE, CHECKS)
        checks = CHECKS[CLAUDE_GUIDE]

        # Repository policy must not pin an orchestration model or reasoning
        # setting; those are runtime concerns, not source contracts.
        self.assertIn('model: "opus"', checks["stale"])
        self.assertIn('Dispatch with `model: "gpt-5.5"`', checks["stale"])
        self.assertIn('`reasoning_effort: "high"`', checks["stale"])
        self.assertIn(
            "Do not pin a model or reasoning setting in repository policy.",
            checks["required"],
        )
        self.assertIn("Never add Windows/Linux/Web/Tauri shims.", checks["required"])
        self.assertIn("official Swift SDK", checks["required"])

    def test_features_contract_tracks_mcp_read_fencing_scope(self) -> None:
        self.assertIn(FEATURES, CHECKS)
        checks = CHECKS[FEATURES]

        self.assertIn(
            "| Prompt-injection fencing on MCP read responses | [SHIPPED] | get_task, list_tasks, get_overview |",
            checks["stale"],
        )
        self.assertIn(
            "Structured read payloads carrying user-controlled text are key-aware fenced through `SecurityFencing.fenceValue`",
            checks["required"],
        )
        self.assertIn(
            "including task, calendar, list/tag, focus, habit, review, and memory reads",
            checks["required"],
        )

    def test_features_contract_tracks_cloudkit_sync_readiness(self) -> None:
        self.assertIn(FEATURES, CHECKS)
        checks = CHECKS[FEATURES]

        self.assertIn(
            "| CloudKit sync (read + write) | [PARTIAL] | Scaffold present; production container provisioning required |",
            checks["stale"],
        )
        self.assertIn(
            "| CloudKit sync (read + write) | [SHIPPED] | Live mode includes outbound record export, private database subscription, remote-change refresh, inbound record application, and atomic SQLite change-token checkpointing; distributed builds still require CloudKit entitlement/container provisioning |",
            checks["required"],
        )

    def test_distribution_contract_tracks_carplay_template_boundary(self) -> None:
        self.assertIn(DISTRIBUTION, CHECKS)
        checks = CHECKS[DISTRIBUTION]

        self.assertIn(
            "`com.apple.developer.carplay-*` — required if CarPlay integration is added.",
            checks["stale"],
        )
        self.assertIn(
            "2. [macOS — Developer ID notarized](#2-macos--developer-id-notarized)",
            checks["stale"],
        )
        self.assertIn(
            "2. [macOS — distributable DMG](#2-macos--distributable-dmg-the-default-packaging-path)",
            checks["stale"],
        )
        self.assertIn(
            "3. [macOS — Developer ID notarized](#3-macos--developer-id-notarized-archive-path)",
            checks["stale"],
        )
        self.assertIn(
            "3. [iOS/iPadOS — App Store Connect](#3-iosipados--app-store-connect)",
            checks["stale"],
        )
        self.assertIn("## 3. iOS/iPadOS — App Store Connect", checks["stale"])
        self.assertIn(
            "`upload_testflight.sh` could wrap `xcrun notarytool` or the App Store Connect",
            checks["stale"],
        )
        self.assertIn("TODO: MAS archive script", checks["stale"])
        self.assertIn(
            "2. [macOS — production Developer ID DMG](#2-macos--production-developer-id-dmg)",
            checks["required"],
        )
        self.assertIn(
            "3. [macOS — local development and CI packages](#3-macos--local-development-and-ci-packages)",
            checks["required"],
        )
        self.assertIn(
            "4. [macOS - Mac App Store](#4-macos---mac-app-store)",
            checks["required"],
        )
        self.assertIn(
            "5. [iOS/iPadOS — App Store Connect](#5-iosipados--app-store-connect)",
            checks["required"],
        )
        self.assertIn(
            "10. [Distribution gaps and follow-up work](#10-distribution-gaps-and-follow-up-work)",
            checks["required"],
        )
        self.assertIn("## 4. macOS - Mac App Store", checks["required"])
        self.assertIn("## 5. iOS/iPadOS — App Store Connect", checks["required"])
        self.assertIn("## 10. Distribution gaps and follow-up work", checks["required"])
        self.assertIn("./script/archive_mas.sh --preflight", checks["required"])
        self.assertIn("./script/archive_mas.sh --package", checks["required"])
        self.assertIn("com.lorvex.apple.focus-filter", checks["required"])
        self.assertIn("a reused wildcard profile", checks["required"])
        self.assertIn(
            "CloudKit production schema promotion remains a manual release gate",
            checks["required"],
        )
        self.assertIn(
            "| iOS CarPlay approval template | `LorvexCarPlay.entitlements` | — | — | — | — | — | CarPlay communication entitlement template; merge into the iOS app entitlements only after Apple approval |",
            checks["required"],
        )
        self.assertIn(
            "The template declares\n`com.apple.developer.carplay-communication`; do not merge it into\n`LorvexMobileApp.entitlements` until Apple approves the CarPlay capability",
            checks["required"],
        )
        self.assertIn(
            "Do not use\n`xcrun notarytool` for IPA uploads; notarization is the Developer ID macOS\ndistribution path, not the TestFlight/App Store Connect path.",
            checks["required"],
        )

    def test_ci_release_policy_tracks_app_store_ipa_artifacts(self) -> None:
        self.assertIn(CI_RELEASE_TRIGGER_POLICY, CHECKS)
        checks = CHECKS[CI_RELEASE_TRIGGER_POLICY]

        self.assertIn("`Swift Build`", checks["stale"])
        self.assertIn("`Swift Test`", checks["stale"])
        self.assertIn("`MCP Smoke`", checks["stale"])
        self.assertIn("Signed `.pkg` uploaded to workflow artifacts", checks["stale"])
        self.assertIn("Signed `.pkg` uploaded to App Store Connect", checks["stale"])
        self.assertIn("App Store Connect (App Store signed .pkg)", checks["stale"])
        self.assertIn(
            "App Store distribution signed `.pkg` submitted to App Store Connect",
            checks["stale"],
        )
        self.assertIn("`Apple CI / Swift package`", checks["required"])
        self.assertIn("`script/verify_schema_embed.sh`", checks["required"])
        self.assertIn(
            "`script/mcp_stdio_smoke.py` — MCP host stdio round-trip against the Swift core",
            checks["required"],
        )
        self.assertIn(
            "Apple static verifiers for metadata, strategy, build matrix, CloudKit\n  readiness, MCP catalog, localization, system entrypoints, core service\n  coverage, hotspots, repo hygiene, and user docs",
            checks["required"],
        )
        self.assertIn("Signed `.ipa` uploaded to workflow artifacts", checks["required"])
        self.assertIn("Signed `.ipa` uploaded to App Store Connect", checks["required"])
        self.assertIn("App Store Connect (App Store signed IPA)", checks["required"])
        self.assertIn(
            "App Store distribution signed `.ipa` submitted to App Store Connect",
            checks["required"],
        )

    def test_contributing_contract_tracks_web_ui_source_ban(self) -> None:
        contributing = ROOT / "docs" / "CONTRIBUTING.md"
        self.assertIn(contributing, CHECKS)
        self.assertIn(
            "web UI source artifacts such as `.tsx`, `.jsx`, `.css`, `.html`, and `.js`",
            CHECKS[contributing]["required"],
        )

    def test_release_doc_contract_tracks_archive_and_notarization_safety_rules(self) -> None:
        release_doc = ROOT / "docs" / "release.md"
        self.assertIn(release_doc, CHECKS)
        checks = CHECKS[release_doc]

        self.assertIn(
            "rejects AppleDouble sidecar files, `__MACOSX` metadata entries, symlink entries, and entries outside",
            checks["required"],
        )
        # The archive contains a statically-linked Swift binary — no Rust
        # bridge dylib. The contract guards both the current Swift wording
        # (required) and that the old Rust-dylib wording stays gone (stale).
        self.assertIn(
            "The archive must contain the app\nexecutable, privacy manifest, bundled MCP helper, and Widget extension files.",
            checks["required"],
        )
        self.assertIn("Rust bridge dylib", checks["stale"])
        self.assertIn(
            "watchOS, Watch complication, Widget, Focus Filter, and shared App Intents targets",
            checks["required"],
        )
        self.assertIn(
            "release manifest records CloudKit sync readiness metadata",
            checks["required"],
        )
        self.assertIn(
            "CloudKit sync readiness drift checks",
            checks["required"],
        )
        self.assertIn(
            "CloudKit production schema promotion and App Store Connect provisioning remain\nhuman-gated release requirements",
            checks["required"],
        )
        self.assertIn(
            "The release manifest records both the runtime\nCloudKit sync readiness and the separate production release readiness gate",
            checks["required"],
        )

    def test_user_guide_contract_tracks_cloudkit_readiness_boundaries(self) -> None:
        user_guide = ROOT / "docs" / "USER_GUIDE.md"
        self.assertIn(user_guide, CHECKS)
        checks = CHECKS[user_guide]

        self.assertIn(
            "outbound record export, private database subscription, remote-change refresh,\ninbound record application, and atomic SQLite change-token checkpointing are\nready",
            checks["required"],
        )
        self.assertIn(
            "Core planning entities such as tasks, lists, habits, calendar events, memory,\nand focus plans route through the same native inbound sync\nengine used by the Swift core tests",
            checks["required"],
        )
        self.assertIn(
            "typed HLC LWW gates, tombstones,\nredirect-aware pending inbox draining, and conflict logging",
            checks["required"],
        )

    def test_apple_arch_contract_tracks_store_bootstrap_and_watch_replica(self) -> None:
        apple_arch = ROOT / "docs" / "architecture" / "apple-native-architecture.md"
        self.assertIn(apple_arch, CHECKS)
        checks = CHECKS[apple_arch]

        self.assertIn(
            "`MobileStoreFactory` centralizes the mobile/vision store bootstrap",
            checks["required"],
        )
        self.assertIn(
            "production `LorvexWatchStoreFactory` is read-only with respect\n  to SQLite",
            checks["required"],
        )
        self.assertIn(
            "through replaceable `WCSession.updateApplicationContext`",
            checks["required"],
        )
        self.assertIn(
            "replica state fails closed instead of opening a second writable database",
            checks["required"],
        )
        self.assertIn(
            "whose applied receipt commits in the same transaction as the domain write",
            checks["required"],
        )


if __name__ == "__main__":
    unittest.main()
