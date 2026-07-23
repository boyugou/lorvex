#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import re

from verify_localization_catalog import (
    CATALOG_PATH,
    MODULE_CATALOGS,
    MODULE_RESOURCE_BUNDLE_TOKENS,
    ROOT,
    _call_site_defaults,
    _parse_concat_string,
    apple_native_bundle_qualification_failures,
    bare_localization_text_failures,
    default_value_equality_failures,
    load_catalog,
    catalog_entry_failures,
    catalog_languages,
    catalog_source_language,
    catalog_structure_failures,
    copied_source_translation_failures,
    hardcoded_system_case_display_failures,
    hardcoded_system_intent_metadata_failures,
    info_plist_strings_failures,
    implicit_localized_string_resource_failures,
    localized_info_plist_keys,
    native_localized_string_bundle_keys,
    native_localized_text_bundle_keys,
    parse_info_plist_strings,
    referenced_module_keys,
    localized_string_resource_bundle_keys,
    mobile_native_bundle_qualification_failures,
    module_owned_reference_keys,
    module_resource_reference_failures,
    module_reference_failures,
    module_reference_presence_failures,
    plain_helper_plural_reference_failures,
    plist_localization_failures,
    referenced_app_keys,
    required_languages,
    required_source_language,
    shipping_bundle_plists,
    source_reference_failures,
    swift_source_without_comments,
    system_intent_bundle_qualification_failures,
    sync_plist_localizations,
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

    def test_catalog_entry_failures_understands_locale_specific_plural_substitutions(self) -> None:
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
        value = entry(
            "%1$lld tasks, %1$lld total",
            extra_localizations={"es": "placeholder replaced below"},
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
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%arg",
                                }
                            }
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

    def test_referenced_module_keys_scans_localized_string_resource_literals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Intent.swift"
            source.write_text(
                "\n".join(
                    [
                        'LocalizedStringResource(stringLiteral: WidgetL10n.string("widget.list.parameter.title", "List"))',
                        'SystemL10n.resource("system.entity.task.type", "Lorvex Task")',
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                referenced_module_keys("WidgetL10n", [root]), {"widget.list.parameter.title"}
            )
            self.assertEqual(
                referenced_module_keys("SystemL10n", [root]), {"system.entity.task.type"}
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
                        'LocalizedStringResource(stringLiteral: SystemL10n.string("x", "y"))',
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
                    "helper/native lookup or bundle-owned resource): ['shared.name']"
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
                    "helper/native/resource scanner before accepting this catalog"
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
                    "helper/native/resource scanner before accepting this catalog"
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

    def test_plural_catalog_keys_cannot_use_eager_plain_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                'String(format: WidgetL10n.string("widget.remaining", "%lld remaining"), count)',
                encoding="utf-8",
            )
            catalog = catalog_with_strings(
                {
                    "widget.remaining": {
                        "extractionState": "manual",
                        "localizations": {
                            "en": {
                                "variations": {
                                    "plural": {
                                        "one": {"stringUnit": {"state": "translated", "value": "%lld remaining"}},
                                        "other": {"stringUnit": {"state": "translated", "value": "%lld remaining"}},
                                    }
                                }
                            }
                        },
                    }
                }
            )

            self.assertEqual(
                plain_helper_plural_reference_failures("WidgetL10n", catalog, [root]),
                [
                    "WidgetL10n routes plural catalog key(s) through an eager plain "
                    "helper; use native integer interpolation: ['widget.remaining']"
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

        concat = 'MobileL10n.text("k", "A " + "B.")'
        value, interp, _ = _parse_concat_string(concat, concat.index(",") + 1)
        self.assertEqual(value, "A B.")
        self.assertFalse(interp)

        interpolated = 'x(key: "k", defaultValue: "N=\\(n)")'
        _, interp, _ = _parse_concat_string(
            interpolated, interpolated.index("defaultValue:") + len("defaultValue:")
        )
        self.assertTrue(interp)

    def test_call_site_defaults_extracts_key_and_decoded_default(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "View.swift").write_text(
                'MobileL10n.text("settings.tab.general", "General")',
                encoding="utf-8",
            )
            sites = _call_site_defaults(root, re.compile(r"MobileL10n\.text\s*\("), "")
            self.assertEqual(
                [(key, default) for key, default, _, _ in sites],
                [("settings.tab.general", "General")],
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
