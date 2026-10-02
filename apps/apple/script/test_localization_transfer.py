#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import localization_transfer  # noqa: E402
from localization_transfer import (  # noqa: E402
    apply_document,
    apply_multi_document,
    define_entries,
    document_text,
    export_document,
    export_multi_document,
    import_document,
    import_from_checkout,
    import_multi_document,
    remove_entries,
    windowed_document,
)


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(**forms: str) -> dict:
    return {"variations": {"plural": {category: unit(text) for category, text in forms.items()}}}


def make_checkout(root: Path, *, greeting: str = "Hello") -> Path:
    catalog = {
        "sourceLanguage": "en",
        "strings": {
            "greeting": {
                "comment": "Shown on launch",
                "extractionState": "manual",
                "localizations": {"en": unit(greeting), "zh-Hans": unit("你好")},
            },
            "tasks.count": {
                "extractionState": "manual",
                "localizations": {
                    "en": plural(one="%lld task", other="%lld tasks"),
                    "zh-Hans": plural(other="%lld 项任务"),
                },
            },
        },
        "version": "1.0",
    }
    catalog_path = root / "Sources" / "Mod" / "Resources" / "Localizable.xcstrings"
    catalog_path.parent.mkdir(parents=True)
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    info = root / "Config" / "InfoPlist" / "App"
    (info / "en.lproj").mkdir(parents=True)
    (info / "zh-Hans.lproj").mkdir(parents=True)
    (info / "en.lproj" / "InfoPlist.strings").write_text(
        '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Open Today";\n', encoding="utf-8")
    (info / "zh-Hans.lproj" / "InfoPlist.strings").write_text(
        '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "打开今日";\n', encoding="utf-8")
    return catalog_path


def fill(document: dict, catalog: dict[str, object], info_plist: dict[str, str]) -> dict:
    for item in document["catalogItems"]:
        item["translation"] = catalog.get(item["key"])
    for item in document["infoPlistItems"]:
        item["translation"] = info_plist.get(item["key"])
    return document


def fill_multi(
    document: dict,
    catalog: dict[str, dict[str, object]],
    info_plist: dict[str, dict[str, str]],
) -> dict:
    """Fill every slot of a several-language document from per-key language maps."""
    for item in document["catalogItems"]:
        for language in item["translations"]:
            item["translations"][language] = catalog.get(item["key"], {}).get(language)
    for item in document["infoPlistItems"]:
        for language in item["translations"]:
            item["translations"][language] = info_plist.get(item["key"], {}).get(language)
    return document


TASKS_COUNT = {
    "es": {"plural": {"one": "%lld tarea", "other": "%lld tareas"}},
    "fr": {"plural": {"one": "%lld tâche", "other": "%lld tâches"}},
}


class LocalizationTransferTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name) / "main"
        self.catalog_path = make_checkout(self.root)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def catalog(self) -> dict:
        return json.loads(self.catalog_path.read_text(encoding="utf-8"))

    def test_export_lists_every_entry_and_info_plist_key_missing_the_language(self) -> None:
        document = export_document(self.root, "es")

        self.assertEqual(
            document["pluralCategories"],
            {"required": ["one", "other"], "allowed": ["many", "one", "other", "zero"]})
        greeting = document["catalogItems"][0]
        self.assertEqual(greeting["catalog"], "Sources/Mod/Resources/Localizable.xcstrings")
        self.assertEqual(greeting["key"], "greeting")
        self.assertEqual(greeting["comment"], "Shown on launch")
        self.assertEqual(greeting["source"], unit("Hello"))
        self.assertEqual(greeting["references"], {"zh-Hans": unit("你好")})
        self.assertIsNone(greeting["translation"])
        self.assertEqual([item["key"] for item in document["catalogItems"]], ["greeting", "tasks.count"])
        self.assertEqual(
            [(item["target"], item["key"], item["references"]) for item in document["infoPlistItems"]],
            [
                ("App", "CFBundleDisplayName", {"zh-Hans": "Lorvex"}),
                ("App", "Open Today", {"zh-Hans": "打开今日"}),
            ])

    def test_text_view_pages_through_items_with_their_forms(self) -> None:
        document = export_document(self.root, "es")

        first = document_text(document, 0, 1)
        self.assertIn("[0] Sources/Mod/Resources/Localizable.xcstrings :: greeting", first)
        self.assertIn("  comment: Shown on launch", first)
        self.assertIn("  en: Hello", first)
        self.assertIn("  zh-Hans: 你好", first)
        self.assertNotIn("tasks.count", first)
        self.assertNotIn("InfoPlist", first)

        rest = document_text(document, 1)
        self.assertIn("  en: plural: one=%lld task | other=%lld tasks", rest)
        self.assertIn("[InfoPlist App] Open Today", rest)
        self.assertIn("  zh-Hans: 打开今日", rest)

    def test_import_writes_shorthand_translations_in_the_catalog_format(self) -> None:
        document = fill(
            export_document(self.root, "es"),
            {"greeting": "Hola", "tasks.count": {"plural": {"other": "%lld tareas", "one": "%lld tarea"}}},
            {"CFBundleDisplayName": "Lorvex", "Open Today": "Abrir Hoy"})

        self.assertEqual(import_document(self.root, "es", document), [])

        catalog = self.catalog()
        self.assertEqual(list(catalog["strings"]["greeting"]["localizations"]), ["en", "es", "zh-Hans"])
        self.assertEqual(catalog["strings"]["greeting"]["localizations"]["es"], unit("Hola"))
        self.assertEqual(
            catalog["strings"]["tasks.count"]["localizations"]["es"],
            plural(one="%lld tarea", other="%lld tareas"))
        self.assertEqual(
            self.catalog_path.read_text(encoding="utf-8"),
            json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
        self.assertEqual(
            (self.root / "Config/InfoPlist/App/es.lproj/InfoPlist.strings").read_text(encoding="utf-8"),
            '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Abrir Hoy";\n')
        self.assertEqual(export_document(self.root, "es")["catalogItems"], [])

    def test_import_expands_a_substitution_shorthand_from_the_source(self) -> None:
        catalog = self.catalog()
        catalog["strings"]["open.count"] = {
            "extractionState": "manual",
            "localizations": {
                "en": {
                    "stringUnit": {"state": "translated", "value": "%#@open@"},
                    "substitutions": {
                        "open": {
                            "argNum": 1,
                            "formatSpecifier": "lld",
                            "variations": {"plural": {"one": unit("%arg open"), "other": unit("%arg open")}},
                        }
                    },
                },
                "zh-Hans": unit("%lld 项未完成"),
            },
        }
        self.catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        document = export_document(self.root, "es")
        for item in document["catalogItems"]:
            if item["key"] == "open.count":
                item["translation"] = {
                    "value": "%#@open@",
                    "substitutions": {"open": {"one": "%arg abierta", "other": "%arg abiertas"}},
                }
        document["catalogItems"] = [item for item in document["catalogItems"] if item["key"] == "open.count"]
        document["infoPlistItems"] = []

        self.assertEqual(import_document(self.root, "es", document), [])

        substitution = self.catalog()["strings"]["open.count"]["localizations"]["es"]["substitutions"]["open"]
        self.assertEqual(substitution["argNum"], 1)
        self.assertEqual(substitution["formatSpecifier"], "lld")
        self.assertEqual(
            substitution["variations"]["plural"],
            {"one": unit("%arg abierta"), "other": unit("%arg abiertas")})

    def test_import_skips_invalid_items_and_writes_the_rest(self) -> None:
        document = fill(
            export_document(self.root, "ru"),
            {
                "greeting": "Привет %@",
                "tasks.count": {"plural": {"one": "%lld задача", "other": "%lld задачи"}},
            },
            {"CFBundleDisplayName": "Lorvex", "Open Today": "Открыть «Сегодня»"})

        problems = import_document(self.root, "ru", document)

        self.assertTrue(any("greeting ru format placeholder mismatch" in problem for problem in problems))
        self.assertTrue(
            any("tasks.count ru plural variations missing CLDR categories ['few', 'many']" in problem
                for problem in problems))
        self.assertNotIn("ru", self.catalog()["strings"]["greeting"]["localizations"])
        self.assertEqual(
            (self.root / "Config/InfoPlist/App/ru.lproj/InfoPlist.strings").read_text(encoding="utf-8"),
            '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Открыть «Сегодня»";\n')

    def test_import_rejects_an_item_whose_source_changed_since_the_export(self) -> None:
        document = fill(export_document(self.root, "es"), {"greeting": "Hola"}, {})
        document["catalogItems"] = document["catalogItems"][:1]
        document["infoPlistItems"] = []
        catalog = self.catalog()
        catalog["strings"]["greeting"]["localizations"]["en"] = unit("Hi there")
        self.catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        self.assertEqual(
            import_document(self.root, "es", document),
            ["Sources/Mod/Resources/Localizable.xcstrings greeting: the source text changed since "
             "the export; export again"])

    def test_apply_writes_a_key_map_against_the_current_source(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        self.assertEqual(
            import_document(self.root, "es", apply_document(self.root, relative, {"greeting": "Hola"})),
            [])
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Hola"))

        # A second pass, naming the catalog by its absolute path, revises the
        # translation; a key the catalog lacks is reported.
        problems = import_document(
            self.root, "es",
            apply_document(self.root, str(self.catalog_path), {"greeting": "Buenas", "farewell": "Adiós"}))

        self.assertEqual(problems, [f"{relative} farewell: the key is not in the catalog"])
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Buenas"))

    def test_a_catalog_path_that_names_no_catalog_is_an_error(self) -> None:
        with self.assertRaises(SystemExit):
            export_document(self.root, "es", "Sources/Missing/Resources/Localizable.xcstrings")

    def test_import_requires_declared_plural_rules(self) -> None:
        problems = import_document(self.root, "xx", {"catalogItems": [], "infoPlistItems": []})

        self.assertEqual(len(problems), 1)
        self.assertIn("'xx' has no CLDR plural categories", problems[0])

    def test_from_checkout_copies_translations_whose_source_matches(self) -> None:
        branch = Path(self.directory.name) / "branch"
        make_checkout(branch, greeting="Hi")
        branch_document = fill(
            export_document(branch, "es"),
            {"greeting": "Hola", "tasks.count": {"plural": {"one": "%lld tarea", "other": "%lld tareas"}}},
            {"CFBundleDisplayName": "Lorvex", "Open Today": "Abrir Hoy"})
        self.assertEqual(import_document(branch, "es", branch_document), [])

        copied, missing = import_from_checkout(self.root, "es", branch)

        # The branch translated "Hi"; this checkout's source says "Hello".
        self.assertEqual(copied, 3)
        self.assertEqual(missing, ["Sources/Mod/Resources/Localizable.xcstrings greeting"])
        self.assertEqual(
            self.catalog()["strings"]["tasks.count"]["localizations"]["es"],
            plural(one="%lld tarea", other="%lld tareas"))
        self.assertNotIn("es", self.catalog()["strings"]["greeting"]["localizations"])

    def test_from_checkout_follows_a_key_that_moved_to_another_catalog(self) -> None:
        # Here "moved" and "split" live in the Mod catalog; the branch still has
        # them in two older catalogs and no longer has them in Mod.
        catalog = self.catalog()
        for key in ("moved", "split"):
            catalog["strings"][key] = {
                "extractionState": "manual", "localizations": {"en": unit(key.title())}}
        self.catalog_path.write_text(
            json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        branch = Path(self.directory.name) / "branch"
        make_checkout(branch)
        for module, split in (("Old", "Dividir"), ("Older", "Partir")):
            old = branch / "Sources" / module / "Resources" / "Localizable.xcstrings"
            old.parent.mkdir(parents=True)
            old.write_text(json.dumps({"sourceLanguage": "en", "strings": {
                "greeting": {"localizations": {"en": unit("Hello"), "es": unit("Hola")}},
                "moved": {"localizations": {"en": unit("Moved"), "es": unit("Movido")}},
                "split": {"localizations": {"en": unit("Split"), "es": unit(split)}},
            }, "version": "1.0"}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        copied, missing = import_from_checkout(self.root, "es", branch)

        strings = self.catalog()["strings"]
        self.assertEqual(strings["moved"]["localizations"]["es"], unit("Movido"))
        # The two older catalogs disagree, so neither translation is taken.
        self.assertNotIn("es", strings["split"]["localizations"])
        self.assertIn("Sources/Mod/Resources/Localizable.xcstrings split", missing)
        # A key still in the branch's matching catalog never falls back to
        # another catalog, even when that one's source text would match.
        self.assertNotIn("es", strings["greeting"]["localizations"])
        self.assertEqual(copied, 1)

    def test_define_adds_an_entry_in_every_shipped_language_at_its_sorted_place(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        problems = define_entries(self.root, relative, {
            "farewell": {"comment": "Shown on quit", "en": "Goodbye", "zh-Hans": "再见"},
        })

        self.assertEqual(problems, [])
        catalog = self.catalog()
        self.assertEqual(list(catalog["strings"]), ["farewell", "greeting", "tasks.count"])
        self.assertEqual(catalog["strings"]["farewell"], {
            "comment": "Shown on quit",
            "extractionState": "manual",
            "localizations": {"en": unit("Goodbye"), "zh-Hans": unit("再见")},
        })
        self.assertEqual(
            self.catalog_path.read_text(encoding="utf-8"),
            json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")

    def test_define_replaces_a_whole_entry_where_it_stands(self) -> None:
        problems = define_entries(self.root, str(self.catalog_path), {
            "tasks.count": {
                "en": {"plural": {"one": "%lld open task", "other": "%lld open tasks"}},
                "zh-Hans": {"plural": {"other": "%lld 项未完成任务"}},
            },
        })

        self.assertEqual(problems, [])
        catalog = self.catalog()
        self.assertEqual(list(catalog["strings"]), ["greeting", "tasks.count"])
        self.assertEqual(catalog["strings"]["tasks.count"]["localizations"], {
            "en": plural(one="%lld open task", other="%lld open tasks"),
            "zh-Hans": plural(other="%lld 项未完成任务"),
        })

    def test_define_requires_exactly_the_shipped_languages(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        before = self.catalog_path.read_text(encoding="utf-8")

        problems = define_entries(self.root, relative, {
            "farewell": {"en": "Goodbye"},
            "welcome": {"en": "Welcome", "zh-Hans": "欢迎", "zh": "欢迎"},
        })

        self.assertEqual(problems, [
            f"{relative} farewell: the spec lacks ['zh-Hans']",
            f"{relative} welcome: the spec names ['zh'], which the catalogs do not ship",
        ])
        self.assertEqual(self.catalog_path.read_text(encoding="utf-8"), before)

    def test_define_checks_placeholders_and_plural_categories(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        problems = define_entries(self.root, relative, {
            "lost.placeholder": {"en": "Moved %@", "zh-Hans": "已移动"},
            "wrong.categories": {
                "en": {"plural": {"one": "%lld day", "other": "%lld days"}},
                "zh-Hans": {"plural": {"one": "%lld 天", "other": "%lld 天"}},
            },
            "kept": {"en": "Moved %@", "zh-Hans": "已移动 %@"},
        })

        self.assertEqual(len(problems), 2)
        self.assertIn("lost.placeholder", problems[0])
        self.assertIn("wrong.categories", problems[1])
        self.assertEqual(list(self.catalog()["strings"]), ["greeting", "kept", "tasks.count"])

    def test_a_language_with_one_plural_category_may_write_a_count_as_plain_text(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        problems = define_entries(self.root, relative, {
            "tasks.done": {
                "en": {"plural": {"one": "%lld task done", "other": "%lld tasks done"}},
                "zh-Hans": "已完成 %lld\u00a0项任务",
            },
        })

        self.assertEqual(problems, [])
        self.assertEqual(
            self.catalog()["strings"]["tasks.done"]["localizations"]["zh-Hans"],
            unit("已完成 %lld\u00a0项任务"))

    def test_import_rejects_a_plain_count_where_the_language_has_plural_categories(self) -> None:
        document = fill(
            export_document(self.root, "es"),
            {"greeting": "Hola", "tasks.count": "%lld tareas"},
            {"CFBundleDisplayName": "Lorvex", "Open Today": "Abrir Hoy"})

        problems = import_document(self.root, "es", document)

        self.assertTrue(any(
            "tasks.count es does not vary argument 1 by plural; en does, and es has the plural "
            "categories ['one', 'other']" in problem for problem in problems), problems)
        self.assertNotIn("es", self.catalog()["strings"]["tasks.count"]["localizations"])
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Hola"))

    def test_remove_deletes_entries_and_reports_absent_keys(self) -> None:
        relative = "Sources/Mod/Resources/Localizable.xcstrings"
        problems = remove_entries(self.root, relative, ["greeting", "farewell"])

        self.assertEqual(problems, [f"{relative} farewell: the key is not in the catalog"])
        self.assertEqual(list(self.catalog()["strings"]), ["tasks.count"])


RELATIVE = "Sources/Mod/Resources/Localizable.xcstrings"


class MultiLanguageTransferTests(unittest.TestCase):
    """Export, import, and apply of several languages in one document."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name) / "main"
        self.catalog_path = make_checkout(self.root)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def catalog(self) -> dict:
        return json.loads(self.catalog_path.read_text(encoding="utf-8"))

    def save(self, catalog: dict) -> None:
        self.catalog_path.write_text(
            json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    def info_plist(self, language: str) -> str:
        return (self.root / f"Config/InfoPlist/App/{language}.lproj/InfoPlist.strings").read_text(
            encoding="utf-8")

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(localization_transfer, "ROOT", self.root),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            status = localization_transfer.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def filled_document(self) -> dict:
        return fill_multi(
            export_multi_document(self.root, ["es", "fr"]),
            {"greeting": {"es": "Hola", "fr": "Salut"}, "tasks.count": TASKS_COUNT},
            {
                "CFBundleDisplayName": {"es": "Lorvex", "fr": "Lorvex"},
                "Open Today": {"es": "Abrir Hoy", "fr": "Ouvrir Aujourd’hui"},
            })

    def test_export_has_one_slot_per_language_and_no_references(self) -> None:
        document = export_multi_document(self.root, ["es", "fr"])

        self.assertEqual(document["languages"], ["es", "fr"])
        self.assertEqual(document["sourceLanguage"], "en")
        required = {"required": ["one", "other"], "allowed": ["many", "one", "other", "zero"]}
        self.assertEqual(document["pluralCategories"], {"es": required, "fr": required})
        self.assertEqual(document["catalogItems"][0], {
            "catalog": RELATIVE,
            "key": "greeting",
            "comment": "Shown on launch",
            "source": unit("Hello"),
            "translations": {"es": None, "fr": None},
        })
        self.assertEqual(
            document["catalogItems"][1]["source"], plural(one="%lld task", other="%lld tasks"))
        self.assertEqual(document["infoPlistItems"], [
            {"target": "App", "key": "CFBundleDisplayName", "source": "Lorvex",
             "translations": {"es": None, "fr": None}},
            {"target": "App", "key": "Open Today", "source": "Open Today",
             "translations": {"es": None, "fr": None}},
        ])

    def test_export_gives_a_slot_only_to_the_languages_that_lack_the_entry(self) -> None:
        catalog = self.catalog()
        strings = catalog["strings"]
        strings["greeting"]["localizations"]["es"] = unit("Hola")
        strings["greeting"]["localizations"]["fr"] = {
            "stringUnit": {"state": "needs_review", "value": "Salut"}}
        for language, forms in TASKS_COUNT.items():
            strings["tasks.count"]["localizations"][language] = {
                "variations": {"plural": {
                    category: unit(text) for category, text in forms["plural"].items()}}}
        self.save(catalog)
        info = self.root / "Config/InfoPlist/App/es.lproj"
        info.mkdir()
        (info / "InfoPlist.strings").write_text('"CFBundleDisplayName" = "Lorvex";\n', encoding="utf-8")

        document = export_multi_document(self.root, ["es", "fr"])

        self.assertEqual([item["key"] for item in document["catalogItems"]], ["greeting"])
        greeting = document["catalogItems"][0]
        self.assertEqual(greeting["translations"], {"fr": None})
        self.assertEqual(
            greeting["current"], {"fr": {"stringUnit": {"state": "needs_review", "value": "Salut"}}})
        self.assertEqual(
            [(item["key"], item["translations"]) for item in document["infoPlistItems"]],
            [
                ("CFBundleDisplayName", {"fr": None}),
                ("Open Today", {"es": None, "fr": None}),
            ])

    def test_export_can_be_limited_to_one_catalog_without_the_info_plist_keys(self) -> None:
        document = export_multi_document(self.root, ["es", "fr"], str(self.catalog_path))

        self.assertEqual(len(document["catalogItems"]), 2)
        self.assertEqual(document["infoPlistItems"], [])

    def test_text_view_names_the_languages_an_item_lacks_when_not_all(self) -> None:
        catalog = self.catalog()
        catalog["strings"]["greeting"]["localizations"]["es"] = unit("Hola")
        self.save(catalog)
        document = export_multi_document(self.root, ["es", "fr"])

        first = document_text(document, 0, 1)
        self.assertIn("es, fr: catalog items 0..<1 of 2", first)
        self.assertIn("  fr: plural categories required ['one', 'other']", first)
        self.assertIn("[0] Sources/Mod/Resources/Localizable.xcstrings :: greeting", first)
        self.assertIn("  comment: Shown on launch", first)
        self.assertIn("  en: Hello", first)
        self.assertIn("  lacks: fr", first)
        self.assertNotIn("zh-Hans", first)
        self.assertNotIn("tasks.count", first)
        self.assertNotIn("InfoPlist", first)

        rest = document_text(document, 1)
        self.assertIn("  en: plural: one=%lld task | other=%lld tasks", rest)
        self.assertNotIn("lacks", rest)
        self.assertIn("[InfoPlist App] Open Today", rest)

    def test_a_window_keeps_the_info_plist_items_for_the_last_page(self) -> None:
        document = export_multi_document(self.root, ["es", "fr"])

        first = windowed_document(document, 0, 1)
        self.assertEqual([item["key"] for item in first["catalogItems"]], ["greeting"])
        self.assertEqual(first["infoPlistItems"], [])
        self.assertEqual(first["languages"], ["es", "fr"])

        last = windowed_document(document, 1, 5)
        self.assertEqual([item["key"] for item in last["catalogItems"]], ["tasks.count"])
        self.assertEqual(len(last["infoPlistItems"]), 2)

        self.assertEqual(windowed_document(document), document)
        self.assertEqual(
            list(windowed_document(export_document(self.root, "es"))),
            ["language", "sourceLanguage", "pluralCategories", "catalogItems", "infoPlistItems"])

    def test_import_writes_every_language_in_the_catalog_format(self) -> None:
        self.assertEqual(import_multi_document(self.root, self.filled_document()), [])

        catalog = self.catalog()
        greeting = catalog["strings"]["greeting"]["localizations"]
        self.assertEqual(list(greeting), ["en", "es", "fr", "zh-Hans"])
        self.assertEqual(greeting["es"], unit("Hola"))
        self.assertEqual(greeting["fr"], unit("Salut"))
        tasks = catalog["strings"]["tasks.count"]["localizations"]
        self.assertEqual(tasks["es"], plural(one="%lld tarea", other="%lld tareas"))
        self.assertEqual(tasks["fr"], plural(one="%lld tâche", other="%lld tâches"))
        self.assertEqual(
            self.catalog_path.read_text(encoding="utf-8"),
            json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
        self.assertEqual(
            self.info_plist("es"), '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Abrir Hoy";\n')
        self.assertEqual(
            self.info_plist("fr"),
            '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Ouvrir Aujourd’hui";\n')
        remaining = export_multi_document(self.root, ["es", "fr"])
        self.assertEqual(remaining["catalogItems"], [])
        self.assertEqual(remaining["infoPlistItems"], [])

    def test_import_checks_each_slot_on_its_own(self) -> None:
        document = fill_multi(
            export_multi_document(self.root, ["es", "fr"]),
            {
                "greeting": {"es": "Hola", "fr": "Salut %@"},
                "tasks.count": {
                    "es": TASKS_COUNT["es"],
                    "fr": {"plural": {"other": "%lld tâches"}},
                },
            },
            {"CFBundleDisplayName": {"es": "Lorvex", "fr": "Lorvex"}, "Open Today": {"es": "Abrir Hoy"}})

        problems = import_multi_document(self.root, document)

        self.assertTrue(
            any("greeting fr format placeholder mismatch" in problem for problem in problems), problems)
        self.assertTrue(any(
            "tasks.count fr plural variations missing CLDR categories ['one']" in problem
            for problem in problems), problems)
        self.assertIn("InfoPlist App Open Today fr: no translation", problems)
        self.assertEqual(len(problems), 3)
        catalog = self.catalog()["strings"]
        self.assertEqual(catalog["greeting"]["localizations"]["es"], unit("Hola"))
        self.assertEqual(
            catalog["tasks.count"]["localizations"]["es"], plural(one="%lld tarea", other="%lld tareas"))
        self.assertNotIn("fr", catalog["greeting"]["localizations"])
        self.assertNotIn("fr", catalog["tasks.count"]["localizations"])
        self.assertEqual(
            self.info_plist("es"), '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Abrir Hoy";\n')
        self.assertEqual(self.info_plist("fr"), '"CFBundleDisplayName" = "Lorvex";\n')

    def test_import_reports_a_changed_source_once_per_item(self) -> None:
        document = self.filled_document()
        document["catalogItems"] = document["catalogItems"][:1]
        document["infoPlistItems"] = []
        catalog = self.catalog()
        catalog["strings"]["greeting"]["localizations"]["en"] = unit("Hi there")
        self.save(catalog)

        self.assertEqual(
            import_multi_document(self.root, document),
            [f"{RELATIVE} greeting: the source text changed since the export; export again"])

    def test_import_rejects_a_slot_for_a_language_the_document_does_not_list(self) -> None:
        document = self.filled_document()
        document["languages"] = ["es"]

        problems = import_multi_document(self.root, document)

        self.assertIn(f"{RELATIVE} greeting: names fr, which the document does not list", problems)
        self.assertIn("InfoPlist App Open Today: names fr, which the document does not list", problems)
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Hola"))
        self.assertNotIn("fr", self.catalog()["strings"]["greeting"]["localizations"])

    def test_import_without_declared_plural_rules_writes_only_the_other_languages(self) -> None:
        document = fill_multi(
            export_multi_document(self.root, ["es", "xx"]),
            {
                "greeting": {"es": "Hola", "xx": "…"},
                "tasks.count": {"es": TASKS_COUNT["es"], "xx": "…"},
            },
            {
                "CFBundleDisplayName": {"es": "Lorvex", "xx": "Lorvex"},
                "Open Today": {"es": "Abrir Hoy", "xx": "…"},
            })

        problems = import_multi_document(self.root, document)

        self.assertEqual(len(problems), 1, problems)
        self.assertIn("'xx' has no CLDR plural categories", problems[0])
        greeting = self.catalog()["strings"]["greeting"]["localizations"]
        self.assertEqual(greeting["es"], unit("Hola"))
        self.assertNotIn("xx", greeting)
        self.assertFalse((self.root / "Config/InfoPlist/App/xx.lproj").exists())

    def test_an_import_that_stops_partway_keeps_what_it_wrote(self) -> None:
        document = self.filled_document()
        # A malformed strings file makes the InfoPlist step stop the run after
        # the catalogs were written.
        broken = self.root / "Config/InfoPlist/App/fr.lproj"
        broken.mkdir()
        (broken / "InfoPlist.strings").write_text("not a strings file\n", encoding="utf-8")

        with self.assertRaises(SystemExit):
            import_multi_document(self.root, document)

        greeting = self.catalog()["strings"]["greeting"]["localizations"]
        self.assertEqual(greeting["es"], unit("Hola"))
        self.assertEqual(greeting["fr"], unit("Salut"))

    def test_apply_writes_a_key_map_for_several_languages(self) -> None:
        document = apply_multi_document(self.root, RELATIVE, ["es", "fr"], {
            "greeting": {"es": "Hola", "fr": "Salut"},
            "tasks.count": {"es": TASKS_COUNT["es"]},
        })

        self.assertEqual(import_multi_document(self.root, document), [])

        catalog = self.catalog()["strings"]
        self.assertEqual(catalog["greeting"]["localizations"]["fr"], unit("Salut"))
        self.assertIn("es", catalog["tasks.count"]["localizations"])
        self.assertNotIn("fr", catalog["tasks.count"]["localizations"])

        # A second pass revises, and reports a missing key, a stray language,
        # and a value that is not an object of language to translation.
        problems = import_multi_document(self.root, apply_multi_document(
            self.root, str(self.catalog_path), ["es", "fr"], {
                "greeting": {"es": "Buenas", "de": "Hallo"},
                "farewell": {"es": "Adiós"},
                "tasks.count": "%lld tareas",
            }))

        self.assertEqual(problems, [
            f"{RELATIVE} greeting: names de, which the document does not list",
            f"{RELATIVE} farewell: the key is not in the catalog",
            f"{RELATIVE} tasks.count: \"translations\" maps each language to its translation",
        ])
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Buenas"))

    def test_cli_exports_several_languages_as_a_listing_and_as_windows(self) -> None:
        status, out, _ = self.run_cli(
            "export", "--language", "es", "--language", "fr", "--text", "--limit", "1")
        self.assertEqual(status, 0)
        self.assertIn("es, fr: catalog items 0..<1 of 2", out)

        output = Path(self.directory.name) / "page.json"
        status, _, err = self.run_cli(
            "export", "--language", "es", "--language", "fr", "--offset", "1",
            "--output", str(output))
        self.assertEqual(status, 0)
        self.assertEqual(err, "2 catalog entries and 2 InfoPlist keys lack at least one of es, fr\n")
        page = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual([item["key"] for item in page["catalogItems"]], ["tasks.count"])
        self.assertEqual(len(page["infoPlistItems"]), 2)

        status, _, err = self.run_cli("export", "--language", "es", "--limit", "1", "--output", str(output))
        self.assertEqual((status, err), (0, "2 catalog entries and 2 InfoPlist keys lack es\n"))
        single = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual([item["key"] for item in single["catalogItems"]], ["greeting"])
        self.assertEqual(single["infoPlistItems"], [])

    def test_cli_imports_a_several_language_document_that_names_its_languages(self) -> None:
        output = Path(self.directory.name) / "filled.json"
        output.write_text(json.dumps(self.filled_document(), ensure_ascii=False), encoding="utf-8")

        status, _, err = self.run_cli("import", "--language", "es", str(output))
        self.assertEqual(status, 1)
        self.assertEqual(err, "the document is for ['es', 'fr'], not ['es']\n")

        status, out, err = self.run_cli("import", str(output))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual(out, "imported every item in es, fr\n")
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["fr"], unit("Salut"))

    def test_cli_imports_a_single_language_document_by_its_own_language(self) -> None:
        output = Path(self.directory.name) / "filled.json"
        output.write_text(
            json.dumps(fill(
                export_document(self.root, "es"),
                {"greeting": "Hola", "tasks.count": TASKS_COUNT["es"]},
                {"CFBundleDisplayName": "Lorvex", "Open Today": "Abrir Hoy"}), ensure_ascii=False),
            encoding="utf-8")

        status, _, err = self.run_cli("import", "--language", "fr", str(output))
        self.assertEqual((status, err), (1, "the document is for 'es', not 'fr'\n"))

        status, out, _ = self.run_cli("import", str(output))
        self.assertEqual((status, out), (0, "imported every es item\n"))
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["es"], unit("Hola"))

    def test_cli_applies_a_key_map_of_several_languages(self) -> None:
        translations = Path(self.directory.name) / "map.json"
        translations.write_text(
            json.dumps({"greeting": {"es": "Hola", "fr": "Salut"}, "tasks.count": TASKS_COUNT}),
            encoding="utf-8")

        status, out, err = self.run_cli(
            "apply", "--language", "es", "--language", "fr", "--catalog", RELATIVE, str(translations))

        self.assertEqual((status, err), (0, ""))
        self.assertEqual(out, "applied all 2 entries in es, fr\n")
        localizations = self.catalog()["strings"]["tasks.count"]["localizations"]
        self.assertEqual(localizations["fr"], plural(one="%lld tâche", other="%lld tâches"))

    def test_cli_copies_several_languages_from_a_checkout(self) -> None:
        branch = Path(self.directory.name) / "branch"
        make_checkout(branch)
        self.assertEqual(import_multi_document(branch, fill_multi(
            export_multi_document(branch, ["es", "fr"]),
            {"greeting": {"es": "Hola", "fr": "Salut"}, "tasks.count": TASKS_COUNT},
            {
                "CFBundleDisplayName": {"es": "Lorvex", "fr": "Lorvex"},
                "Open Today": {"es": "Abrir Hoy", "fr": "Ouvrir Aujourd’hui"},
            })), [])

        status, out, _ = self.run_cli(
            "import", "--language", "es", "--language", "fr", "--from-checkout", str(branch))

        self.assertEqual(status, 0)
        self.assertEqual(out, "copied 4 es translations\ncopied 4 fr translations\n")
        self.assertEqual(self.catalog()["strings"]["greeting"]["localizations"]["fr"], unit("Salut"))
        self.assertEqual(
            self.info_plist("fr"),
            '"CFBundleDisplayName" = "Lorvex";\n"Open Today" = "Ouvrir Aujourd’hui";\n')
        remaining = export_multi_document(self.root, ["es", "fr"])
        self.assertEqual((remaining["catalogItems"], remaining["infoPlistItems"]), ([], []))

    def test_cli_needs_a_language_to_copy_from_a_checkout(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()) as err, self.assertRaises(SystemExit):
            localization_transfer.parse_args(["import", "--from-checkout", self.directory.name])

        self.assertIn("--from-checkout needs at least one --language", err.getvalue())


if __name__ == "__main__":
    unittest.main()
