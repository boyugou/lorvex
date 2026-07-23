#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_repo_hygiene import (
    app_intents_metadata_literal_failures,
    ci_workflow_failures,
    distribution_script_failures,
    repo_hygiene_failures,
    uncommented_yaml_line,
    verify_all_gate_failures,
)


# The verification gate script the Apple CI workflow now delegates to. Carries
# every verifier command ci_workflow_failures follows the delegation into.
GOOD_VERIFY_ALL = """\
swift build --product LorvexApple
swift test
( cd core && swift test )
python3 -m py_compile script/verify_repo_hygiene.py
python3 -m unittest discover -s script -p 'test_*.py'
./script/verify_schema_embed.sh
./script/verify_sync_payload_contract.py
./script/verify_repo_hygiene.py
./script/verify_app_metadata.py
./script/verify_apple_strategy.py
./script/verify_build_matrix.py
./script/verify_cloudkit_sync_readiness.py
./script/verify_mcp_tool_catalog.py
./script/verify_localization_catalog.py
./script/verify_system_entrypoints.py
python3 ./script/verify_core_service_coverage.py
./script/verify_hotspots.py
./script/verify_user_docs.py
./script/mcp_stdio_smoke.py
"""

GOOD_WORKFLOW = """\
run: ./script/verify_all.sh
run: ./script/verify_mobile_release_link.sh
run: ./script/verify_vision_release_link.sh
"""


