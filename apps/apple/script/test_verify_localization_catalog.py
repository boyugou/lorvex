#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import verify_localization_catalog
from verify_localization_catalog import (
    CATALOG_PATH,
    INTERPOLATION_MARK,
    MODULE_CATALOGS,
    MODULE_RESOURCE_BUNDLE_TOKENS,
    NON_LITERAL_MARK,
    ROOT,
    _parse_concat_string,
    app_shortcut_phrase_failures,
    apple_native_bundle_qualification_failures,
    bare_localization_text_failures,
    default_value_equality_failures,
    load_catalog,
    catalog_entry_failures,
    catalog_languages,
    catalog_source_language,
    catalog_structure_failures,
    cjk_number_unit_spacing_failures,
    copied_source_translation_failures,
    english_typographic_quote_failures,
    hardcoded_system_case_display_failures,
    hardcoded_system_intent_metadata_failures,
    generated_app_info_plist_values,
    generated_info_plist_strings_failures,
    info_plist_strings_failures,
    implicit_localized_string_resource_failures,
    localized_info_plist_keys,
    native_localized_string_bundle_keys,
    native_localized_text_bundle_keys,
    non_count_allowlist_failures,
    orphan_info_plist_target_failures,
    parse_info_plist_strings,
    referenced_module_keys,
    localized_string_resource_bundle_keys,
    mobile_native_bundle_qualification_failures,
    module_owned_reference_keys,
    module_resource_reference_failures,
    module_reference_failures,
    module_reference_presence_failures,
    plist_localization_failures,
    plural_rules_for,
    referenced_app_keys,
    required_languages,
    required_source_language,
    shipping_bundle_plists,
    source_reference_failures,
    swift_source_without_comments,
    system_intent_bundle_qualification_failures,
    sync_plist_localizations,
    undeclared_plural_language_failures,
    unreferenced_module_key_failures,
)


def catalog_with_strings(
    strings: dict[str, object],
    source_language: str = "en",
) -> dict[str, object]:
    return {
        "sourceLanguage": source_language,
        "version": "1.0",
        "strings": strings,
    }


def entry(
    value: str = "Today",
    state: str = "translated",
    extra_localizations: dict[str, str] | None = None,
) -> dict[str, object]:
    localizations: dict[str, object] = {
        "en": {
            "stringUnit": {
                "state": state,
                "value": value,
            }
        }
    }
    for language, localized_value in (extra_localizations or {}).items():
        localizations[language] = {
            "stringUnit": {
                "state": "translated",
                "value": localized_value,
            }
        }
    return {
        "extractionState": "manual",
        "localizations": localizations,
    }


def string_unit(text: str) -> dict[str, object]:
    """A translated text: a plain localization, or one plural form."""
    return {"stringUnit": {"state": "translated", "value": text}}


def plural_substitution(argument: int, forms: dict[str, str]) -> dict[str, object]:
    """A substitution that varies the integer argument `argument` by plural."""
    return {
        "argNum": argument,
        "formatSpecifier": "lld",
        "variations": {"plural": {category: string_unit(text) for category, text in forms.items()}},
    }


def substitution_localization(
    value: str, substitutions: dict[str, dict[str, object]]
) -> dict[str, object]:
    return {**string_unit(value), "substitutions": substitutions}


def bad_entry(value: str = "Today", state: str = "translated") -> dict[str, object]:
    return {
        "extractionState": "manual",
        "localizations": {
            "en": {
                "stringUnit": {
                    "state": state,
                    "value": value,
                }
            }
        },
    }


