#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from acknowledgments_data import ResolvedPackage
from verify_privacy_manifests import (
    accessed_api_type_structural_failures,
    category_usage_evidence,
    consistency_failures,
    dependency_boundary_note,
    no_tracking_no_collection_failures,
    privacy_manifest_failures,
    required_reason_coverage_failures,
    swift_files,
    REQUIRED_REASON_CATEGORIES,
)


def _base_plist(**overrides: object) -> dict:
    plist: dict = {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [],
        "NSPrivacyAccessedAPITypes": [
            {
                "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
            },
        ],
    }
    plist.update(overrides)
    return plist


class ConsistencyFailuresTests(unittest.TestCase):
    def test_identical_manifests_pass(self) -> None:
        macos = _base_plist()
        resource = _base_plist()
        self.assertEqual(consistency_failures("macos", macos, "resource", resource), [])

    def test_tracking_flag_drift_fails(self) -> None:
        macos = _base_plist(NSPrivacyTracking=False)
        resource = _base_plist(NSPrivacyTracking=True)
        failures = consistency_failures("macos", macos, "resource", resource)
        self.assertTrue(any("NSPrivacyTracking drift" in failure for failure in failures))

    def test_tracking_domain_drift_fails(self) -> None:
        macos = _base_plist(NSPrivacyTrackingDomains=[])
        resource = _base_plist(NSPrivacyTrackingDomains=["example.com"])
        failures = consistency_failures("macos", macos, "resource", resource)
        self.assertTrue(any("NSPrivacyTrackingDomains drift" in failure for failure in failures))

    def test_tracking_domain_order_does_not_count_as_drift(self) -> None:
        macos = _base_plist(NSPrivacyTrackingDomains=["a.com", "b.com"])
        resource = _base_plist(NSPrivacyTrackingDomains=["b.com", "a.com"])
        self.assertEqual(consistency_failures("macos", macos, "resource", resource), [])

    def test_collected_data_types_drift_fails(self) -> None:
        macos = _base_plist(NSPrivacyCollectedDataTypes=[])
        resource = _base_plist(
            NSPrivacyCollectedDataTypes=[{"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeName"}]
        )
        failures = consistency_failures("macos", macos, "resource", resource)
        self.assertTrue(any("NSPrivacyCollectedDataTypes drift" in failure for failure in failures))

    def test_accessed_api_types_drift_fails_on_extra_category(self) -> None:
        macos = _base_plist()
        resource = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
                },
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
                    "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
                },
            ]
        )
        failures = consistency_failures("macos", macos, "resource", resource)
        self.assertTrue(any("NSPrivacyAccessedAPITypes drift" in failure for failure in failures))

    def test_accessed_api_types_drift_fails_on_reason_mismatch(self) -> None:
        macos = _base_plist()
        resource = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["1C8F.1"],
                },
            ]
        )
        failures = consistency_failures("macos", macos, "resource", resource)
        self.assertTrue(any("NSPrivacyAccessedAPITypes drift" in failure for failure in failures))

    def test_accessed_api_reason_order_does_not_count_as_drift(self) -> None:
        macos = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "1C8F.1"],
                },
            ]
        )
        resource = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["1C8F.1", "CA92.1"],
                },
            ]
        )
        self.assertEqual(consistency_failures("macos", macos, "resource", resource), [])


class NoTrackingNoCollectionFailuresTests(unittest.TestCase):
    def test_compliant_manifest_passes(self) -> None:
        self.assertEqual(no_tracking_no_collection_failures("manifest", _base_plist()), [])

    def test_tracking_true_fails(self) -> None:
        failures = no_tracking_no_collection_failures("manifest", _base_plist(NSPrivacyTracking=True))
        self.assertTrue(any("NSPrivacyTracking must be false" in failure for failure in failures))

    def test_nonempty_tracking_domains_fail(self) -> None:
        failures = no_tracking_no_collection_failures(
            "manifest", _base_plist(NSPrivacyTrackingDomains=["ads.example.com"])
        )
        self.assertTrue(any("NSPrivacyTrackingDomains must be empty" in failure for failure in failures))

    def test_nonempty_collected_data_types_fail(self) -> None:
        failures = no_tracking_no_collection_failures(
            "manifest",
            _base_plist(
                NSPrivacyCollectedDataTypes=[{"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeEmailAddress"}]
            ),
        )
        self.assertTrue(any("NSPrivacyCollectedDataTypes must be empty" in failure for failure in failures))


