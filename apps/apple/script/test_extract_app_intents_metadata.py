#!/usr/bin/env python3
from __future__ import annotations

import json
import io
import plistlib
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch

from extract_app_intents_metadata import (
    const_value_files,
    linked_targets,
    metadata_strings,
    metadata_module_order,
    process_metadata,
    verify_metadata,
    write_metadata_tables,
)


def catalog(path: Path, strings: dict) -> dict:
    path.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}))
    return {"path": str(path)}


def entry(**values: str) -> dict:
    return {
        "localizations": {
            language: {"stringUnit": {"state": "translated", "value": value}}
            for language, value in values.items()
        }
    }


class LinkedTargetsTests(unittest.TestCase):
    def test_closure_follows_target_dependencies_only(self) -> None:
        description = {
            "targets": [
                {"name": "App", "target_dependencies": ["Intents"], "product_dependencies": ["GRDB"]},
                {"name": "Intents", "target_dependencies": ["Core"]},
                {"name": "Core"},
                {"name": "Widget", "target_dependencies": ["Core"]},
            ]
        }
        names = [target["name"] for target in linked_targets(description, "App")]
        self.assertEqual(names[0], "App")
        self.assertEqual(sorted(names), ["App", "Core", "Intents"])

    def test_unknown_target_fails(self) -> None:
        with self.assertRaises(SystemExit):
            linked_targets({"targets": []}, "Missing")