class VerifyLocalizationCatalogTests(unittest.TestCase):
    def test_module_catalogs_include_system_intents(self) -> None:
        helpers = {helper for helper, _, _ in MODULE_CATALOGS}

        self.assertIn("SystemL10n", helpers)

    def test_widget_support_catalog_scans_watch_consumers(self) -> None:
        roots = next(
            roots
            for helper, _catalog_path, roots in MODULE_CATALOGS
            if helper == "WidgetSupportL10n"
        )

        self.assertIn(ROOT / "Sources" / "LorvexWatch", roots)

    def test_catalog_structure_accepts_expected_metadata(self) -> None:
        self.assertEqual(catalog_structure_failures(catalog_with_strings({})), [])

    def test_load_catalog_rejects_duplicate_json_keys_at_any_depth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.xcstrings"
            path.write_text(
                '{"sourceLanguage":"en","version":"1.0","strings":'
                '{"today":{"localizations":{"en":{},"en":{}}}}}',
                encoding="utf-8",
            )

            catalog, failures = load_catalog(path)

            self.assertEqual(catalog, {})
            self.assertEqual(len(failures), 1)
            self.assertIn("duplicate JSON object key 'en'", failures[0])

    def test_swift_comment_mask_preserves_strings_positions_and_nested_comments(self) -> None:
        source = (
            'Text("live.key", bundle: Bundle.module) // Text("comment.key")\n'
            '/* outer\n  /* Text("nested.key") */\n*/\n'
            'let url = "https://lorvex.app/privacy/"\n'
        )

        masked = swift_source_without_comments(source)

        self.assertEqual(len(masked), len(source))
        self.assertEqual(masked.count("\n"), source.count("\n"))
        self.assertIn('Text("live.key", bundle: Bundle.module)', masked)
        self.assertIn('"https://lorvex.app/privacy/"', masked)
        self.assertNotIn("comment.key", masked)
        self.assertNotIn("nested.key", masked)

    def test_catalog_structure_rejects_wrong_source_language_and_version(self) -> None:
        self.assertEqual(
            catalog_structure_failures(
                {"sourceLanguage": "fr", "version": "2.0", "strings": []}
            ),
            [
                "sourceLanguage mismatch: 'fr'",
                "version mismatch: '2.0'",
                "strings mismatch: []",
            ],
        )

    def test_catalog_structure_accepts_declared_non_english_source_language(self) -> None:
        catalog = catalog_with_strings({}, source_language="fr")

        self.assertEqual(catalog_source_language(catalog), "fr")
        self.assertEqual(required_source_language([catalog]), "fr")
        self.assertEqual(catalog_structure_failures(catalog, source_language="fr"), [])

    def test_catalog_structure_requires_all_catalogs_to_share_source_language(self) -> None:
        primary = catalog_with_strings({}, source_language="fr")
        module = catalog_with_strings({}, source_language="en")
        source_language = required_source_language([primary, module])

        self.assertEqual(source_language, "fr")
        self.assertEqual(
            catalog_structure_failures(module, source_language=source_language),
            ["sourceLanguage mismatch: 'en'"],
        )

    def test_info_plist_strings_failures_exempts_background_only_agent(self) -> None:
        import plistlib
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp) / "LorvexMCPHost-Info.plist"
            plist_path.write_bytes(plistlib.dumps({
                "CFBundleName": "LorvexMCPHost",
                "CFBundleDisplayName": "Lorvex MCP Host",
                "LSUIElement": True,
                "LSBackgroundOnly": True,
            }))
            # A headless helper needs no per-language InfoPlist.strings mapping.
            self.assertEqual(
                info_plist_strings_failures(plist_path, ("en", "de"), config_root=Path(tmp)),
                [],
            )

    def test_info_plist_strings_failures_still_requires_mapping_for_ui_bundle(self) -> None:
        import plistlib
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp) / "SomeUiApp-Info.plist"
            plist_path.write_bytes(plistlib.dumps({
                "CFBundleName": "SomeUiApp",
                "CFBundleDisplayName": "Some UI App",
            }))
            failures = info_plist_strings_failures(plist_path, ("en",), config_root=Path(tmp))
            self.assertTrue(any("no InfoPlist resource target mapping" in f for f in failures))

    def test_catalog_entry_failures_rejects_missing_required_key_and_empty_source_value(self) -> None:
        failures = catalog_entry_failures(
            catalog_with_strings(
                {
                    "sidebar.section.plan": bad_entry(""),
                    "sidebar.item.memory": bad_entry("Memory", state="new"),
                }
            ),
            required_keys={"missing.key"},
        )

        self.assertIn("sidebar.section.plan missing non-empty en stringUnit.value", failures)
        self.assertIn("sidebar.item.memory en stringUnit.state mismatch: 'new'", failures)
        self.assertTrue(any("required localization key(s) missing" in failure for failure in failures))

    def test_cjk_number_unit_spacing_failures_rejects_a_breaking_space_after_a_number(self) -> None:
        catalog = catalog_with_strings(
            {
                "duration": entry("%lld min", extra_localizations={"zh-Hans": "%lld 分钟"}),
                "count": entry("1 task", extra_localizations={"zh-Hans": "1 项任务"}),
            }
        )

        self.assertEqual(
            cjk_number_unit_spacing_failures(catalog),
            [
                "duration zh-Hans breaks between a number and its unit at '%lld '; "
                "use a no-break space (U+00A0)",
                "count zh-Hans breaks between a number and its unit at '1 '; "
                "use a no-break space (U+00A0)",
            ],
        )

    def test_cjk_number_unit_spacing_failures_allows_bound_units_and_other_spaces(self) -> None:
        catalog = catalog_with_strings(
            {
                "duration": entry(
                    "%1$lld hr %2$lld min",
                    extra_localizations={"zh-Hans": "%1$lld\u00a0小时\u00a0%2$lld\u00a0分钟"},
                ),
                "remaining": entry("%@ left", extra_localizations={"zh-Hans": "还剩 %@"}),
                "until": entry("Until %@", extra_localizations={"zh-Hans": "%@ 结束"}),
                "english": entry("3 tasks"),
            }
        )

        self.assertEqual(cjk_number_unit_spacing_failures(catalog), [])

    def test_cjk_number_unit_spacing_failures_checks_substitution_forms(self) -> None:
        value = entry("%lld tasks", extra_localizations={"zh-Hans": "placeholder replaced below"})
        value["localizations"]["zh-Hans"] = {
            "stringUnit": {"state": "translated", "value": "%#@tasks@"},
            "substitutions": {
                "tasks": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "other": {"stringUnit": {"state": "translated", "value": "%arg 项任务"}}
                        }
                    },
                }
            },
        }

        self.assertEqual(
            cjk_number_unit_spacing_failures(catalog_with_strings({"tasks": value})),
            [
                "tasks zh-Hans breaks between a number and its unit at '%arg '; "
                "use a no-break space (U+00A0)"
            ],
        )

    def test_english_typographic_quote_failures_rejects_straight_marks(self) -> None:
        catalog = catalog_with_strings(
            {
                "error": entry("Couldn't load tasks"),
                "confirm": entry('Delete "%@"?'),
            }
        )

        self.assertEqual(
            english_typographic_quote_failures(catalog),
            [
                "error en uses a straight quote mark in \"Couldn't load tasks\"; use ’ or “…”",
                "confirm en uses a straight quote mark in 'Delete \"%@\"?'; use ’ or “…”",
            ],
        )

    def test_english_typographic_quote_failures_allows_curly_marks_and_other_languages(self) -> None:
        catalog = catalog_with_strings(
            {
                "error": entry("Couldn’t load tasks", extra_localizations={"zh-Hans": "无法加载任务"}),
                "confirm": entry("Delete “%@”?", extra_localizations={"fr": "Supprimer l'élément"}),
            }
        )

        self.assertEqual(english_typographic_quote_failures(catalog), [])

    def test_copied_source_translation_failures_rejects_all_locale_prose_copy(self) -> None:
        catalog = catalog_with_strings(
            {
                "settings.title": entry(
                    "Settings", extra_localizations={"de": "Settings", "fr": "Settings"}
                )
            }
        )

        self.assertEqual(
            copied_source_translation_failures(catalog, ("de", "en", "fr")),
            [
                "settings.title copies source-language prose into every non-source localization"
            ],
        )

    def test_copied_source_translation_failures_allows_real_translation_and_templates(self) -> None:
        catalog = catalog_with_strings(
            {
                "settings.title": entry(
                    "Settings", extra_localizations={"de": "Einstellungen", "fr": "Settings"}
                ),
                "template": entry(
                    "%1$@ · %2$@",
                    extra_localizations={"de": "%1$@ · %2$@", "fr": "%1$@ · %2$@"},
                ),
                "numeric_template": entry(
                    "%@: %lld",
                    extra_localizations={"de": "%@: %lld", "fr": "%@: %lld"},
                ),
                "brand": entry(
                    "CloudKit", extra_localizations={"de": "CloudKit", "fr": "CloudKit"}
                ),
            }
        )

        self.assertEqual(
            copied_source_translation_failures(
                catalog, ("de", "en", "fr"), {"brand"}
            ),
            [],
        )

    def test_copied_source_translation_failures_rejects_plural_leaf_copy(self) -> None:
        def plural(forms: dict[str, str]) -> dict[str, object]:
            return {
                "variations": {
                    "plural": {
                        category: {
                            "stringUnit": {
                                "state": "translated",
                                "value": value,
                            }
                        }
                        for category, value in forms.items()
                    }
                }
            }

        catalog = catalog_with_strings(
            {
                "count": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": plural({"one": "%lld item", "other": "%lld items"}),
                        "de": plural({"one": "%lld item", "other": "%lld items"}),
                        "fr": plural({"one": "%lld item", "other": "%lld items"}),
                    },
                }
            }
        )

        self.assertEqual(
            copied_source_translation_failures(catalog, ("de", "en", "fr")),
            ["count copies source-language prose into every non-source localization"],
        )

    def test_copied_source_translation_failures_rejects_plain_copy_of_a_plural_form(self) -> None:
        def plural(forms: dict[str, str]) -> dict[str, object]:
            return {
                "variations": {
                    "plural": {
                        category: {"stringUnit": {"state": "translated", "value": value}}
                        for category, value in forms.items()
                    }
                }
            }

        def plain(value: str) -> dict[str, object]:
            return {"stringUnit": {"state": "translated", "value": value}}

        english = plural({"one": "%lld day", "other": "%lld days"})
        catalog = catalog_with_strings(
            {
                "copied": {
                    "extractionState": "manual",
                    "localizations": {"en": english, "zh-Hans": plain("%lld days")},
                },
                "translated": {
                    "extractionState": "manual",
                    "localizations": {"en": english, "zh-Hans": plain("%lld 天")},
                },
            }
        )

        self.assertEqual(
            copied_source_translation_failures(catalog, ("en", "zh-Hans")),
            ["copied copies source-language prose into every non-source localization"],
        )

    def test_app_shortcut_phrase_failures(self) -> None:
        def phrase(translation: str | None) -> dict[str, object]:
            if translation is None:
                return {}
            return {
                "localizations": {
                    "zh-Hans": {"stringUnit": {"state": "translated", "value": translation}}
                }
            }

        catalog = {
            "sourceLanguage": "en",
            "version": "1.0",
            "strings": {
                "Open ${applicationName}": phrase("打开 ${applicationName}"),
                "Search tasks in ${applicationName}": phrase("Search tasks in ${applicationName}"),
                "List tasks in ${applicationName}": phrase("列出任务"),
                "Show the weekly review": phrase("显示每周回顾"),
                "Add habit in ${applicationName}": phrase(None),
            },
        }

        self.assertEqual(
            app_shortcut_phrase_failures(catalog, ("en", "zh-Hans")),
            [
                "App Shortcut phrase 'Search tasks in ${applicationName}' copies English into zh-Hans",
                "App Shortcut phrase 'List tasks in ${applicationName}' (zh-Hans) must contain ${applicationName} exactly once",
                "App Shortcut phrase 'Show the weekly review' must contain ${applicationName} exactly once",
                "App Shortcut phrase 'Show the weekly review' (zh-Hans) must contain ${applicationName} exactly once",
                "App Shortcut phrase 'Add habit in ${applicationName}' has no zh-Hans translation",
            ],
        )

    def test_copied_source_translation_failures_rejects_substitution_plural_copy(self) -> None:
        def substitution() -> dict[str, object]:
            return {
                "stringUnit": {
                    "state": "translated",
                    "value": "%1$@ · %#@count@",
                },
                "substitutions": {
                    "count": {
                        "argNum": 2,
                        "formatSpecifier": "lld",
                        "variations": {
                            "plural": {
                                "one": {
                                    "stringUnit": {
                                        "state": "translated",
                                        "value": "%arg copied item",
                                    }
                                },
                                "other": {
                                    "stringUnit": {
                                        "state": "translated",
                                        "value": "%arg copied items",
                                    }
                                },
                            }
                        },
                    }
                },
            }

        catalog = catalog_with_strings(
            {
                "count": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": substitution(),
                        "de": substitution(),
                        "fr": substitution(),
                    },
                }
            }
        )

        self.assertEqual(
            copied_source_translation_failures(catalog, ("de", "en", "fr")),
            ["count copies source-language prose into every non-source localization"],
        )

    def test_required_languages_are_discovered_from_all_catalogs(self) -> None:
        first = catalog_with_strings({"today": entry(extra_localizations={"ar": "اليوم"})})
        second = catalog_with_strings({"today": entry(extra_localizations={"fr": "Aujourd’hui"})})

        self.assertEqual(catalog_languages(first), {"ar", "en"})
        self.assertEqual(required_languages([first, second]), ("ar", "en", "fr"))

    def test_required_languages_include_each_catalog_source_language(self) -> None:
        first = catalog_with_strings({"today": entry(extra_localizations={"ar": "اليوم"})})
        second = catalog_with_strings({}, source_language="fr")

        self.assertEqual(catalog_languages(second), {"fr"})
        self.assertEqual(required_languages([first, second]), ("ar", "en", "fr"))

    def test_catalog_entry_failures_requires_every_discovered_language(self) -> None:
        failures = catalog_entry_failures(
            catalog_with_strings({"today": entry(extra_localizations={"ar": "اليوم"})}),
            languages=("ar", "en", "fr"),
        )

        self.assertIn("today missing non-empty fr stringUnit.value", failures)
        self.assertIn("today fr stringUnit.state mismatch: None", failures)

    def test_catalog_entry_failures_requires_localized_format_placeholders_to_match_source(self) -> None:
        failures = catalog_entry_failures(
            catalog_with_strings(
                {
                    "task.result": entry(
                        "%d matching tasks: %@",
                        extra_localizations={
                            "fr": "%@ tâches correspondantes",
                            "ja": "%2$@：%1$d 件",
                        },
                    )
                }
            ),
            languages=("en", "fr", "ja"),
        )

        self.assertIn(
            "task.result fr format placeholder mismatch: [(1, '@')]; "
            "expected [(1, 'd'), (2, '@')]",
            failures,
        )
        self.assertFalse(any("task.result ja" in failure for failure in failures))

    def test_catalog_entry_failures_checks_every_plural_leaf_argument_type(self) -> None:
        def plural(one: str, other: str) -> dict[str, object]:
            return {
                "variations": {
                    "plural": {
                        "one": {
                            "stringUnit": {"state": "translated", "value": one}
                        },
                        "other": {
                            "stringUnit": {"state": "translated", "value": other}
                        },
                    }
                }
            }

        catalog = catalog_with_strings(
            {
                "records": {
                    "extractionState": "manual",
                    "localizations": {
                        # Omitting the rendered count in a singular leaf is
                        # valid; the source union still declares argument 1/lld.
                        "en": plural("1 record", "%lld records"),
                        # `other` matches and was all the old verifier checked;
                        # `one` illegally reinterprets the count as an object.
                        "fr": plural("%@ enregistrement", "%lld enregistrements"),
                    },
                }
            }
        )

        failures = catalog_entry_failures(catalog, languages=("en", "fr"))

        self.assertIn(
            "records fr plural 'one' argument 1 type mismatch: '@'; expected 'lld'",
            failures,
        )

    @staticmethod
    def _plural_localization(forms: dict[str, str]) -> dict[str, object]:
        return {
            "variations": {
                "plural": {
                    category: {"stringUnit": {"state": "translated", "value": value}}
                    for category, value in forms.items()
                }
            }
        }

    def _plural_entry(self, forms_by_language: dict[str, dict[str, str]]) -> dict[str, object]:
        return {
            "extractionState": "manual",
            "localizations": {
                language: self._plural_localization(forms)
                for language, forms in forms_by_language.items()
            },
        }

    def test_catalog_entry_failures_requires_each_languages_cldr_plural_categories(self) -> None:
        catalog = catalog_with_strings(
            {
                "tasks.count": self._plural_entry(
                    {
                        "en": {"one": "%lld task", "other": "%lld tasks"},
                        # Russian counts select one, few, and many; `other`
                        # alone would render "5 задачи" for every count.
                        "ru": {"one": "%lld задача", "other": "%lld задачи"},
                    }
                )
            }
        )

        self.assertIn(
            "tasks.count ru plural variations missing CLDR categories ['few', 'many']",
            catalog_entry_failures(catalog, languages=("en", "ru")),
        )

    def test_catalog_entry_failures_rejects_plural_categories_a_language_never_selects(self) -> None:
        catalog = catalog_with_strings(
            {
                "tasks.count": self._plural_entry(
                    {
                        "en": {"one": "%lld task", "other": "%lld tasks"},
                        "zh-Hans": {"one": "%lld 项任务", "other": "%lld 项任务"},
                    }
                )
            }
        )

        self.assertIn(
            "tasks.count zh-Hans plural variations carry ['one'], which zh-Hans never selects",
            catalog_entry_failures(catalog, languages=("en", "zh-Hans")),
        )

    def test_catalog_entry_failures_accepts_optional_and_zero_plural_categories(self) -> None:
        catalog = catalog_with_strings(
            {
                "tasks.count": self._plural_entry(
                    {
                        "en": {"zero": "No tasks", "one": "%lld task", "other": "%lld tasks"},
                        "es": {
                            "one": "%lld tarea",
                            "many": "%lld de tareas",
                            "other": "%lld tareas",
                        },
                    }
                )
            }
        )

        self.assertEqual(catalog_entry_failures(catalog, languages=("en", "es")), [])

    def test_catalog_entry_failures_checks_substitution_plural_categories(self) -> None:
        value = entry("%lld open", extra_localizations={"es": "placeholder replaced below"})
        value["localizations"]["es"] = {
            "stringUnit": {"state": "translated", "value": "%#@open@"},
            "substitutions": {
                "open": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "other": {
                                "stringUnit": {"state": "translated", "value": "%arg abiertas"}
                            }
                        }
                    },
                }
            },
        }

        self.assertIn(
            "widget.open substitution 'open' es plural variations missing CLDR categories ['one']",
            catalog_entry_failures(
                catalog_with_strings({"widget.open": value}), languages=("en", "es")
            ),
        )

    def test_a_one_form_shows_the_number_where_one_also_counts_other_numbers(self) -> None:
        catalog = catalog_with_strings(
            {
                "weekly": self._plural_entry(
                    {
                        # English `one` is 1 alone, so it may read "Once a week".
                        "en": {"one": "Once a week", "other": "%lld times a week"},
                        # French `one` also covers 0; Russian `one` also covers 21.
                        "fr": {"one": "Une fois par semaine", "other": "%lld fois par semaine"},
                        "ru": {
                            "one": "Раз в неделю",
                            "few": "%lld раза в неделю",
                            "many": "%lld раз в неделю",
                            "other": "%lld раза в неделю",
                        },
                    }
                )
            }
        )

        failures = catalog_entry_failures(catalog, languages=("en", "fr", "ru"))

        self.assertIn(
            "weekly fr plural 'one' leaves out the number, but fr also uses 'one' for 0; "
            "show the count",
            failures,
        )
        self.assertIn(
            "weekly ru plural 'one' leaves out the number, but ru also uses 'one' for "
            "21, 31, 101, …; show the count",
            failures,
        )
        self.assertFalse(any(failure.startswith("weekly en") for failure in failures))

    def test_a_count_stays_with_its_word_in_russian_ukrainian_and_polish(self) -> None:
        catalog = catalog_with_strings(
            {
                "added": self._plural_entry(
                    {
                        "en": {"one": "%lld task added", "other": "%lld tasks added"},
                        "ru": {
                            "one": "Добавлена %lld\u00a0задача",
                            "few": "Добавлено %lld\u00a0задачи",
                            "many": "Добавлено %lld задач",
                            "other": "Добавлено %lld\u00a0задачи",
                        },
                    }
                )
            }
        )

        failures = catalog_entry_failures(catalog, languages=("en", "ru"))

        self.assertIn(
            "added ru keeps a plain space after a count in 'Добавлено %lld задач'; "
            "use a no-break space (U+00A0) so the number stays with its word",
            failures,
        )
        self.assertFalse(any(failure.startswith("added en") for failure in failures))

    def test_a_zero_form_takes_0_over_from_one(self) -> None:
        catalog = catalog_with_strings(
            {
                "weekly": self._plural_entry(
                    {
                        "en": {"one": "Once a week", "other": "%lld times a week"},
                        "fr": {
                            "zero": "Jamais",
                            "one": "Une fois par semaine",
                            "other": "%lld fois par semaine",
                        },
                    }
                )
            }
        )

        self.assertEqual(catalog_entry_failures(catalog, languages=("en", "fr")), [])

    def test_the_one_form_rule_covers_substitutions(self) -> None:
        value = entry("%lld open", extra_localizations={"ru": "placeholder replaced below"})

        def form(text: str) -> dict[str, object]:
            return {"stringUnit": {"state": "translated", "value": text}}

        value["localizations"]["ru"] = {
            "stringUnit": {"state": "translated", "value": "%#@open@"},
            "substitutions": {
                "open": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "one": form("открыта"),
                            "few": form("%arg открыты"),
                            "many": form("%arg открыто"),
                            "other": form("%arg открыто"),
                        }
                    },
                }
            },
        }

        self.assertIn(
            "widget.open substitution 'open' ru plural 'one' leaves out the number, but ru "
            "also uses 'one' for 21, 31, 101, …; show the count",
            catalog_entry_failures(
                catalog_with_strings({"widget.open": value}), languages=("en", "ru")
            ),
        )

    def test_every_shipped_language_must_declare_its_plural_rules(self) -> None:
        self.assertEqual(undeclared_plural_language_failures(("en", "pt-BR", "zh-Hant")), [])
        self.assertEqual(
            undeclared_plural_language_failures(("en", "xx")),
            [
                "shipped language 'xx' has no CLDR plural categories in PLURAL_CATEGORIES; "
                "declare them before shipping its translations"
            ],
        )
        required, allowed = plural_rules_for("zh-Hans") or (frozenset(), frozenset())
        self.assertEqual(required, {"other"})
        self.assertEqual(allowed, {"zero", "other"})

    def test_catalog_entry_failures_understands_locale_specific_plural_substitutions(self) -> None:
        # Each language names and words its own substitutions; only the
        # arguments they stand for must agree.
        value = entry(
            "placeholder replaced below",
            extra_localizations={"es": "placeholder replaced below"},
        )
        value["localizations"]["en"] = substitution_localization(
            "%#@done@ · %#@open@",
            {
                "done": plural_substitution(1, {"one": "%arg completed", "other": "%arg completed"}),
                "open": plural_substitution(2, {"one": "%arg open", "other": "%arg open"}),
            },
        )
        value["localizations"]["es"] = {
            "stringUnit": {
                "state": "translated",
                "value": "%#@completed@ · %#@open@",
            },
            "substitutions": {
                "completed": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "one": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg completada",
                                }
                            },
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg completadas",
                                }
                            },
                        }
                    },
                },
                "open": {
                    "argNum": 2,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "one": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg abierta",
                                }
                            },
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg abiertas",
                                }
                            },
                        }
                    },
                },
            },
        }

        self.assertEqual(
            catalog_entry_failures(
                catalog_with_strings({"widget.footer": value}),
                languages=("en", "es"),
            ),
            [],
        )

    def test_catalog_entry_failures_rejects_duplicate_substitution_argument_numbers(self) -> None:
        value = entry(
            "%1$lld completed · %2$lld open",
            extra_localizations={"es": "placeholder replaced below"},
        )
        value["localizations"]["es"] = {
            "stringUnit": {
                "state": "translated",
                "value": "%#@completed@ · %#@open@",
            },
            "substitutions": {
                name: {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": f"%arg {name}",
                                }
                            }
                        }
                    },
                }
                for name in ("completed", "open")
            },
        }

        failures = catalog_entry_failures(
            catalog_with_strings({"widget.footer": value}),
            languages=("en", "es"),
        )
        self.assertTrue(any("duplicate substitution argNum" in failure for failure in failures))

    def test_catalog_entry_failures_rejects_missing_substitution_argument_position(self) -> None:
        value = entry(
            "%1$lld completed · %2$lld open",
            extra_localizations={"es": "placeholder replaced below"},
        )
        value["localizations"]["es"] = {
            "stringUnit": {
                "state": "translated",
                "value": "%#@completed@ · %#@open@",
            },
            "substitutions": {
                name: {
                    "argNum": argument_number,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": f"%arg {name}",
                                }
                            }
                        }
                    },
                }
                for name, argument_number in (("completed", 1), ("open", 3))
            },
        }

        failures = catalog_entry_failures(
            catalog_with_strings({"widget.footer": value}),
            languages=("en", "es"),
        )
        self.assertTrue(any("format placeholder mismatch" in failure for failure in failures))

    def test_catalog_entry_failures_allows_reusing_one_substitution_marker(self) -> None:
        value = self._plural_entry(
            {"en": {"one": "%1$lld task, %1$lld total", "other": "%1$lld tasks, %1$lld total"}}
        )
        value["localizations"]["es"] = {
            "stringUnit": {
                "state": "translated",
                "value": "%#@count@ tareas, %#@count@ en total",
            },
            "substitutions": {
                "count": {
                    "argNum": 1,
                    "formatSpecifier": "lld",
                    "variations": {
                        "plural": {
                            "one": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg",
                                }
                            },
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg",
                                }
                            },
                        }
                    },
                }
            },
        }

        self.assertEqual(
            catalog_entry_failures(
                catalog_with_strings({"widget.count": value}),
                languages=("en", "es"),
            ),
            [],
        )

    def test_a_count_in_the_source_text_varies_by_plural(self) -> None:
        # English writes "1 completed" and "5 completed" alike, but the source's
        # plural forms are the ones every translator fills in for their language.
        plain = catalog_with_strings({"tasks.completed": entry("%lld completed")})
        varied = catalog_with_strings(
            {
                "tasks.completed": self._plural_entry(
                    {"en": {"one": "%lld completed", "other": "%lld completed"}}
                )
            }
        )

        self.assertEqual(
            catalog_entry_failures(plain),
            [
                "tasks.completed en argument 1 is a count (%lld) with no plural forms; vary it by "
                "plural, or list it in NON_COUNT_INTEGER_ARGUMENTS with the reason it counts nothing"
            ],
        )
        self.assertEqual(catalog_entry_failures(varied), [])

    def test_a_top_level_plural_varies_by_one_count_only(self) -> None:
        catalog = catalog_with_strings(
            {
                "habits.done": self._plural_entry(
                    {"en": {"one": "%1$lld of %2$lld habit", "other": "%1$lld of %2$lld habits"}}
                )
            }
        )

        self.assertEqual(
            catalog_entry_failures(catalog),
            [
                "habits.done en varies by plural at the top level but formats the integer "
                "arguments [1, 2]; vary each count with its own substitution"
            ],
        )

    def test_a_listed_non_count_argument_needs_no_plural_forms(self) -> None:
        catalog = catalog_with_strings({"tasks.pending": entry("Pending: %lld")})

        with mock.patch.dict(
            verify_localization_catalog.NON_COUNT_INTEGER_ARGUMENTS,
            {"tasks.pending": {1: "a value after its label"}},
            clear=True,
        ):
            self.assertEqual(catalog_entry_failures(catalog), [])
            self.assertEqual(non_count_allowlist_failures([catalog]), [])
        with mock.patch.dict(
            verify_localization_catalog.NON_COUNT_INTEGER_ARGUMENTS, {}, clear=True
        ):
            self.assertEqual(
                catalog_entry_failures(catalog),
                [
                    "tasks.pending en argument 1 is a count (%lld) with no plural forms; vary it by "
                    "plural, or list it in NON_COUNT_INTEGER_ARGUMENTS with the reason it counts nothing"
                ],
            )

    def test_a_non_count_listing_that_exempts_nothing_fails(self) -> None:
        catalog = catalog_with_strings(
            {
                "greeting": entry("Hello, %@"),
                "tasks.count": self._plural_entry({"en": {"one": "%lld task", "other": "%lld tasks"}}),
                "tasks.pending": entry("Pending: %lld"),
            }
        )
        listing = {
            "greeting": {1: "a name"},
            "missing.key": {1: "a ratio"},
            "tasks.count": {1: "a ratio"},
            "tasks.pending": {1: "a value after its label"},
        }

        with mock.patch.dict(
            verify_localization_catalog.NON_COUNT_INTEGER_ARGUMENTS, listing, clear=True
        ):
            failures = non_count_allowlist_failures([catalog])

        self.assertEqual(
            failures,
            [
                "NON_COUNT_INTEGER_ARGUMENTS exempts 'greeting' argument 1, which is not an "
                "integer argument without plural forms",
                "NON_COUNT_INTEGER_ARGUMENTS names 'missing.key', which no catalog has",
                "NON_COUNT_INTEGER_ARGUMENTS exempts 'tasks.count' argument 1, which is not an "
                "integer argument without plural forms",
            ],
        )

    def test_a_translation_varies_every_count_the_source_varies(self) -> None:
        value = self._plural_entry({"en": {"one": "%lld task", "other": "%lld tasks"}})
        # Spanish selects `one` and `other`; Chinese writes every count alike.
        value["localizations"]["es"] = string_unit("%lld tareas")
        value["localizations"]["zh-Hans"] = string_unit("%lld\u00a0项任务")

        self.assertEqual(
            catalog_entry_failures(
                catalog_with_strings({"tasks.count": value}), languages=("en", "es", "zh-Hans")
            ),
            [
                "tasks.count es does not vary argument 1 by plural; en does, and es has the "
                "plural categories ['one', 'other']"
            ],
        )

    def test_a_substitution_source_sets_the_arguments_every_translation_reads(self) -> None:
        value = entry("placeholder replaced below")
        value["localizations"]["en"] = substitution_localization(
            "%1$@: %#@count@",
            {"count": plural_substitution(2, {"one": "%arg task", "other": "%arg tasks"})},
        )
        value["localizations"]["es"] = self._plural_localization(
            {"one": "%1$@: %2$@ tarea", "other": "%1$@: %2$lld tareas"}
        )

        self.assertEqual(
            catalog_entry_failures(
                catalog_with_strings({"list.count": value}), languages=("en", "es")
            ),
            ["list.count es plural 'one' argument 2 type mismatch: '@'; expected 'lld'"],
        )

    def test_a_translation_may_vary_a_count_the_source_does_not(self) -> None:
        # Russian agrees the verb with the first number of "1 of 3"; English
        # leaves that number alone.
        value = entry("placeholder replaced below")
        value["localizations"]["en"] = substitution_localization(
            "%1$lld of %#@habits@ kept.",
            {"habits": plural_substitution(2, {"one": "%arg habit", "other": "%arg habits"})},
        )
        value["localizations"]["ru"] = substitution_localization(
            "%#@kept@ %#@habits@.",
            {
                "kept": plural_substitution(
                    1,
                    {
                        "one": "Выполнена %arg из",
                        "few": "Выполнены %arg из",
                        "many": "Выполнено %arg из",
                        "other": "Выполнено %arg из",
                    },
                ),
                "habits": plural_substitution(
                    2,
                    {
                        "one": "%arg привычки",
                        "few": "%arg привычек",
                        "many": "%arg привычек",
                        "other": "%arg привычки",
                    },
                ),
            },
        )

        with mock.patch.dict(
            verify_localization_catalog.NON_COUNT_INTEGER_ARGUMENTS,
            {"review.habits_kept": {1: "the first number of an “N of M …” ratio"}},
            clear=True,
        ):
            failures = catalog_entry_failures(
                catalog_with_strings({"review.habits_kept": value}), languages=("en", "ru")
            )

        self.assertEqual(failures, [])

    def test_a_unit_word_beside_a_separate_number_leaves_the_number_out_everywhere(self) -> None:
        # The goal ring shows "30" large with the unit word under it; the number
        # only selects the word's form.
        def unit_word(forms: dict[str, str]) -> dict[str, object]:
            return substitution_localization("%#@unit@", {"unit": plural_substitution(1, forms)})

        value = entry("placeholder replaced below")
        value["localizations"] = {
            "en": unit_word({"one": "day", "other": "days"}),
            "es": unit_word({"one": "día", "other": "días"}),
            # Russian `one` also covers 21, yet the word may still stand alone.
            "ru": unit_word({"one": "день", "few": "дня", "many": "дней", "other": "дня"}),
            "zh-Hans": unit_word({"other": "天"}),
        }
        catalog = catalog_with_strings({"goal.unit": value})
        languages = ("en", "es", "ru", "zh-Hans")

        self.assertEqual(catalog_entry_failures(catalog, languages=languages), [])

        value["localizations"]["es"] = unit_word({"one": "%arg día", "other": "%arg días"})
        self.assertEqual(
            catalog_entry_failures(catalog, languages=languages),
            [
                "goal.unit es substitution 'unit' plural 'one' shows the number, but the "
                "source's forms for this argument leave it out",
                "goal.unit es substitution 'unit' plural 'other' shows the number, but the "
                "source's forms for this argument leave it out",
            ],
        )

    def test_discovered_language_set_drives_catalog_and_bundle_requirements(self) -> None:
        app = catalog_with_strings(
            {"today": entry(extra_localizations={"ar": "اليوم", "fr": "Aujourd’hui"})}
        )
        watch = catalog_with_strings(
            {"today": entry(extra_localizations={"ar": "اليوم", "fr": "Aujourd’hui"})}
        )
        languages = required_languages([app, watch])

        self.assertEqual(languages, ("ar", "en", "fr"))
        self.assertEqual(catalog_entry_failures(app, languages=languages), [])
        self.assertEqual(catalog_entry_failures(watch, languages=languages), [])

        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>ar</string>
    <string>en</string>
    <string>fr</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertEqual(plist_localization_failures(plist, languages), [])

    def test_locale_added_to_one_catalog_must_exist_in_every_catalog(self) -> None:
        app = catalog_with_strings(
            {"today": entry(extra_localizations={"ar": "اليوم", "fr": "Aujourd’hui"})}
        )
        watch = catalog_with_strings({"today": entry(extra_localizations={"ar": "اليوم"})})
        languages = required_languages([app, watch])

        self.assertEqual(languages, ("ar", "en", "fr"))
        self.assertEqual(catalog_entry_failures(app, languages=languages), [])
        self.assertIn(
            "today missing non-empty fr stringUnit.value",
            catalog_entry_failures(watch, languages=languages),
        )

    def test_plist_localization_failures_require_discovered_languages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>ar</string>
    <string>en</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertEqual(plist_localization_failures(plist, ("ar", "en")), [])
            self.assertEqual(
                plist_localization_failures(plist, ("ar", "en", "fr")),
                [f"{plist} CFBundleLocalizations mismatch: ('ar', 'en'); expected ('ar', 'en', 'fr')"],
            )

    def test_plist_localization_failures_require_source_language_development_region(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>fr</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>fr</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertEqual(
                plist_localization_failures(plist, ("en", "fr")),
                [f"{plist} CFBundleDevelopmentRegion mismatch: 'fr'; expected 'en'"],
            )

    def test_plist_localization_failures_accept_declared_non_english_source_language(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>fr</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>fr</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertEqual(plist_localization_failures(plist, ("en", "fr"), "fr"), [])

    def test_sync_plist_localizations_writes_discovered_languages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>de</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>de</string>
    <string>en</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertTrue(sync_plist_localizations(plist, ("ar", "de", "en", "fr", "ja")))
            self.assertEqual(
                plist_localization_failures(plist, ("ar", "de", "en", "fr", "ja")),
                [],
            )
            self.assertFalse(sync_plist_localizations(plist, ("ar", "de", "en", "fr", "ja")))

    def test_sync_plist_localizations_writes_declared_source_language(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertTrue(sync_plist_localizations(plist, ("en", "fr"), "fr"))
            self.assertEqual(plist_localization_failures(plist, ("en", "fr"), "fr"), [])

    def test_sync_plist_localizations_preserves_xcode_development_language(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>$(DEVELOPMENT_LANGUAGE)</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
  </array>
</dict>
</plist>
""",
                encoding="utf-8",
            )

            self.assertTrue(sync_plist_localizations(plist, ("en", "fr")))
            text = plist.read_text(encoding="utf-8")
            self.assertIn("<string>$(DEVELOPMENT_LANGUAGE)</string>", text)
            self.assertEqual(plist_localization_failures(plist, ("en", "fr")), [])

    def test_sync_plist_localizations_keeps_comments_and_layout(self) -> None:
        original = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
  Why this bundle declares what it declares.
-->
<plist version="1.0">
<dict>
\t<key>CFBundleIdentifier</key>
\t<string>com.example.app</string>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>en</string>
\t<key>CFBundleLocalizations</key>
\t<array>
\t\t<string>en</string>
\t\t<string>zh-Hans</string>
\t</array>
\t<!-- A note on the next key. -->
\t<key>CFBundleName</key>
\t<string>App</string>
</dict>
</plist>
"""
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(original, encoding="utf-8")

            self.assertTrue(sync_plist_localizations(plist, ("en", "es", "zh-Hans")))
            self.assertEqual(
                plist.read_text(encoding="utf-8"),
                original.replace(
                    "\t\t<string>en</string>\n",
                    "\t\t<string>en</string>\n\t\t<string>es</string>\n",
                ),
            )

    def test_sync_plist_localizations_adds_a_missing_array_after_the_development_region(
        self,
    ) -> None:
        original = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>en</string>
\t<key>CFBundleName</key>
\t<string>App</string>
</dict>
</plist>
"""
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(original, encoding="utf-8")

            self.assertTrue(sync_plist_localizations(plist, ("en", "es")))
            self.assertEqual(
                plist.read_text(encoding="utf-8"),
                original.replace(
                    "\t<string>en</string>\n",
                    "\t<string>en</string>\n\t<key>CFBundleLocalizations</key>\n"
                    "\t<array>\n\t\t<string>en</string>\n\t\t<string>es</string>\n\t</array>\n",
                ),
            )

    def test_sync_plist_localizations_writes_nothing_when_the_edit_misses(self) -> None:
        # A nested dict names the key first, so a text edit would land there;
        # parsing the edit back catches it before anything is written.
        original = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>Nested</key>
\t<dict>
\t\t<key>CFBundleLocalizations</key>
\t\t<array>
\t\t\t<string>en</string>
\t\t</array>
\t</dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>en</string>
\t<key>CFBundleLocalizations</key>
\t<array>
\t\t<string>en</string>
\t</array>
</dict>
</plist>
"""
        with tempfile.TemporaryDirectory() as directory:
            plist = Path(directory) / "Info.plist"
            plist.write_text(original, encoding="utf-8")

            with self.assertRaises(ValueError):
                sync_plist_localizations(plist, ("en", "es"))
            self.assertEqual(plist.read_text(encoding="utf-8"), original)

    def test_shipping_bundle_plists_are_discovered_from_config_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "B-Info.plist").touch()
            (root / "A-Info.plist").touch()
            (root / "Ignored.plist").touch()

            self.assertEqual(
                shipping_bundle_plists(root),
                [root / "A-Info.plist", root / "B-Info.plist"],
            )

    def test_localized_info_plist_keys_include_permission_and_shortcut_titles(self) -> None:
        self.assertEqual(
            localized_info_plist_keys(
                {
                    "CFBundleDisplayName": "Lorvex",
                    "CFBundleName": "LorvexMobileApp",
                    "NSCalendarsFullAccessUsageDescription": "Read event details.",
                    "UIApplicationShortcutItems": [
                        {"UIApplicationShortcutItemTitle": "Quick Capture"},
                        {"UIApplicationShortcutItemSubtitle": "Ignored only if absent"},
                    ],
                }
            ),
            {
                "CFBundleDisplayName",
                "CFBundleName",
                "NSCalendarsFullAccessUsageDescription",
                "Quick Capture",
                "Ignored only if absent",
            },
        )

    def test_parse_info_plist_strings_reads_quoted_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            strings = Path(directory) / "InfoPlist.strings"
            strings.write_text(
                '"CFBundleDisplayName" = "Lorvex";\n'
                '"NSCalendarsFullAccessUsageDescription" = "Lire la disponibilité du calendrier";\n',
                encoding="utf-8",
            )

            entries, failures = parse_info_plist_strings(strings)

        self.assertEqual(failures, [])
        self.assertEqual(entries["CFBundleDisplayName"], "Lorvex")
        self.assertEqual(
            entries["NSCalendarsFullAccessUsageDescription"],
            "Lire la disponibilité du calendrier",
        )

    def test_catalog_entry_failures_preserves_integer_width_in_placeholder_signatures(self) -> None:
        failures = catalog_entry_failures(
            catalog_with_strings(
                {
                    "count": entry(
                        "%d items",
                        extra_localizations={"fr": "%lld éléments"},
                    )
                }
            ),
            languages=("en", "fr"),
        )

        self.assertIn(
            "count fr format placeholder mismatch: [(1, 'lld')]; expected [(1, 'd')]",
            failures,
        )

    def test_info_plist_strings_failures_require_every_discovered_language(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plist = root / "LorvexMobileApp-Info.plist"
            plist.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Lorvex</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Read event details.</string>
</dict>
</plist>
""",
                encoding="utf-8",
            )
            en = root / "InfoPlist" / "LorvexMobileApp" / "en.lproj"
            fr = root / "InfoPlist" / "LorvexMobileApp" / "fr.lproj"
            en.mkdir(parents=True)
            fr.mkdir(parents=True)
            en.joinpath("InfoPlist.strings").write_text(
                '"CFBundleDisplayName" = "Lorvex";\n'
                '"NSCalendarsFullAccessUsageDescription" = "Read event details.";\n',
                encoding="utf-8",
            )
            fr.joinpath("InfoPlist.strings").write_text(
                '"CFBundleDisplayName" = "Lorvex";\n',
                encoding="utf-8",
            )

            self.assertEqual(
                info_plist_strings_failures(plist, ("en", "fr"), root),
                [
                    f"{fr / 'InfoPlist.strings'} missing non-empty localization for "
                    "NSCalendarsFullAccessUsageDescription"
                ],
            )

    def test_generated_app_info_plist_values_resolve_metadata_variables(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "build_and_run.sh"
            script.write_text(
                'echo staging\n'
                'cat >"$INFO_PLIST" <<PLIST\n'
                "<dict>\n"
                "  <key>CFBundleName</key>\n"
                "  <string>$APP_DISPLAY_NAME</string>\n"
                "  <key>CFBundleVersion</key>\n"
                "  <string>$BUILD_VERSION</string>\n"
                "  <key>NSCalendarsFullAccessUsageDescription</key>\n"
                "  <string>${READ_TEXT}</string>\n"
                "</dict>\n"
                "PLIST\n",
                encoding="utf-8",
            )
            values, failures = generated_app_info_plist_values(
                script, {"APP_DISPLAY_NAME": "Lorvex", "BUILD_VERSION": "7", "READ_TEXT": "Read events."})

        self.assertEqual(failures, [])
        self.assertEqual(
            values,
            {"CFBundleName": "Lorvex", "NSCalendarsFullAccessUsageDescription": "Read events."},
        )

    def test_generated_app_info_plist_values_reject_unknown_metadata_and_missing_heredoc(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "build_and_run.sh"
            script.write_text(
                'cat >"$INFO_PLIST" <<PLIST\n'
                "  <key>CFBundleName</key>\n  <string>$MISSING_NAME</string>\n"
                "PLIST\n",
                encoding="utf-8",
            )
            values, failures = generated_app_info_plist_values(script, {})
            self.assertEqual(values, {})
            self.assertTrue(any("unknown metadata ['MISSING_NAME']" in f for f in failures))

            script.write_text("echo no plist here\n", encoding="utf-8")
            values, failures = generated_app_info_plist_values(script, {})
            self.assertEqual(values, {})
            self.assertTrue(any("has no Info.plist heredoc" in f for f in failures))

    def test_generated_info_plist_strings_failures_check_every_language_and_the_english_text(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "build_and_run.sh"
            script.write_text(
                'cat >"$INFO_PLIST" <<PLIST\n'
                "  <key>NSCalendarsFullAccessUsageDescription</key>\n"
                "  <string>$READ_TEXT</string>\n"
                "PLIST\n",
                encoding="utf-8",
            )
            en = root / "InfoPlist" / "LorvexApple" / "en.lproj"
            fr = root / "InfoPlist" / "LorvexApple" / "fr.lproj"
            en.mkdir(parents=True)
            fr.mkdir(parents=True)
            en.joinpath("InfoPlist.strings").write_text(
                '"NSCalendarsFullAccessUsageDescription" = "Reads events.";\n', encoding="utf-8")
            fr.joinpath("InfoPlist.strings").write_text('"CFBundleName" = "Lorvex";\n', encoding="utf-8")

            failures = generated_info_plist_strings_failures(
                ("en", "fr"), "en", script_path=script, config_root=root,
                metadata={"READ_TEXT": "Read events."})

        self.assertEqual(
            failures,
            [
                f"{en / 'InfoPlist.strings'} NSCalendarsFullAccessUsageDescription differs from "
                "the Info.plist text: 'Reads events.'; expected 'Read events.'",
                f"{fr / 'InfoPlist.strings'} missing non-empty localization for "
                "NSCalendarsFullAccessUsageDescription",
            ],
        )

    def test_info_plist_strings_failures_resolve_product_name_and_reject_unshipped_language(self) -> None:
        import plistlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plist = root / "LorvexWatchApp-Info.plist"
            plist.write_bytes(plistlib.dumps({
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundleDisplayName": "$(LORVEX_DISPLAY_NAME)",
            }))
            target = root / "InfoPlist" / "LorvexWatchApp"
            for language, name in [("en", "LorvexWatchApp"), ("de", "LorvexWatchApp"), ("fr", "x")]:
                (target / f"{language}.lproj").mkdir(parents=True)
                (target / f"{language}.lproj" / "InfoPlist.strings").write_text(
                    f'"CFBundleName" = "{name}";\n"CFBundleDisplayName" = "Lorvex";\n',
                    encoding="utf-8",
                )

            # The display name is a build setting only the build resolves, so
            # its English text is not compared; fr is not a shipped language.
            self.assertEqual(
                info_plist_strings_failures(plist, ("de", "en"), root),
                [f"{target / 'fr.lproj'} is not a shipped language"],
            )

            (target / "en.lproj" / "InfoPlist.strings").write_text(
                '"CFBundleName" = "Watch";\n"CFBundleDisplayName" = "Lorvex";\n', encoding="utf-8")
            self.assertIn(
                f"{target / 'en.lproj' / 'InfoPlist.strings'} CFBundleName differs from the "
                "Info.plist text: 'Watch'; expected 'LorvexWatchApp'",
                info_plist_strings_failures(plist, ("de", "en", "fr"), root),
            )

    def test_orphan_info_plist_target_failures_flag_a_directory_no_bundle_stages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "InfoPlist" / "LorvexApple").mkdir(parents=True)
            (root / "InfoPlist" / "LorvexMobileApp").mkdir(parents=True)
            (root / "InfoPlist" / "RetiredTarget").mkdir(parents=True)

            self.assertEqual(
                orphan_info_plist_target_failures(root),
                [f"{root / 'InfoPlist' / 'RetiredTarget'} belongs to no shipping bundle"],
            )

    def test_referenced_app_keys_scans_native_bundle_qualified_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                'String(localized: "sidebar.list_scope.open_count", '
                'defaultValue: "\\(count) open tasks", table: "Localizable", '
                'bundle: LorvexL10n.bundle)\n'
                'Text("sidebar.item.today", bundle: LorvexL10n.bundle)\n'
                'LocalizedStringResource("app.command.refresh", '
                'defaultValue: "Refresh", table: "Localizable", '
                'bundle: LorvexL10n.bundle)',
                encoding="utf-8",
            )

            self.assertEqual(
                referenced_app_keys([root]),
                {
                    "app.command.refresh",
                    "sidebar.list_scope.open_count",
                    "sidebar.item.today",
                },
            )

    def test_localized_string_resource_bundle_keys_maps_tokens_to_keys(self) -> None:
        # The App-Intent form: a raw LocalizedStringResource with a trailing
        # bundle: token, including an interpolated defaultValue whose `\\(…)`
        # must not break argument-boundary scanning.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Intent.swift").write_text(
                "\n".join(
                    [
                        'static let title = LocalizedStringResource(',
                        '  "system.task.complete.title", defaultValue: "Complete",',
                        '  table: "Localizable", bundle: SystemL10n.bundle)',
                        'IntentDialog(LocalizedStringResource(',
                        '  "system.task.capture.dialog", defaultValue: "Captured \\(title).",',
                        '  table: "Localizable", bundle: SystemL10n.bundle))',
                        'LocalizedStringResource("widget.intent.parameter.task",',
                        '  defaultValue: "Task", table: "Localizable", bundle: WidgetSupportL10n.bundle)',
                        # stringLiteral form carries no literal key nor bundle token.
                        'LocalizedStringResource(stringLiteral: title)',
                    ]
                ),
                encoding="utf-8",
            )

            by_token = localized_string_resource_bundle_keys([root])
            self.assertEqual(
                by_token.get("SystemL10n.bundle"),
                {"system.task.complete.title", "system.task.capture.dialog"},
            )
            self.assertEqual(
                by_token.get("WidgetSupportL10n.bundle"), {"widget.intent.parameter.task"}
            )

    def test_native_localized_string_bundle_keys_maps_interpolated_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Widget.swift").write_text(
                "\n".join(
                    [
                        'String(localized: "widget.progress.a11y",',
                        '  defaultValue: "\\(completed) of \\(total) tasks completed",',
                        '  table: "Localizable", bundle: WidgetL10n.bundle)',
                        'String(localized: dynamicKey, defaultValue: "Ignored",',
                        '  table: "Localizable", bundle: WidgetL10n.bundle)',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                native_localized_string_bundle_keys([root]).get("WidgetL10n.bundle"),
                {"widget.progress.a11y"},
            )

    def test_referenced_module_keys_includes_native_bundle_qualified_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Widget.swift").write_text(
                'String(localized: "widget.remaining", '
                'defaultValue: "\\(remaining) remaining", table: "Localizable", '
                'bundle: WidgetL10n.bundle)',
                encoding="utf-8",
            )

            self.assertEqual(
                referenced_module_keys("WidgetL10n", [root]), {"widget.remaining"}
            )

    def test_watch_native_reference_ownership_covers_string_text_and_resource(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "WatchView.swift").write_text(
                "\n".join(
                    [
                        'String(localized: "watch.status.live", '
                        'defaultValue: "Live from Lorvex", table: "Localizable", '
                        'bundle: WatchL10n.bundle)',
                        'Text("watch.section.current", bundle: WatchL10n.bundle)',
                        'LocalizedStringResource("watch.complication.name", '
                        'defaultValue: "Lorvex Focus", table: "Localizable", '
                        'bundle: WatchL10n.bundle)',
                        'Text("widget.title.today", bundle: WidgetL10n.bundle)',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                module_owned_reference_keys("WatchL10n", [root]),
                {
                    "watch.complication.name",
                    "watch.section.current",
                    "watch.status.live",
                },
            )

    def test_watch_native_widget_support_key_is_found_and_missing_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            watch_root = Path(directory)
            (watch_root / "LorvexWatchComplicationView.swift").write_text(
                'String(localized: "widget.task.priority.p1", '
                'defaultValue: "Priority 1", table: "Localizable", '
                'bundle: WidgetSupportL10n.bundle)',
                encoding="utf-8",
            )
            present = catalog_with_strings(
                {"widget.task.priority.p1": entry(value="Priority 1")}
            )

            self.assertEqual(
                referenced_module_keys("WidgetSupportL10n", [watch_root]),
                {"widget.task.priority.p1"},
            )
            self.assertEqual(
                module_reference_failures(
                    "WidgetSupportL10n", present, [watch_root]
                ),
                [],
            )
            self.assertEqual(
                module_reference_failures(
                    "WidgetSupportL10n", catalog_with_strings({}), [watch_root]
                ),
                [
                    "WidgetSupportL10n references key(s) missing from its catalog: "
                    "['widget.task.priority.p1']"
                ],
            )

    def test_native_text_bundle_keys_map_only_literal_bundle_owned_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                "\n".join(
                    [
                        'Text("widget.title.today", bundle: WidgetL10n.bundle)',
                        'Text("widget.subtitle", tableName: "Localizable",',
                        '  bundle: WidgetL10n.bundle, comment: "Subtitle")',
                        'Text(verbatim: "Not a key")',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                native_localized_text_bundle_keys([root]).get("WidgetL10n.bundle"),
                {"widget.title.today", "widget.subtitle"},
            )
            self.assertEqual(
                referenced_module_keys("WidgetL10n", [root]),
                {"widget.title.today", "widget.subtitle"},
            )

    def test_dead_key_scan_counts_only_resources_owned_by_the_catalog_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Intent.swift").write_text(
                'LocalizedStringResource("shared.name", defaultValue: "Shared", '
                'table: "Localizable", bundle: SystemL10n.bundle)',
                encoding="utf-8",
            )
            catalog = catalog_with_strings({"shared.name": entry(value="Shared")})

            self.assertEqual(
                unreferenced_module_key_failures("SystemL10n", catalog, [root]), []
            )
            self.assertEqual(
                unreferenced_module_key_failures("WidgetL10n", catalog, [root]),
                [
                    "WidgetL10n catalog has unreferenced key(s) (not used via a "
                    "native lookup or bundle-owned resource): ['shared.name']"
                ],
            )

    def test_widget_l10n_resource_ownership_requires_direct_bundle_token(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(
                MODULE_RESOURCE_BUNDLE_TOKENS["WidgetL10n"],
                {"WidgetL10n.bundle"},
            )
            self.assertEqual(
                module_reference_presence_failures("WidgetL10n", [root]),
                [
                    "WidgetL10n reference scan returned zero keys; update the "
                    "native/resource scanner before accepting this catalog"
                ],
            )
            (root / "Intent.swift").write_text(
                'LocalizedStringResource("widget.config.legacy", defaultValue: "Legacy", '
                'table: "Localizable", bundle: WidgetConfigL10n.viewsBundle)',
                encoding="utf-8",
            )
            self.assertEqual(
                module_reference_presence_failures("WidgetL10n", [root]),
                [
                    "WidgetL10n reference scan returned zero keys; update the "
                    "native/resource scanner before accepting this catalog"
                ],
            )
            (root / "Intent.swift").write_text(
                'LocalizedStringResource("widget.config.title", defaultValue: "Widget", '
                'table: "Localizable", bundle: WidgetL10n.bundle)\n'
                'Text("widget.config.subtitle", bundle: WidgetL10n.bundle)',
                encoding="utf-8",
            )
            self.assertEqual(module_reference_presence_failures("WidgetL10n", [root]), [])
            self.assertEqual(
                module_resource_reference_failures(
                    "WidgetL10n",
                    catalog_with_strings(
                        {"widget.config.subtitle": entry(value="Subtitle")}
                    ),
                    [root],
                ),
                [
                    "WidgetL10n references LocalizedStringResource key(s) missing "
                    "from its catalog: ['widget.config.title']"
                ],
            )
            self.assertEqual(
                module_reference_failures(
                    "WidgetL10n",
                    catalog_with_strings(
                        {"widget.config.title": entry(value="Widget")}
                    ),
                    [root],
                ),
                [
                    "WidgetL10n references key(s) missing from its catalog: "
                    "['widget.config.subtitle']"
                ],
            )

    def test_module_resource_reference_failures_flags_missing_bundle_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Intent.swift").write_text(
                'LocalizedStringResource("system.present.title", defaultValue: "P", '
                'table: "Localizable", bundle: SystemL10n.bundle)\n'
                'LocalizedStringResource("system.absent.title", defaultValue: "A", '
                'table: "Localizable", bundle: SystemL10n.bundle)\n',
                encoding="utf-8",
            )
            catalog = catalog_with_strings({"system.present.title": entry(value="P")})

            self.assertEqual(
                module_resource_reference_failures("SystemL10n", catalog, [root]),
                [
                    "SystemL10n references LocalizedStringResource key(s) missing from "
                    "its catalog: ['system.absent.title']"
                ],
            )
            # A helper with no bundle-token mapping never reports a failure.
            self.assertEqual(
                module_resource_reference_failures("MobileL10n", catalog, [root]), []
            )

    def test_system_intent_bundle_qualification_requires_exact_table_and_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Intent.swift"
            source.write_text(
                "\n".join(
                    [
                        'LocalizedStringResource("system.valid.title", defaultValue: "Valid", table: "Localizable", bundle: SystemL10n.bundle)',
                        'LocalizedStringResource("system.missing.title", defaultValue: "Missing")',
                        'String(localized: "system.wrong.title", defaultValue: "Wrong", table: "Other", bundle: MobileL10n.bundle)',
                        'LocalizedStringResource(stringLiteral: raw)',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                system_intent_bundle_qualification_failures([root]),
                [
                    f"{source}:2 system localization key 'system.missing.title' must use table: \"Localizable\"; found None",
                    f"{source}:2 system localization key 'system.missing.title' must use bundle: SystemL10n.bundle; found None",
                    f"{source}:3 system localization key 'system.wrong.title' must use table: \"Localizable\"; found 'Other'",
                    f"{source}:3 system localization key 'system.wrong.title' must use bundle: SystemL10n.bundle; found 'MobileL10n.bundle'",
                ],
            )

    def test_mobile_bundle_qualification_requires_exact_table_and_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "MobileView.swift"
            source.write_text(
                "\n".join(
                    [
                        'String(localized: "mobile.valid", defaultValue: "Valid", table: "Localizable", bundle: MobileL10n.bundle)',
                        'LocalizedStringResource("mobile.missing", defaultValue: "Missing")',
                        'String(localized: "mobile.wrong", defaultValue: "Wrong", table: "Other", bundle: SystemL10n.bundle)',
                        'Text("mobile.text.valid", bundle: MobileL10n.bundle)',
                        'Text("mobile.text.missing")',
                        'Text("•")',
                        'Text(verbatim: runtimeValue)',
                        'String(localized: "mobile.multiline", defaultValue: """\nLong value.\n""", table: "Localizable", bundle: MobileL10n.bundle)',
                    ]
                ),
                encoding="utf-8",
            )
            catalog = catalog_with_strings(
                {
                    "mobile.valid": entry("Valid"),
                    "mobile.missing": entry("Missing"),
                    "mobile.wrong": entry("Wrong"),
                    "mobile.text.valid": entry("Valid text"),
                    "mobile.text.missing": entry("Missing text"),
                    "mobile.multiline": entry("Long value."),
                }
            )

            self.assertEqual(
                mobile_native_bundle_qualification_failures(catalog, [root]),
                [
                    f"{source}:2 Mobile localization key 'mobile.missing' must use table: \"Localizable\"; found None",
                    f"{source}:2 Mobile localization key 'mobile.missing' must use bundle: MobileL10n.bundle; found None",
                    f"{source}:3 Mobile localization key 'mobile.wrong' must use table: \"Localizable\"; found 'Other'",
                    f"{source}:3 Mobile localization key 'mobile.wrong' must use bundle: MobileL10n.bundle; found 'SystemL10n.bundle'",
                    f"{source}:5 Mobile Text key 'mobile.text.missing' must use bundle: MobileL10n.bundle; found None",
                ],
            )

    def test_apple_bundle_qualification_requires_exact_table_and_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "AppleView.swift"
            source.write_text(
                "\n".join(
                    [
                        'String(localized: "apple.valid", defaultValue: "Valid", table: "Localizable", bundle: LorvexL10n.bundle)',
                        'LocalizedStringResource("apple.missing", defaultValue: "Missing")',
                        'String(localized: "apple.wrong", defaultValue: "Wrong", table: "Other", bundle: MobileL10n.bundle)',
                        'Text("apple.text.valid", bundle: LorvexL10n.bundle)',
                        'Text("apple.text.missing")',
                        'Text("•")',
                        'Text(verbatim: runtimeValue)',
                    ]
                ),
                encoding="utf-8",
            )
            catalog = catalog_with_strings(
                {
                    "apple.valid": entry("Valid"),
                    "apple.missing": entry("Missing"),
                    "apple.wrong": entry("Wrong"),
                    "apple.text.valid": entry("Valid text"),
                    "apple.text.missing": entry("Missing text"),
                }
            )

            self.assertEqual(
                apple_native_bundle_qualification_failures(catalog, [root]),
                [
                    f"{source}:2 Apple localization key 'apple.missing' must use table: \"Localizable\"; found None",
                    f"{source}:2 Apple localization key 'apple.missing' must use bundle: LorvexL10n.bundle; found None",
                    f"{source}:3 Apple localization key 'apple.wrong' must use table: \"Localizable\"; found 'Other'",
                    f"{source}:3 Apple localization key 'apple.wrong' must use bundle: LorvexL10n.bundle; found 'MobileL10n.bundle'",
                    f"{source}:5 Apple Text key 'apple.text.missing' must use bundle: LorvexL10n.bundle; found None",
                ],
            )

    def test_bare_localization_text_failure_catches_unknown_key_but_ignores_comments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "View.swift"
            source.write_text(
                '\n'.join(
                    [
                        '// Text("commented.typo")',
                        'Text("settings.real_typo")',
                        'Text("Human-facing sentence")',
                        'Text("settings.valid", bundle: MobileL10n.bundle)',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                bare_localization_text_failures([root]),
                [
                    f"{source}:2 localization-shaped Text key 'settings.real_typo' "
                    "must use an explicit owning bundle"
                ],
            )

    def test_implicit_localized_string_resource_failure_ignores_comments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Metadata.swift"
            source.write_text(
                '\n'.join(
                    [
                        '// let ignored: LocalizedStringResource = "ignored.key"',
                        'let bad: LocalizedStringResource = "system.bad.title"',
                        'let good = LocalizedStringResource("system.good.title", table: "Localizable", bundle: SystemL10n.bundle)',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                implicit_localized_string_resource_failures([root]),
                [
                    f"{source}:2 implicit LocalizedStringResource literal must use "
                    "an explicit table and owning bundle"
                ],
            )

    def test_hardcoded_system_case_display_failures_rejects_case_literals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Options.swift"
            source.write_text(
                """
enum ExampleOption: String, AppEnum {
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .daily: "Daily",
    .weekly: DisplayRepresentation(title: "Weekly"),
    .localized: DisplayRepresentation(title: SystemL10n.resource("system.option.localized", "Localized")),
  ]
}
""",
                encoding="utf-8",
            )

            self.assertEqual(
                hardcoded_system_case_display_failures([root]),
                [
                    f"{source}:4 hardcoded AppEnum case display literal; use a bundle-qualified LocalizedStringResource",
                    f"{source}:5 hardcoded AppEnum DisplayRepresentation title; use a bundle-qualified LocalizedStringResource",
                ],
            )

    def test_hardcoded_system_intent_metadata_failures_rejects_user_visible_literals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "CompleteIntent.swift"
            source.write_text(
                """
struct CompleteIntent: AppIntent {
  static let title: LocalizedStringResource = "Complete Lorvex Task"
  static let description = IntentDescription("Complete a Lorvex task.")
  static let multilineDescription = IntentDescription(
    "Complete a Lorvex task from another system surface."
  )

  @Parameter(title: "Task")
  var task: LorvexTaskEntity
}
""",
                encoding="utf-8",
            )

            self.assertEqual(
                hardcoded_system_intent_metadata_failures([root]),
                [
                    f"{source}:3 hardcoded AppIntent title; use a bundle-qualified LocalizedStringResource",
                    f"{source}:4 hardcoded AppIntent description; use a bundle-qualified LocalizedStringResource",
                    f"{source}:6 hardcoded AppIntent description; use a bundle-qualified LocalizedStringResource",
                    f"{source}:9 hardcoded AppIntent parameter title; use a bundle-qualified LocalizedStringResource",
                ],
            )

    def test_source_reference_failures_rejects_missing_catalog_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                'String(localized: "missing.key", defaultValue: "Missing", '
                'table: "Localizable", bundle: LorvexL10n.bundle)',
                encoding="utf-8",
            )

            self.assertEqual(
                source_reference_failures(catalog_with_strings({}), [root]),
                ["source references localization key(s) missing from catalog: ['missing.key']"],
            )


    def test_parse_concat_string_decodes_multiline_concat_and_interpolation(self) -> None:
        multiline = 'x(key: "k", defaultValue: """\n      Hello \\\n      world.\n      """)'
        value, interp, _ = _parse_concat_string(
            multiline, multiline.index("defaultValue:") + len("defaultValue:")
        )
        self.assertEqual(value, "Hello world.")
        self.assertFalse(interp)

        concat = 'x(key: "k", defaultValue: "A " + "B.")'
        value, interp, _ = _parse_concat_string(
            concat, concat.index("defaultValue:") + len("defaultValue:")
        )
        self.assertEqual(value, "A B.")
        self.assertFalse(interp)

        interpolated = 'x(key: "k", defaultValue: "N=\\(n)")'
        _, interp, _ = _parse_concat_string(
            interpolated, interpolated.index("defaultValue:") + len("defaultValue:")
        )
        self.assertTrue(interp)

    def test_decoded_literals_mark_interpolations_and_computed_operands(self) -> None:
        def default_of(call: str) -> tuple[str, bool]:
            value, interp, _ = _parse_concat_string(
                call, call.index("defaultValue:") + len("defaultValue:")
            )
            return value, interp

        self.assertEqual(
            default_of('x(key: "k", defaultValue: "\\(done) of \\(total(in: list)) done")'),
            (f"{INTERPOLATION_MARK} of {INTERPOLATION_MARK} done", True),
        )
        self.assertEqual(
            default_of('x(key: "k", defaultValue: """\n      \\(count) left\n      """)'),
            (f"{INTERPOLATION_MARK} left", True),
        )
        self.assertEqual(
            default_of('x(key: "k", defaultValue: "Total: " + label)'),
            (f"Total: {NON_LITERAL_MARK}", True),
        )

    def test_default_value_equality_gate_flags_drift(self) -> None:
        app = catalog_with_strings({"settings.tab.general": entry("General")})

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                'String(localized: "settings.tab.general", defaultValue: "Drifted", '
                'table: "Localizable", bundle: LorvexL10n.bundle)',
                encoding="utf-8",
            )
            failures = default_value_equality_failures(app, [], source_roots=[root])

        self.assertEqual(len(failures), 1)
        self.assertIn("settings.tab.general", failures[0])
        self.assertIn("'Drifted'", failures[0])

    def test_default_value_equality_gate_routes_native_defaults_by_bundle(self) -> None:
        app = catalog_with_strings({})
        mobile = catalog_with_strings(
            {"mobile.title": entry("Mobile title")}
        )
        widget_support = catalog_with_strings(
            {"widget.support.title": entry("Support title")}
        )
        widget_views = catalog_with_strings(
            {"widget.config.title": entry("Widget title")}
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Widget.swift").write_text(
                'String(localized: "widget.support.title", '
                'defaultValue: "Drifted support title", table: "Localizable", '
                'bundle: WidgetSupportL10n.bundle)\n'
                'LocalizedStringResource("widget.config.title", '
                'defaultValue: "Drifted widget title", table: "Localizable", '
                'bundle: WidgetL10n.bundle)\n'
                # This deleted resolver token must not be assigned to WidgetL10n.
                'LocalizedStringResource("widget.config.legacy", '
                'defaultValue: "Ignored legacy alias", table: "Localizable", '
                'bundle: WidgetConfigL10n.viewsBundle)\n'
                # Text has no code default; its key existence is checked elsewhere.
                'Text("widget.config.subtitle", bundle: WidgetL10n.bundle)',
                encoding="utf-8",
            )
            (root / "Mobile.swift").write_text(
                'String(localized: "mobile.title", '
                'defaultValue: "Drifted mobile title", table: "Localizable", '
                'bundle: MobileL10n.bundle)',
                encoding="utf-8",
            )
            failures = default_value_equality_failures(
                app,
                [
                    ("MobileL10n", mobile, [root]),
                    ("WidgetSupportL10n", widget_support, [root]),
                    ("WidgetL10n", widget_views, [root]),
                ],
                source_roots=[root],
            )

        self.assertEqual(len(failures), 3)
        self.assertTrue(any("mobile.title" in failure for failure in failures))
        self.assertTrue(
            any("widget.support.title" in failure for failure in failures)
        )
        self.assertTrue(
            any("widget.config.title" in failure for failure in failures)
        )
        self.assertFalse(any("widget.config.legacy" in failure for failure in failures))
        self.assertFalse(any("widget.config.subtitle" in failure for failure in failures))

    def test_default_value_equality_gate_compares_interpolated_defaults(self) -> None:
        app = catalog_with_strings(
            {
                "tasks.count": self._plural_entry({"en": {"one": "%lld task", "other": "%lld tasks"}}),
                "list.count": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": substitution_localization(
                            "%1$@: %#@count@",
                            {"count": plural_substitution(2, {"one": "%arg task", "other": "%arg tasks"})},
                        )
                    },
                },
                "goal.unit": {
                    "extractionState": "manual",
                    "localizations": {
                        "en": substitution_localization(
                            "%#@unit@", {"unit": plural_substitution(1, {"one": "day", "other": "days"})}
                        )
                    },
                },
                "tasks.share": entry("%@ (100%%)"),
                "tasks.label": entry("Total: %@"),
            }
        )
        # Each entry shape is called once with its catalog text and once drifted.
        calls = (
            ("tasks.count", '"\\(count) tasks"'),
            ("tasks.count", '"\\(count) items"'),
            ("list.count", '"\\(list): \\(count) tasks"'),
            ("list.count", '"\\(list): \\(count) items"'),
            ("tasks.share", '"\\(label) (100%)"'),
            ("tasks.share", '"\\(label) (50%)"'),
            # The ring shows the number apart; the catalog's forms leave it out.
            ("goal.unit", '"\\(value) days"'),
            # A computed operand makes the text unknown, so it is not compared.
            ("tasks.label", '"Total " + label'),
        )
        source = "\n".join(
            f'String(localized: "{key}", defaultValue: {default}, table: "Localizable", '
            "bundle: LorvexL10n.bundle)"
            for key, default in calls
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(source, encoding="utf-8")
            failures = default_value_equality_failures(app, [], source_roots=[root])

        drifts = [failure.split(" for ", 1)[1] for failure in failures]
        self.assertEqual(
            drifts,
            [
                "'tasks.count' (each placeholder and interpolation shown as \u25c6): "
                "catalog='\u25c6 tasks' default='\u25c6 items'",
                "'list.count' (each placeholder and interpolation shown as \u25c6): "
                "catalog='\u25c6: \u25c6 tasks' default='\u25c6: \u25c6 items'",
                "'tasks.share' (each placeholder and interpolation shown as \u25c6): "
                "catalog='\u25c6 (100%)' default='\u25c6 (50%)'",
            ],
        )

    def test_default_value_equality_gate_passes_on_shipped_catalogs(self) -> None:
        app, app_failures = load_catalog(CATALOG_PATH)
        self.assertEqual(app_failures, [])
        modules: list[tuple[str, dict[str, object], list[Path]]] = []
        for helper, catalog_path, roots in MODULE_CATALOGS:
            catalog, failures = load_catalog(catalog_path)
            self.assertEqual(failures, [])
            modules.append((helper, catalog, roots))
        self.assertEqual(default_value_equality_failures(app, modules), [])


if __name__ == "__main__":
    unittest.main()