class AccessedApiTypeStructuralFailuresTests(unittest.TestCase):
    def test_known_category_and_reason_pass(self) -> None:
        self.assertEqual(accessed_api_type_structural_failures("manifest", _base_plist()), [])

    def test_unrecognized_category_fails(self) -> None:
        plist = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryTotallyMadeUp",
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
                },
            ]
        )
        failures = accessed_api_type_structural_failures("manifest", plist)
        self.assertTrue(any("unrecognized" in failure for failure in failures))

    def test_unknown_reason_code_fails(self) -> None:
        plist = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["ZZZZ.9"],
                },
            ]
        )
        failures = accessed_api_type_structural_failures("manifest", plist)
        self.assertTrue(any("unknown reason code" in failure for failure in failures))

    def test_empty_reason_list_fails(self) -> None:
        plist = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": [],
                },
            ]
        )
        failures = accessed_api_type_structural_failures("manifest", plist)
        self.assertTrue(any("declares no reason codes" in failure for failure in failures))

    def test_duplicate_category_entry_fails(self) -> None:
        plist = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
                },
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                    "NSPrivacyAccessedAPITypeReasons": ["1C8F.1"],
                },
            ]
        )
        failures = accessed_api_type_structural_failures("manifest", plist)
        self.assertTrue(any("duplicate" in failure for failure in failures))

    def test_all_documented_categories_and_reasons_pass(self) -> None:
        plist = _base_plist(
            NSPrivacyAccessedAPITypes=[
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime",
                    "NSPrivacyAccessedAPITypeReasons": ["35F9.1"],
                },
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace",
                    "NSPrivacyAccessedAPITypeReasons": ["E174.1"],
                },
                {
                    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryActiveKeyboards",
                    "NSPrivacyAccessedAPITypeReasons": ["3EC4.1"],
                },
            ]
        )
        self.assertEqual(accessed_api_type_structural_failures("manifest", plist), [])


class CategoryUsageEvidenceTests(unittest.TestCase):
    def test_user_defaults_category_detects_real_usage(self) -> None:
        user_defaults_category = next(
            category for category in REQUIRED_REASON_CATEGORIES if category.key.endswith("UserDefaults")
        )
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Settings.swift").write_text(
                "let defaults = UserDefaults.standard\n", encoding="utf-8"
            )

            evidence = category_usage_evidence(user_defaults_category.usage_pattern, (sources,))

        self.assertIsNotNone(evidence)
        self.assertEqual(evidence.name, "Settings.swift")

    def test_user_defaults_category_ignores_unrelated_code(self) -> None:
        user_defaults_category = next(
            category for category in REQUIRED_REASON_CATEGORIES if category.key.endswith("UserDefaults")
        )
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Model.swift").write_text("struct Task { var id: String }\n", encoding="utf-8")

            evidence = category_usage_evidence(user_defaults_category.usage_pattern, (sources,))

        self.assertIsNone(evidence)

    def test_file_timestamp_category_detects_attributes_of_item(self) -> None:
        file_timestamp_category = next(
            category for category in REQUIRED_REASON_CATEGORIES if category.key.endswith("FileTimestamp")
        )
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Attrs.swift").write_text(
                "let attrs = try FileManager.default.attributesOfItem(atPath: path)\n",
                encoding="utf-8",
            )

            evidence = category_usage_evidence(file_timestamp_category.usage_pattern, (sources,))

        self.assertIsNotNone(evidence)

    def test_file_timestamp_category_ignores_unrelated_local_identifier_named_stat(self) -> None:
        """A local helper literally named `stat(` must not be mistaken for the
        Darwin `stat()` syscall — the pattern only matches the more distinctive
        getattrlist/fstatat/etc. members of that family, not bare `stat(`."""
        file_timestamp_category = next(
            category for category in REQUIRED_REASON_CATEGORIES if category.key.endswith("FileTimestamp")
        )
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Stats.swift").write_text(
                'private func stat(title: String, value: String) -> some View { EmptyView() }\n',
                encoding="utf-8",
            )

            evidence = category_usage_evidence(file_timestamp_category.usage_pattern, (sources,))

        self.assertIsNone(evidence)

    def test_swift_files_skips_missing_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "does-not-exist"
            self.assertEqual(swift_files((missing,)), [])