class ConstValueFilesTests(unittest.TestCase):
    def test_finds_both_build_layouts_without_prefix_collisions(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            out = Path(scratch) / ".build" / "out"
            bin_path = out / "Products" / "Release"
            bin_path.mkdir(parents=True)
            intermediates = out / "Intermediates.noindex" / "Pkg.build" / "Release"
            module_dir = intermediates / "Widget-t.build" / "Objects-normal" / "arm64"
            module_dir.mkdir(parents=True)
            (module_dir / "Widget-primary.swiftconstvalues").write_text("[]")
            longer = intermediates / "WidgetViews-t.build"
            longer.mkdir(parents=True)
            (longer / "WidgetViews-primary.swiftconstvalues").write_text("[]")
            native = bin_path / "Widget.build"
            native.mkdir()
            (native / "A.swiftconstvalues").write_text("[]")

            found = {path.name for path in const_value_files(bin_path, "Pkg", "Widget")}
            self.assertEqual(found, {"Widget-primary.swiftconstvalues", "A.swiftconstvalues"})


class MetadataModuleTests(unittest.TestCase):
    def const_file(self, root: Path, module: str, values: list[dict]) -> Path:
        path = root / (module + ".swiftconstvalues")
        path.write_text(json.dumps(values))
        return path

    def test_empty_executable_uses_its_intent_library_as_primary(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            files = {"App": [self.const_file(root, "App", [])],
                     "Intents": [self.const_file(root, "Intents", [{"conformances": ["AppIntents.AppIntent"]}])]}
            self.assertEqual(metadata_module_order(files), ["Intents"])

    def test_shortcuts_provider_stays_primary_instead_of_losing_its_shortcuts_in_a_static_merge(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            files = {"App": [self.const_file(root, "App", [{"conformances": ["AppIntents.AppEntity"]}])],
                     "Intents": [self.const_file(root, "Intents", [{"conformances": ["AppIntents.AppShortcutsProvider"]}])]}
            self.assertEqual(metadata_module_order(files), ["Intents", "App"])

    def test_widget_configuration_and_interactive_intents_both_participate(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            files = {"WidgetBundle": [self.const_file(root, "WidgetBundle", [])],
                     "WidgetExtension": [self.const_file(root, "WidgetExtension", [{"conformances": ["AppIntents.WidgetConfigurationIntent"]}])],
                     "WidgetIntents": [self.const_file(root, "WidgetIntents", [{"conformances": ["AppIntents.AppIntent"]}])]}
            self.assertEqual(metadata_module_order(files), ["WidgetExtension", "WidgetIntents"])

    def test_multiple_provider_modules_fail_rather_than_silently_dropping_one(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            files = {name: [self.const_file(root, name, [{"conformances": ["AppIntents.AppShortcutsProvider"]}])]
                     for name in ("First", "Second")}
            with self.assertRaisesRegex(SystemExit, "providers span multiple modules"):
                metadata_module_order(files)

    def test_no_declarations_is_a_clear_failure(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            with self.assertRaisesRegex(SystemExit, "no App Intents declarations"):
                metadata_module_order({"App": [self.const_file(root, "App", [])]})

    def test_successful_process_without_fresh_output_rejects_stale_metadata_and_preserves_other_resources(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            metadata = root / "Metadata.appintents"
            metadata.mkdir()
            (metadata / "extract.actionsdata").write_text('{"actions": {"Old": {}}}')
            (root / "keep.txt").write_text("resource")
            output = io.StringIO()
            with patch("extract_app_intents_metadata.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "no relevant symbols", "")), redirect_stderr(output):
                with self.assertRaisesRegex(SystemExit, "produced no valid metadata"):
                    process_metadata(["processor"], "App", root)
            self.assertIn("no relevant symbols", output.getvalue())
            self.assertFalse(metadata.exists())
            self.assertTrue((root / "keep.txt").is_file())


class VerifyMetadataTests(unittest.TestCase):
    def test_actions_alone_cannot_satisfy_a_bundle_that_has_app_shortcuts(self) -> None:
        with self.assertRaisesRegex(SystemExit, "App Shortcuts provider or phrases"):
            verify_metadata({"actions": {"Capture": {}}}, "App", ["Capture"], True)

    def test_complete_shortcuts_metadata_is_accepted(self) -> None:
        verify_metadata({"actions": {"Capture": {}}, "autoShortcuts": [{}],
                         "autoShortcutProviderMangledName": "provider"}, "App", ["Capture"], True)

    def test_a_widget_requires_its_actions_but_not_an_app_shortcuts_provider(self) -> None:
        verify_metadata({"actions": {"Complete": {}}}, "Widget", ["Complete"], False)
        with self.assertRaisesRegex(SystemExit, "lacks Missing"):
            verify_metadata({"actions": {"Complete": {}}}, "Widget", ["Missing"], False)


class MetadataStringsTests(unittest.TestCase):
    def test_collects_localized_resources_but_not_phrase_templates(self) -> None:
        metadata = {
            "actions": {
                "Capture": {
                    "title": {"key": "capture.title", "table": "Localizable", "defaultValue": "Capture"},
                    "parameters": [{"title": {"key": "capture.list", "table": "Localizable"}}],
                }
            },
            "autoShortcuts": [{"phraseTemplates": [{"key": "Capture in ${applicationName}"}]}],
        }
        found: dict[tuple[str, str], str] = {}
        metadata_strings(metadata, found)
        self.assertEqual(
            found,
            {("Localizable", "capture.title"): "Capture", ("Localizable", "capture.list"): "capture.list"},
        )


class WriteMetadataTablesTests(unittest.TestCase):
    def test_writes_each_language_with_only_the_named_keys(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            resource = catalog(
                root / "Localizable.xcstrings",
                {
                    "capture.title": entry(en="Capture", **{"zh-Hans": "记录"}),
                    "unrelated": entry(en="Other", **{"zh-Hans": "其他"}),
                },
            )
            resources = root / "Resources"
            write_metadata_tables(
                {("Localizable", "capture.title"): "Capture"},
                [{"name": "Intents", "resources": [resource]}],
                resources,
            )
            with (resources / "zh-Hans.lproj" / "Localizable.strings").open("rb") as handle:
                self.assertEqual(plistlib.load(handle), {"capture.title": "记录"})
            with (resources / "en.lproj" / "Localizable.strings").open("rb") as handle:
                self.assertEqual(plistlib.load(handle), {"capture.title": "Capture"})

    def test_source_language_falls_back_to_the_default_value(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            resource = catalog(root / "Localizable.xcstrings", {"capture.title": entry(**{"zh-Hans": "记录"})})
            resources = root / "Resources"
            write_metadata_tables(
                {("Localizable", "capture.title"): "Capture"},
                [{"name": "Intents", "resources": [resource]}],
                resources,
            )
            with (resources / "en.lproj" / "Localizable.strings").open("rb") as handle:
                self.assertEqual(plistlib.load(handle), {"capture.title": "Capture"})

    def test_missing_key_or_translation_fails(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            resource = catalog(
                root / "Localizable.xcstrings",
                {"a": entry(en="A", **{"zh-Hans": "甲"}), "b": entry(en="B")},
            )
            targets = [{"name": "Intents", "resources": [resource]}]
            with self.assertRaises(SystemExit) as missing:
                write_metadata_tables({("Localizable", "c"): "C"}, targets, root / "Out")
            self.assertIn("is in no linked target", str(missing.exception))
            with self.assertRaises(SystemExit) as untranslated:
                write_metadata_tables({("Localizable", "b"): "B"}, targets, root / "Out")
            self.assertIn("no zh-Hans translation", str(untranslated.exception))

    def test_app_shortcuts_catalog_is_not_a_metadata_table(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            shortcuts = root / "AppShortcuts.xcstrings"
            resource = catalog(shortcuts, {"x": entry(en="X")})
            with self.assertRaises(SystemExit):
                write_metadata_tables(
                    {("AppShortcuts", "x"): "X"},
                    [{"name": "Intents", "resources": [resource]}],
                    root / "Out",
                )


if __name__ == "__main__":
    unittest.main()