class RepoHygieneTests(unittest.TestCase):
    def test_uncommented_yaml_line_preserves_hash_inside_quotes(self) -> None:
        self.assertEqual(
            uncommented_yaml_line('      - "schema/#fixture.sql" # comment'),
            '      - "schema/#fixture.sql"',
        )

    def test_uncommented_yaml_line_strips_inline_comment(self) -> None:
        self.assertEqual(
            uncommented_yaml_line("run: echo ok # ./script/mcp_stdio_smoke.py"),
            "run: echo ok",
        )

    def test_repo_hygiene_accepts_clean_source_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            sources.mkdir(parents=True)
            (sources / "App.swift").write_text("struct App {}\n", encoding="utf-8")

            self.assertEqual(repo_hygiene_failures(root=root, scan_roots=[root / "Sources"]), [])

    def test_repo_hygiene_rejects_os_and_editor_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            tests = root / "Tests"
            scripts = root / "script"
            sources.mkdir(parents=True)
            tests.mkdir()
            scripts.mkdir()
            (sources / ".DS_Store").write_text("", encoding="utf-8")
            (tests / "FocusTests.swift.bak").write_text("", encoding="utf-8")
            (scripts / "verify.py.tmp").write_text("", encoding="utf-8")

            self.assertEqual(
                repo_hygiene_failures(
                    root=root,
                    scan_roots=[root / "Sources", tests, scripts],
                ),
                [
                    "forbidden generated/editor artifact: Sources/LorvexApple/.DS_Store",
                    "forbidden generated/editor artifact: Tests/FocusTests.swift.bak",
                    "forbidden generated/editor artifact: script/verify.py.tmp",
                ],
            )

    def test_repo_hygiene_rejects_stale_rust_store_source_wording(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexCore"
            sources.mkdir(parents=True)
            (sources / "Review.swift").write_text(
                "// a parameterised weekly snapshot requires the " + "Rust store.\n",
                encoding="utf-8",
            )

            self.assertEqual(
                repo_hygiene_failures(root=root, scan_roots=[root / "Sources"]),
                [
                    "current Swift sources must not describe active functionality as requiring "
                    "the deleted Rust store: Sources/LorvexCore/Review.swift contains "
                    "'requires the " + "Rust store'"
                ],
            )

    def test_repo_hygiene_rejects_stale_cloud_sync_coordinator_wording(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexApple"
            sources.mkdir(parents=True)
            (sources / "CloudSyncMode.swift").write_text(
                "// engine sync coordinator " + "is not built\n",
                encoding="utf-8",
            )

            self.assertEqual(
                repo_hygiene_failures(root=root, scan_roots=[root / "Sources"]),
                [
                    "current Swift sources must not describe the live Cloud Sync coordinator "
                    "as unbuilt: Sources/LorvexApple/CloudSyncMode.swift contains "
                    "'engine sync coordinator " + "is not built'"
                ],
            )

    def test_app_intents_metadata_rejects_runtime_resource_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexSystemIntents"
            sources.mkdir(parents=True)
            (sources / "Capture.swift").write_text(
                'static let title = SystemL10n.resource("key", "Title")\n',
                encoding="utf-8",
            )

            self.assertEqual(
                app_intents_metadata_literal_failures(root=root, scan_roots=[sources]),
                [
                    "App Intents metadata must use direct LocalizedStringResource "
                    "initializers, not SystemL10n.resource: "
                    "Sources/LorvexSystemIntents/Capture.swift contains "
                    "'SystemL10n.resource('"
                ],
            )

    def test_app_intents_metadata_rejects_computed_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexWidgetIntents"
            sources.mkdir(parents=True)
            (sources / "Widget.swift").write_text(
                "public static var title: LocalizedStringResource {\n"
                '  LocalizedStringResource("key", defaultValue: "Title")\n'
                "}\n",
                encoding="utf-8",
            )

            self.assertEqual(
                app_intents_metadata_literal_failures(root=root, scan_roots=[sources]),
                [
                    "App Intents title metadata must be static let, not computed "
                    "static var: Sources/LorvexWidgetIntents/Widget.swift "
                    "contains 'static var title'"
                ],
            )

    def test_app_intents_metadata_accepts_direct_static_initializers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "Sources" / "LorvexSystemIntents"
            sources.mkdir(parents=True)
            (sources / "Capture.swift").write_text(
                "static let title = LocalizedStringResource(\n"
                '  "key",\n'
                '  defaultValue: "Title",\n'
                '  table: "Localizable")\n',
                encoding="utf-8",
            )

            self.assertEqual(
                app_intents_metadata_literal_failures(root=root, scan_roots=[sources]),
                [],
            )

    def test_distribution_script_rejects_notarytool_ipa_upload_guidance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "archive_ios.sh"
            script.write_text(
                "echo \"xcrun notarytool submit '$IPA_PATH' --wait\"\n",
                encoding="utf-8",
            )

            self.assertEqual(
                distribution_script_failures(script),
                [
                    "script/archive_ios.sh must not suggest notarytool for IPA uploads",
                    "script/archive_ios.sh must document App Store Connect IPA upload via altool",
                    "script/archive_ios.sh must use verify_macho_closure.py for watch embed validation",
                ],
            )

    def test_distribution_script_accepts_altool_upload_guidance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "archive_ios.sh"
            script.write_text(
                "echo \"xcrun altool --upload-app\"\n"
                "\"$ROOT_DIR/script/verify_macho_closure.py\" \"$ARCHIVED_APP\"\n",
                encoding="utf-8",
            )

            self.assertEqual(distribution_script_failures(script), [])

    def test_ci_workflow_accepts_delegation_and_full_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / "apple-ci.yml"
            workflow.write_text(GOOD_WORKFLOW, encoding="utf-8")
            verify_all = root / "verify_all.sh"
            verify_all.write_text(GOOD_VERIFY_ALL, encoding="utf-8")

            self.assertEqual(ci_workflow_failures(workflow, verify_all), [])

    def test_ci_workflow_rejects_missing_delegation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / "apple-ci.yml"
            workflow.write_text(
                "run: ./script/verify_mobile_release_link.sh\n"
                "run: ./script/verify_vision_release_link.sh\n",
                encoding="utf-8",
            )
            verify_all = root / "verify_all.sh"
            verify_all.write_text(GOOD_VERIFY_ALL, encoding="utf-8")

            self.assertIn(
                "Apple CI workflow missing required command: ./script/verify_all.sh",
                ci_workflow_failures(workflow, verify_all),
            )

    def test_ci_workflow_ignores_commented_delegation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / "apple-ci.yml"
            workflow.write_text(
                "# run: ./script/verify_all.sh\n"
                "run: ./script/verify_mobile_release_link.sh\n"
                "run: ./script/verify_vision_release_link.sh\n",
                encoding="utf-8",
            )
            verify_all = root / "verify_all.sh"
            verify_all.write_text(GOOD_VERIFY_ALL, encoding="utf-8")

            self.assertIn(
                "Apple CI workflow missing required command: ./script/verify_all.sh",
                ci_workflow_failures(workflow, verify_all),
            )

    def test_ci_workflow_rejects_neutered_delegation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / "apple-ci.yml"
            workflow.write_text(
                "run: ./script/verify_all.sh || true\n"
                "run: ./script/verify_mobile_release_link.sh\n"
                "run: ./script/verify_vision_release_link.sh\n",
                encoding="utf-8",
            )
            verify_all = root / "verify_all.sh"
            verify_all.write_text(GOOD_VERIFY_ALL, encoding="utf-8")

            self.assertIn(
                "Apple CI workflow neuters required command (|| true / || : / || exit 0): "
                "./script/verify_all.sh",
                ci_workflow_failures(workflow, verify_all),
            )

    def test_verify_all_gate_accepts_full_command_set(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            verify_all = Path(directory) / "verify_all.sh"
            verify_all.write_text(GOOD_VERIFY_ALL, encoding="utf-8")

            self.assertEqual(verify_all_gate_failures(verify_all), [])

    def test_verify_all_gate_rejects_missing_verifier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            verify_all = Path(directory) / "verify_all.sh"
            verify_all.write_text("swift build\nswift test\n", encoding="utf-8")

            self.assertIn(
                "Apple verification gate missing required command: ./script/mcp_stdio_smoke.py",
                verify_all_gate_failures(verify_all),
            )

    def test_verify_all_gate_rejects_neutered_verifier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            verify_all = Path(directory) / "verify_all.sh"
            verify_all.write_text(
                GOOD_VERIFY_ALL.replace(
                    "./script/mcp_stdio_smoke.py",
                    "./script/mcp_stdio_smoke.py || true",
                ),
                encoding="utf-8",
            )

            self.assertIn(
                "Apple verification gate neuters required command (|| true / || : / || exit 0): "
                "./script/mcp_stdio_smoke.py",
                verify_all_gate_failures(verify_all),
            )

    def test_verify_all_gate_requires_sync_payload_contract_verifier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            verify_all = Path(directory) / "verify_all.sh"
            verify_all.write_text(
                GOOD_VERIFY_ALL.replace("./script/verify_sync_payload_contract.py\n", ""),
                encoding="utf-8",
            )

            self.assertIn(
                "Apple verification gate missing required command: "
                "./script/verify_sync_payload_contract.py",
                verify_all_gate_failures(verify_all),
            )


if __name__ == "__main__":
    unittest.main()
