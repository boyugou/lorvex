#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verify_localization_arguments  # noqa: E402
from verify_localization_arguments import (  # noqa: E402
    ExtractedString,
    argument_failures,
    catalog_arguments,
    colliding_source_names,
    extracted_strings,
    normalized_type,
    source_calls,
    unextracted_calls,
    verify,
)


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(**forms: str) -> dict:
    return {"variations": {"plural": {category: unit(text) for category, text in forms.items()}}}


def substitution(value: str, name: str, argument: int, **forms: str) -> dict:
    return {
        **unit(value),
        "substitutions": {
            name: {
                "argNum": argument,
                "formatSpecifier": "lld",
                "variations": {"plural": {category: unit(text) for category, text in forms.items()}},
            }
        },
    }


class VerifyLocalizationArgumentsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def call(self, value: str) -> ExtractedString:
        return ExtractedString(source=self.root / "View.swift", line=3, key="k", value=value)

    def test_equivalent_printf_spellings_read_the_same_argument(self) -> None:
        self.assertEqual(normalized_type("ld"), normalized_type("lld"))
        self.assertEqual(normalized_type("lf"), normalized_type("f"))
        self.assertEqual(normalized_type("i"), normalized_type("d"))
        # A 32-bit integer is not a 64-bit one, and a C string is not an object.
        self.assertNotEqual(normalized_type("d"), normalized_type("lld"))
        self.assertNotEqual(normalized_type("u"), normalized_type("llu"))
        self.assertNotEqual(normalized_type("s"), normalized_type("@"))

    def test_a_call_whose_arguments_match_its_catalog_text_passes(self) -> None:
        call = self.call("%lld tasks in %@")

        self.assertEqual(
            argument_failures(call, "Cat", plural(one="%lld task in %@", other="%lld tasks in %@")),
            [],
        )
        self.assertEqual(argument_failures(self.call("%ld tasks"), "Cat", unit("%lld tasks")), [])

    def test_argument_failures_name_each_difference(self) -> None:
        call = self.call("%lld tasks in %@")
        prefix = f"{call.source}:3 'k' (Cat)"

        self.assertEqual(
            argument_failures(call, "Cat", unit("%1$@ tasks in %2$@ of %3$@")),
            [
                f"{prefix}: argument 1 is %lld in the code but %@ in the catalog text",
                f"{prefix}: the catalog text reads argument 3 (%@), which the code does not pass",
            ],
        )
        self.assertEqual(
            argument_failures(call, "Cat", unit("%lld tasks")),
            [f"{prefix}: the code passes argument 2 (%@), which the catalog text never shows"],
        )

    def test_plural_forms_and_substitutions_count_every_argument_they_read(self) -> None:
        # The `one` form may leave the number out; the other forms still read it.
        self.assertEqual(
            catalog_arguments(plural(one="A task in %2$@", other="%1$lld tasks in %2$@")),
            {1: "lld", 2: "@"},
        )
        self.assertEqual(
            catalog_arguments(
                substitution("%1$@: %#@count@", "count", 2, one="%arg task", other="%arg tasks")
            ),
            {1: "@", 2: "lld"},
        )

    def test_a_unit_word_reads_its_count_without_printing_it(self) -> None:
        # "days" under the goal ring's large "30": the count selects the form.
        unit_word = substitution("%#@unit@", "unit", 1, one="day", other="days")

        self.assertEqual(catalog_arguments(unit_word), {1: "lld"})
        self.assertEqual(argument_failures(self.call("%lld days"), "Cat", unit_word), [])

    def test_extracted_strings_reads_the_newest_record_of_each_existing_source(self) -> None:
        sources = self.root / "Sources"
        view = self.write("Sources/View.swift", "")
        outside = self.write("Other.swift", "")
        scratch = self.root / "scratch"

        def record(path: Path, source: Path, key: str, value: str, modified: int) -> None:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                json.dumps(
                    {
                        "source": str(source),
                        "tables": {
                            "Localizable": [
                                {
                                    "comment": "",
                                    "key": key,
                                    "location": {"startingColumn": 30, "startingLine": 4},
                                    "value": value,
                                }
                            ]
                        },
                        "version": 1,
                    }
                ),
                encoding="utf-8",
            )
            os.utime(path, (modified, modified))

        record(scratch / "a" / "View.stringsdata", view, "old.key", "Old", 1_000)
        record(scratch / "b" / "View.stringsdata", view, "new.key", "%lld new", 2_000)
        # An incremental build keeps the record of a deleted file.
        record(scratch / "c" / "Gone.stringsdata", sources / "Gone.swift", "gone.key", "Gone", 3_000)
        # Dependencies compile with the package and write records too.
        record(scratch / "d" / "Other.stringsdata", outside, "other.key", "Other", 3_000)

        self.assertEqual(
            extracted_strings(scratch, sources),
            [ExtractedString(source=view, line=4, key="new.key", value="%lld new")],
        )

    def test_source_calls_report_the_key_literal_line_and_bundle_token(self) -> None:
        source = self.write(
            "View.swift",
            "let a = String(\n"
            '  localized: "a.key", defaultValue: "\\(count) tasks", table: "Localizable", '
            "bundle: LorvexL10n.bundle)\n"
            'let b = LocalizedStringResource("b.key", defaultValue: "B", table: "Localizable", '
            "bundle: MobileL10n.bundle)\n"
            'let c = String(localized: key, defaultValue: "C", bundle: LorvexL10n.bundle)\n'
            'let d = String(localized: "d.key", defaultValue: "D", bundle: bundle(for: self))\n',
        )

        self.assertEqual(
            source_calls(source),
            [
                ("a.key", 2, "LorvexL10n.bundle"),
                ("d.key", 5, None),
                ("b.key", 3, "MobileL10n.bundle"),
            ],
        )

    def test_colliding_source_names_lists_shared_basenames_of_localizing_files(self) -> None:
        self.write("A/Row.swift", 'String(localized: "a", defaultValue: "A")')
        self.write("B/Row.swift", 'LocalizedStringResource("b", defaultValue: "B")')
        self.write("A/Model.swift", 'String(localized: "m", defaultValue: "M")')
        self.write("B/Model.swift", "struct Model {}")

        self.assertEqual(colliding_source_names(self.root), ["Row.swift"])

    def test_verify_checks_each_call_against_the_catalog_its_bundle_names(self) -> None:
        catalog_path = self.write(
            "Localizable.xcstrings",
            json.dumps(
                {
                    "sourceLanguage": "en",
                    "strings": {
                        "tasks.count": {
                            "localizations": {"en": plural(one="%lld task", other="%lld tasks")}
                        },
                        "list.name": {"localizations": {"en": unit("List %lld")}},
                    },
                }
            ),
        )
        source = self.write(
            "View.swift",
            'String(localized: "tasks.count", defaultValue: "\\(count) tasks", bundle: LorvexL10n.bundle)\n'
            'String(localized: "list.name", defaultValue: "List \\(name)", bundle: LorvexL10n.bundle)\n'
            'String(localized: "missing.key", defaultValue: "\\(name)", bundle: LorvexL10n.bundle)\n'
            'String(localized: "list.name", defaultValue: "\\(name)", bundle: Other.bundle)\n',
        )
        strings = [
            ExtractedString(source, 1, "tasks.count", "%lld tasks"),
            ExtractedString(source, 2, "list.name", "List %@"),
            # A key the catalog lacks is the catalog verifier's finding.
            ExtractedString(source, 3, "missing.key", "%@"),
            # A bundle no catalog owns is not checked.
            ExtractedString(source, 4, "list.name", "%@"),
        ]

        with mock.patch.object(
            verify_localization_arguments,
            "catalog_for_token",
            return_value={"LorvexL10n.bundle": catalog_path},
        ):
            failures, checked = verify(strings)

        self.assertEqual(
            failures,
            [
                f"{source}:2 'list.name' ({catalog_path}): argument 1 is %@ in the code but "
                "%lld in the catalog text"
            ],
        )
        self.assertEqual(checked, {(str(catalog_path), "tasks.count"), (str(catalog_path), "list.name")})

    def test_unextracted_calls_lists_owned_calls_the_build_did_not_compile(self) -> None:
        sources = self.root / "Sources"
        source = self.write(
            "Sources/Scene.swift",
            'String(localized: "seen.key", defaultValue: "Seen", bundle: LorvexL10n.bundle)\n'
            "#if os(iOS)\n"
            'String(localized: "ios.key", defaultValue: "iOS", bundle: LorvexL10n.bundle)\n'
            "#endif\n"
            'String(localized: "foreign.key", defaultValue: "Foreign", bundle: Bundle.main)\n',
        )
        strings = [ExtractedString(source, 1, "seen.key", "Seen")]

        with mock.patch.object(
            verify_localization_arguments,
            "catalog_for_token",
            return_value={"LorvexL10n.bundle": self.root / "Localizable.xcstrings"},
        ):
            missing = unextracted_calls(strings, sources)

        self.assertEqual(missing, [f"{source}:3 'ios.key'"])


if __name__ == "__main__":
    unittest.main()
