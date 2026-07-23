#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from localization_expand import (
    DEFAULT_TARGET_LANGUAGES,
    apply_translation_pack,
    apply_info_plist_translations,
    build_tauri_index,
    emit_translation_pack,
    emit_info_plist_gaps,
    main,
    parse_languages,
    parse_strings_file,
    tauri_locales,
    validate_english_translations,
    validate_info_plist_translations,
)


class LocalizationExpandTests(unittest.TestCase):
    def test_default_languages_match_remaining_non_rtl_expansion_set(self) -> None:
        expected = ["hi", "id", "vi", "uk", "nl", "th", "ro", "ms", "bn", "el", "ta", "te", "mr", "ml"]

        self.assertEqual(DEFAULT_TARGET_LANGUAGES, expected)
        self.assertEqual(parse_languages(None), expected)
        self.assertEqual(parse_languages("hi, fr, ,te"), ["hi", "fr", "te"])

    def test_tauri_locales_uses_environment_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            locales = Path(directory)
            (locales / "en.json").write_text("{}", encoding="utf-8")

            with patch.dict(os.environ, {"LORVEX_TAURI_LOCALES": str(locales)}):
                self.assertEqual(tauri_locales(), locales)

    def test_build_tauri_index_reuses_unambiguous_exact_english_matches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            locales = Path(directory)
            (locales / "en.json").write_text(
                json.dumps(
                    {
                        "today": "Today",
                        "save": "Save",
                        "count": "%d tasks",
                    }
                ),
                encoding="utf-8",
            )
            (locales / "hi.json").write_text(
                json.dumps(
                    {
                        "today": "आज",
                        "save": "सहेजें",
                        "count": "%d कार्य",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"LORVEX_TAURI_LOCALES": str(locales)}):
                index = build_tauri_index(["hi"])

            self.assertEqual(index["Today"], {"hi": "आज"})
            self.assertEqual(index["Save"], {"hi": "सहेजें"})
            self.assertNotIn("%d tasks", index)

    def test_build_tauri_index_drops_context_dependent_conflicts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            locales = Path(directory)
            (locales / "en.json").write_text(
                json.dumps(
                    {
                        "verb": "Open",
                        "adjective": "Open",
                    }
                ),
                encoding="utf-8",
            )
            (locales / "hi.json").write_text(
                json.dumps(
                    {
                        "verb": "खोलें",
                        "adjective": "खुला",
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"LORVEX_TAURI_LOCALES": str(locales)}):
                index = build_tauri_index(["hi"])

            self.assertNotIn("Open", index)

    def test_info_plist_gaps_emit_missing_target_language_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "InfoPlist" / "LorvexMobileApp"
            en = target / "en.lproj"
            fr = target / "fr.lproj"
            en.mkdir(parents=True)
            fr.mkdir(parents=True)
            en.joinpath("InfoPlist.strings").write_text(
                '"CFBundleDisplayName" = "Lorvex";\n'
                '"Quick Capture" = "Quick Capture";\n',
                encoding="utf-8",
            )
            fr.joinpath("InfoPlist.strings").write_text(
                '"CFBundleDisplayName" = "Lorvex";\n',
                encoding="utf-8",
            )
            out = root / "gaps.json"

            counts = emit_info_plist_gaps(["fr"], out, config_root=root)
            payload = json.loads(out.read_text(encoding="utf-8"))

            self.assertEqual(counts["LorvexMobileApp"]["fr"], 1)
            self.assertEqual(
                payload["LorvexMobileApp"]["Quick Capture"],
                {"en": "Quick Capture", "missing": ["fr"]},
            )

    def test_apply_info_plist_translations_creates_language_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            translations = root / "translations.json"
            translations.write_text(
                json.dumps(
                    {
                        "LorvexMobileApp": {
                            "Quick Capture": {
                                "hi": "त्वरित कैप्चर",
                                "fr": "Capture rapide",
                            },
                            'Needs "quotes"': {
                                "hi": 'उद्धरण "चाहिए"',
                            },
                        }
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            applied = apply_info_plist_translations(translations, config_root=root)
            hi_path = root / "InfoPlist" / "LorvexMobileApp" / "hi.lproj" / "InfoPlist.strings"
            fr_path = root / "InfoPlist" / "LorvexMobileApp" / "fr.lproj" / "InfoPlist.strings"

            self.assertEqual(applied["LorvexMobileApp"], 3)
            self.assertEqual(
                parse_strings_file(hi_path),
                {
                    "Needs \"quotes\"": "उद्धरण \"चाहिए\"",
                    "Quick Capture": "त्वरित कैप्चर",
                },
            )
            self.assertEqual(parse_strings_file(fr_path), {"Quick Capture": "Capture rapide"})

    def test_translation_pack_combines_catalog_and_info_plist_gaps(self) -> None:
        catalog = {
            "strings": {
                "today.title": {
                    "localizations": {
                        "en": {"stringUnit": {"value": "Today"}},
                        "zh-Hans": {"stringUnit": {"value": "今天"}},
                    }
                },
                "done.title": {
                    "localizations": {
                        "en": {"stringUnit": {"value": "Done"}},
                        "fr": {"stringUnit": {"value": "Terminé"}},
                    }
                },
            }
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(json.dumps(catalog), encoding="utf-8")

            target = root / "Config" / "InfoPlist" / "LorvexMobileApp" / "en.lproj"
            target.mkdir(parents=True)
            target.joinpath("InfoPlist.strings").write_text(
                '"Quick Capture" = "Quick Capture";\n',
                encoding="utf-8",
            )
            out = root / "pack.json"

            with patch("localization_expand.ROOT", root), patch(
                "localization_expand.CONFIG_ROOT", root / "Config"
            ):
                counts = emit_translation_pack(["fr"], out, config_root=root / "Config")

            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(counts, {"catalogStrings": 1, "infoPlistTargets": 1, "infoPlistEntries": 1})
            self.assertEqual(payload["languages"], ["fr"])
            instructions = "\n".join(payload["instructions"])
            self.assertIn("add a translations object", instructions)
            self.assertIn("every listed language must be present", instructions)
            self.assertEqual(payload["catalogStrings"][0]["en"], "Today")
            self.assertEqual(payload["catalogStrings"][0]["zhHans"], "今天")
            self.assertEqual(
                payload["catalogStrings"][0]["occurrences"],
                [{"catalog": "Sources/LorvexMobile/Resources/Localizable.xcstrings", "key": "today.title"}],
            )
            self.assertEqual(
                payload["infoPlistStrings"]["LorvexMobileApp"]["Quick Capture"],
                {"en": "Quick Capture", "missing": ["fr"]},
            )

    def test_validate_english_translations_checks_languages_and_placeholders(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            valid = Path(directory) / "valid.json"
            valid.write_text(
                json.dumps({"%d selected": {"hi": "%d चयनित"}}),
                encoding="utf-8",
            )
            invalid = Path(directory) / "invalid.json"
            invalid.write_text(
                json.dumps(
                    {
                        "%d selected": {"hi": "चयनित", "fr": "%d sélectionnés"},
                        "%d wide": {"hi": "%lld विस्तृत"},
                        "Done": {"hi": ""},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(validate_english_translations(valid, ["hi"]), [])
            failures = validate_english_translations(invalid, ["hi"])
            self.assertIn(
                "'%d selected' hi format placeholder mismatch: []; expected ['d']",
                failures,
            )
            self.assertIn(
                "'%d wide' hi format placeholder mismatch: ['lld']; expected ['d']",
                failures,
            )
            self.assertIn("'%d selected' has unexpected language 'fr'; expected one of ['hi']", failures)
            self.assertIn("'Done' hi translation is empty", failures)

            missing = Path(directory) / "missing.json"
            missing.write_text(
                json.dumps([{"en": "Open", "langs": ["hi", "fr"], "translations": {"hi": "खोलें"}}]),
                encoding="utf-8",
            )
            self.assertIn(
                "'Open' is missing translations for ['fr']",
                validate_english_translations(missing, ["hi", "fr"]),
            )
            extra = Path(directory) / "extra.json"
            extra.write_text(
                json.dumps([{"en": "Done", "langs": ["hi"], "translations": {"hi": "पूर्ण", "fr": "Terminé"}}]),
                encoding="utf-8",
            )
            self.assertIn(
                "'Done' has translations for languages not listed by metadata: ['fr']",
                validate_english_translations(extra, ["hi", "fr"]),
            )

    def test_validate_info_plist_translations_checks_targets_and_placeholders(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            valid = Path(directory) / "valid.json"
            valid.write_text(
                json.dumps(
                    {"LorvexMobileApp": {"Quick Capture": {"hi": "त्वरित कैप्चर"}}},
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            invalid = Path(directory) / "invalid.json"
            invalid.write_text(
                json.dumps(
                    {
                        "UnknownTarget": {"Quick Capture": {"hi": "त्वरित कैप्चर"}},
                        "LorvexMobileApp": {
                            "%d items": {"hi": "आइटम"},
                            "Open": {"fr": "Ouvrir"},
                            "Done": {"hi": ""},
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(validate_info_plist_translations(valid, ["hi"]), [])
            failures = validate_info_plist_translations(invalid, ["hi"])
            self.assertIn("unknown InfoPlist target 'UnknownTarget'", failures)
            self.assertIn(
                "LorvexMobileApp '%d items' hi format placeholder mismatch: []; expected ['d']",
                failures,
            )
            self.assertIn("LorvexMobileApp 'Open' has unexpected language 'fr'; expected one of ['hi']", failures)
            self.assertIn("LorvexMobileApp 'Done' hi translation is empty", failures)

            missing = Path(directory) / "missing.json"
            missing.write_text(
                json.dumps(
                    {
                        "LorvexMobileApp": {
                            "Open": {
                                "en": "Open",
                                "missing": ["hi", "fr"],
                                "translations": {"hi": "खोलें"},
                            }
                        }
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            self.assertIn(
                "LorvexMobileApp 'Open' is missing translations for ['fr']",
                validate_info_plist_translations(missing, ["hi", "fr"]),
            )
            extra = Path(directory) / "extra.json"
            extra.write_text(
                json.dumps(
                    {
                        "LorvexMobileApp": {
                            "Done": {
                                "missing": ["hi"],
                                "translations": {"hi": "पूर्ण", "fr": "Terminé"},
                            }
                        }
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            self.assertIn(
                "LorvexMobileApp 'Done' has translations for languages not listed by metadata: ['fr']",
                validate_info_plist_translations(extra, ["hi", "fr"]),
            )

    def test_apply_translation_pack_validates_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "strings": {
                            "selected.count": {
                                "localizations": {
                                    "en": {"stringUnit": {"value": "%d selected"}},
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            target = root / "Config" / "InfoPlist" / "LorvexMobileApp" / "en.lproj"
            target.mkdir(parents=True)
            target.joinpath("InfoPlist.strings").write_text(
                '"Quick Capture" = "Quick Capture";\n',
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "catalogStrings": {"%d selected": {"hi": "चयनित"}},
                        "infoPlistStrings": {
                            "LorvexMobileApp": {"Quick Capture": {"hi": "त्वरित कैप्चर"}}
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch("localization_expand.ROOT", root):
                result = apply_translation_pack(pack_path, ["hi"], config_root=root / "Config")

            self.assertIn(
                "'%d selected' hi format placeholder mismatch: []; expected ['d']",
                result["failures"],
            )
            stored = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertNotIn("hi", stored["strings"]["selected.count"]["localizations"])
            hi_path = root / "Config" / "InfoPlist" / "LorvexMobileApp" / "hi.lproj" / "InfoPlist.strings"
            self.assertFalse(hi_path.exists())

    def test_apply_translation_pack_writes_catalog_and_info_plist(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "strings": {
                            "done.title": {
                                "localizations": {
                                    "en": {"stringUnit": {"value": "Done"}},
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            target = root / "Config" / "InfoPlist" / "LorvexMobileApp" / "en.lproj"
            target.mkdir(parents=True)
            target.joinpath("InfoPlist.strings").write_text(
                '"Quick Capture" = "Quick Capture";\n',
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "catalogStrings": [
                            {
                                "en": "Done",
                                "langs": ["hi"],
                                "translations": {"hi": "पूर्ण"},
                            }
                        ],
                        "infoPlistStrings": {
                            "LorvexMobileApp": {
                                "Quick Capture": {
                                    "en": "Quick Capture",
                                    "missing": ["hi"],
                                    "translations": {"hi": "त्वरित कैप्चर"},
                                }
                            }
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch("localization_expand.ROOT", root):
                result = apply_translation_pack(pack_path, ["hi"], config_root=root / "Config")

            self.assertEqual(result["failures"], [])
            self.assertEqual(result["catalog"], {"Sources/LorvexMobile/Resources/Localizable.xcstrings": 1})
            self.assertEqual(result["infoPlist"], {"LorvexMobileApp": 1})
            stored = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertEqual(
                stored["strings"]["done.title"]["localizations"]["hi"],
                {"stringUnit": {"state": "translated", "value": "पूर्ण"}},
            )
            hi_path = root / "Config" / "InfoPlist" / "LorvexMobileApp" / "hi.lproj" / "InfoPlist.strings"
            self.assertEqual(parse_strings_file(hi_path), {"Quick Capture": "त्वरित कैप्चर"})

    def test_apply_pack_cli_infers_languages_from_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "strings": {
                            "done.title": {
                                "localizations": {
                                    "en": {"stringUnit": {"value": "Done"}},
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogStrings": [
                            {
                                "en": "Done",
                                "langs": ["hi"],
                                "translations": {"hi": "पूर्ण"},
                            }
                        ],
                        "infoPlistStrings": {},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch("localization_expand.ROOT", root):
                with redirect_stdout(StringIO()):
                    self.assertEqual(main(["apply-pack", "--in", str(pack_path)]), 0)

            stored = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertEqual(
                stored["strings"]["done.title"]["localizations"]["hi"],
                {"stringUnit": {"state": "translated", "value": "पूर्ण"}},
            )

    def test_apply_translation_pack_rejects_invalid_inferred_languages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pack_path = Path(directory) / "pack.json"
            pack_path.write_text(
                json.dumps({"languages": ["hi", ""], "catalogStrings": {}, "infoPlistStrings": {}}),
                encoding="utf-8",
            )

            result = apply_translation_pack(pack_path, None)

            self.assertEqual(
                result["failures"],
                ["translation pack languages must contain only non-empty strings"],
            )

            duplicate = Path(directory) / "duplicate.json"
            duplicate.write_text(
                json.dumps({"languages": ["hi", "hi"], "catalogStrings": {}, "infoPlistStrings": {}}),
                encoding="utf-8",
            )
            result = apply_translation_pack(duplicate, None)
            self.assertEqual(result["failures"], ["translation pack languages must not contain duplicates"])

    def test_apply_translation_pack_requires_top_level_payload_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "strings": {
                            "done.title": {
                                "localizations": {
                                    "en": {"stringUnit": {"value": "Done"}},
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogString": {"Done": {"hi": "पूर्ण"}},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch("localization_expand.ROOT", root):
                result = apply_translation_pack(pack_path, None)

            self.assertEqual(
                result["failures"],
                ["translation pack missing required top-level key(s): ['catalogStrings', 'infoPlistStrings']"],
            )
            stored = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertNotIn("hi", stored["strings"]["done.title"]["localizations"])

    def test_apply_translation_pack_rejects_stale_catalog_occurrences_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog_path = root / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "strings": {
                            "done.title": {
                                "localizations": {
                                    "en": {"stringUnit": {"value": "Finished"}},
                                }
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogStrings": [
                            {
                                "en": "Done",
                                "langs": ["hi"],
                                "occurrences": [
                                    {
                                        "catalog": "Sources/LorvexMobile/Resources/Localizable.xcstrings",
                                        "key": "done.title",
                                    }
                                ],
                                "translations": {"hi": "पूर्ण"},
                            }
                        ],
                        "infoPlistStrings": {},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            with patch("localization_expand.ROOT", root):
                result = apply_translation_pack(pack_path, None)

            self.assertIn(
                "'Done' catalog occurrence 'Sources/LorvexMobile/Resources/Localizable.xcstrings' "
                "'done.title' source mismatch: 'Finished'",
                result["failures"],
            )
            stored = json.loads(catalog_path.read_text(encoding="utf-8"))
            self.assertNotIn("hi", stored["strings"]["done.title"]["localizations"])

    def test_apply_translation_pack_rejects_stale_info_plist_gaps_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "Config" / "InfoPlist" / "LorvexMobileApp"
            en = target / "en.lproj"
            hi = target / "hi.lproj"
            en.mkdir(parents=True)
            hi.mkdir(parents=True)
            en.joinpath("InfoPlist.strings").write_text(
                '"Quick Capture" = "Quick Capture";\n',
                encoding="utf-8",
            )
            hi.joinpath("InfoPlist.strings").write_text(
                '"Quick Capture" = "पहले से अनूदित";\n',
                encoding="utf-8",
            )
            pack_path = root / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogStrings": {},
                        "infoPlistStrings": {
                            "LorvexMobileApp": {
                                "Quick Capture": {
                                    "en": "Quick Capture",
                                    "missing": ["hi"],
                                    "translations": {"hi": "त्वरित कैप्चर"},
                                }
                            }
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            result = apply_translation_pack(pack_path, None, config_root=root / "Config")

            self.assertIn(
                "LorvexMobileApp 'Quick Capture' InfoPlist already has translations for ['hi']",
                result["failures"],
            )
            self.assertEqual(
                parse_strings_file(hi / "InfoPlist.strings"),
                {"Quick Capture": "पहले से अनूदित"},
            )

    def test_apply_translation_pack_rejects_malformed_catalog_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pack_path = Path(directory) / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogStrings": [
                            {
                                "en": "Done",
                                "langs": ["hi", ""],
                                "occurrences": [
                                    {
                                        "catalog": "../../outside.xcstrings",
                                        "key": "done.title",
                                    }
                                ],
                                "translations": {"hi": "पूर्ण"},
                            }
                        ],
                        "infoPlistStrings": {},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            result = apply_translation_pack(pack_path, None)

            self.assertIn("'Done' langs metadata must contain only non-empty strings", result["failures"])
            self.assertIn(
                "'Done' catalog occurrence path escapes the Apple root: '../../outside.xcstrings'",
                result["failures"],
            )

    def test_apply_translation_pack_rejects_malformed_info_plist_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pack_path = Path(directory) / "pack.json"
            pack_path.write_text(
                json.dumps(
                    {
                        "languages": ["hi"],
                        "catalogStrings": {},
                        "infoPlistStrings": {
                            "LorvexMobileApp": {
                                "Quick Capture": {
                                    "en": "",
                                    "missing": ["hi", ""],
                                    "translations": {"hi": "त्वरित कैप्चर"},
                                }
                            }
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            result = apply_translation_pack(pack_path, None)

            self.assertIn("LorvexMobileApp 'Quick Capture' en metadata must be a non-empty string", result["failures"])
            self.assertIn(
                "LorvexMobileApp 'Quick Capture' missing metadata must contain only non-empty strings",
                result["failures"],
            )


if __name__ == "__main__":
    unittest.main()