class RequiredReasonCoverageFailuresTests(unittest.TestCase):
    def test_used_category_with_declared_reason_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Settings.swift").write_text("UserDefaults.standard\n", encoding="utf-8")

            failures = required_reason_coverage_failures(
                "manifest", _base_plist(), code_roots=(sources,)
            )

        self.assertEqual(failures, [])

    def test_used_category_with_no_declared_reason_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Settings.swift").write_text("UserDefaults.standard\n", encoding="utf-8")

            failures = required_reason_coverage_failures(
                "manifest",
                _base_plist(NSPrivacyAccessedAPITypes=[]),
                code_roots=(sources,),
            )

        self.assertTrue(any("UserDefaults" in failure and "declares no" in failure for failure in failures))

    def test_unused_category_with_no_declared_reason_does_not_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Model.swift").write_text("struct Task {}\n", encoding="utf-8")

            failures = required_reason_coverage_failures(
                "manifest",
                _base_plist(NSPrivacyAccessedAPITypes=[]),
                code_roots=(sources,),
            )

        self.assertEqual(failures, [])

    def test_declaring_an_unused_category_is_not_a_failure(self) -> None:
        """Over-declaring (a reason present for a category grep cannot prove is
        used) must not fail — grep-based detection can miss real usage, so it
        only asserts the direction that matters: used-but-undeclared."""
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Model.swift").write_text("struct Task {}\n", encoding="utf-8")

            failures = required_reason_coverage_failures(
                "manifest", _base_plist(), code_roots=(sources,)
            )

        self.assertEqual(failures, [])


class DependencyBoundaryNoteTests(unittest.TestCase):
    def test_note_lists_every_resolved_identity(self) -> None:
        resolved = {
            "grdb.swift": ResolvedPackage(
                identity="grdb.swift", version="6.29.3", location="https://example.invalid/grdb.git"
            ),
            "swift-nio": ResolvedPackage(
                identity="swift-nio", version="2.100.0", location="https://example.invalid/swift-nio.git"
            ),
        }

        note = dependency_boundary_note(resolved=resolved)

        self.assertIn("grdb.swift 6.29.3", note)
        self.assertIn("swift-nio 2.100.0", note)
        self.assertIn("signed-archive", note)

    def test_note_never_asserts_failure_shape(self) -> None:
        """The note is purely informational text, not a failures list — a
        caller that forgets this and treats it as a gate result would notice
        immediately since it is a `str`, not a `list[str]`."""
        note = dependency_boundary_note(resolved={})
        self.assertIsInstance(note, str)


class PrivacyManifestFailuresIntegrationTests(unittest.TestCase):
    def test_two_identical_compliant_manifests_pass_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()
            (sources / "Settings.swift").write_text("UserDefaults.standard\n", encoding="utf-8")

            macos = _base_plist()
            resource = _base_plist()

            failures = privacy_manifest_failures(
                "macos", macos, "resource", resource, code_roots=(sources,)
            )

        self.assertEqual(failures, [])

    def test_drifted_manifests_fail_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sources = Path(directory) / "Sources"
            sources.mkdir()

            macos = _base_plist()
            resource = _base_plist(NSPrivacyTracking=True)

            failures = privacy_manifest_failures(
                "macos", macos, "resource", resource, code_roots=(sources,)
            )

        self.assertTrue(failures)


if __name__ == "__main__":
    unittest.main()
