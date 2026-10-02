#!/usr/bin/env python3
"""Move translations in and out of the app's string catalogs, one language or
several at a time.

Usage:
  localization_transfer.py export --language es [--language fr ...] [--catalog PATH]
                                  [--output FILE] [--text] [--offset N] [--limit N]
  localization_transfer.py import [--language es [--language fr ...]] FILE
  localization_transfer.py apply --language es [--language fr ...] --catalog PATH FILE
  localization_transfer.py import --language es [--language fr ...] --from-checkout PATH
  localization_transfer.py define --catalog PATH FILE
  localization_transfer.py remove --catalog PATH KEY [KEY ...]

`export` lists every String Catalog entry (`Sources/*/Resources/*.xcstrings`)
and every `Config/InfoPlist/<Target>/en.lproj/InfoPlist.strings` key that
lacks the language, as one JSON document. Each item carries its source text,
its comment, the other shipped languages' translations for reference, and a
null `translation` for the translator to fill. The document also states the
language's CLDR plural categories (required and allowed). `--catalog` limits
the export to one catalog and leaves out the InfoPlist.strings keys; PATH is
relative to `apps/apple`, relative to the working directory, or absolute.
`--text` prints the same items as a readable listing, one block per item with
its index. `--offset`/`--limit` select a window of the catalog items in either
form; the InfoPlist.strings items belong to the last window, so a document
written in windows is imported window by window.

Repeating `--language` exports several languages in one document, so each
entry's source text and comment are read once for all of them. The document
names its `languages`, maps each language to its plural categories in
`pluralCategories`, and lists every entry that lacks at least one of them.
Each item carries a `translations` object, `{"fr": null, "it": null}`, with a
null slot for each language that still lacks the entry (a language that
already has it gets no slot); an item has no `references`. `--text` adds a
"lacks" line to an item that misses only some of the languages.

`import` writes a filled document back. A catalog entry gets its translation
with every state set to "translated" and its languages kept in sorted order; a
target's `<language>.lproj/InfoPlist.strings` is written in the key order of
the source file beside it. Each item is checked first: an item whose source
text changed since the export, or whose translation fails the localization
verifier's entry checks (placeholders, CLDR plural categories), is skipped
with its reason, the valid items are written, and the command exits 1. A
multi-language document writes every language it contains, each slot checked
on its own, and each catalog file is written as soon as its items are done, so
an import that stops partway keeps what it wrote; without `--language` the
document's own language or languages are imported.

`apply` writes a JSON object mapping keys of one catalog to their
translations, checked like `import` against the catalog's current source
text. A key that already has the language is overwritten, so `apply` also
revises earlier translations. With several `--language` options the object
maps each key to an object of language to translation,
`{"key": {"fr": "…", "it": "…"}}`; a language a key leaves out is not touched.

`import --from-checkout` copies the language's translations from another
checkout of this repository (a localization branch's worktree) for every entry
whose source text matches here, then lists the entries still missing the
language. An entry is looked up under its key in the same catalog of the other
checkout; when that catalog lacks the key, because the key moved to another
catalog on one side, the translation comes from whichever other catalog holds
the key with the same source text, provided every such catalog agrees on it.
Merging a localization branch therefore never hand-resolves catalog
conflicts: keep this checkout's catalogs, copy the branch's translations, and
translate what the list names. Several `--language` options copy each language
in turn and list what each still lacks.

`define` creates or replaces whole entries of one catalog from a JSON object
mapping each key to its spec: an optional `comment` and the text of every
language the catalogs ship, the source language included, each in the
translation shapes below. A spec that leaves out a shipped language or names
one the catalogs do not carry is rejected, so a string ships translated into
every language or not at all; each entry must also pass the verifier's entry
checks. A new key goes before the first key that sorts after it, and a
replaced entry keeps its place. `remove` deletes entries from one catalog.

A `translation` is the full localization object for the language or one of
these shorthands, in whichever shape the language needs: a language with a
single plural category may give plain text where the source varies by plural,
and any language may vary where the source does not.
  "text"                                        a plain string
  {"plural": {"one": "…", "other": "…"}}        plural variations
  {"value": "… %#@n@ …",
   "substitutions": {"n": {"one": "%arg …", "other": "%arg …"}}}
A substitution shorthand takes `argNum` and `formatSpecifier` from the source
substitution of the same name, or from keys of those names in the shorthand
when the source has none. An InfoPlist.strings `translation` is a string.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Callable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from verify_localization_catalog import (  # noqa: E402
    DEFAULT_SOURCE_LANGUAGE,
    ROOT,
    catalog_entry_failures,
    parse_info_plist_strings,
    plural_rules_for,
    required_languages,
)


# MARK: - Files


def catalog_paths(root: Path) -> list[Path]:
    return sorted((root / "Sources").glob("*/Resources/*.xcstrings"))


def resolve_catalog(root: Path, catalog: str) -> Path:
    """The catalog under `root` that `catalog` names: a path relative to
    `root`, relative to the working directory, or absolute."""
    wanted = {(root / catalog).resolve(), Path(catalog).resolve()}
    for path in catalog_paths(root):
        if path.resolve() in wanted:
            return path
    raise SystemExit(f"{catalog} is not one of the string catalogs under {root}")


def info_plist_source_files(root: Path) -> list[Path]:
    return sorted(
        (root / "Config" / "InfoPlist").glob(f"*/{DEFAULT_SOURCE_LANGUAGE}.lproj/InfoPlist.strings")
    )


def info_plist_file(source_file: Path, language: str) -> Path:
    return source_file.parent.parent / f"{language}.lproj" / "InfoPlist.strings"


def load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_catalog(path: Path, catalog: dict) -> None:
    # The catalogs are kept in exactly this serialization, so a rewrite only
    # shows the entries that changed.
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_info_plist_strings(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    entries, failures = parse_info_plist_strings(path)
    if failures:
        raise SystemExit("\n".join(failures))
    return entries


def write_info_plist_strings(path: Path, entries: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};"
        for key, value in entries
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def checkout_app_root(path: Path) -> Path:
    """The `apps/apple` directory of a checkout given its root or that directory."""
    for candidate in (path / "apps" / "apple", path):
        if (candidate / "Sources").is_dir() and (candidate / "Config").is_dir():
            return candidate
    raise SystemExit(f"{path} is not a checkout of this repository")


# MARK: - Localization objects


def is_translated(localization: object) -> bool:
    """Whether every string unit in `localization` is translated and non-empty."""
    units: list[dict] = []

    def walk(value: object) -> None:
        if isinstance(value, dict):
            unit = value.get("stringUnit")
            if isinstance(unit, dict):
                units.append(unit)
            for child in value.values():
                walk(child)

    walk(localization)
    return bool(units) and all(
        unit.get("state") == "translated"
        and isinstance(unit.get("value"), str)
        and unit["value"].strip()
        for unit in units
    )


def string_unit(text: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": text}}


def plural_variations(forms: dict[str, str]) -> dict:
    return {"plural": {category: string_unit(forms[category]) for category in sorted(forms)}}


def marked_translated(localization: object) -> object:
    """A copy of `localization` with every string unit's state "translated"."""
    if isinstance(localization, dict):
        result = {}
        for key, value in localization.items():
            if key == "stringUnit" and isinstance(value, dict):
                result[key] = {"state": "translated", "value": value.get("value")}
            else:
                result[key] = marked_translated(value)
        return result
    return copy.deepcopy(localization)


def expand_translation(translation: object, source: object) -> dict:
    """The localization object a translation (full or shorthand) stands for."""
    if isinstance(translation, str):
        return string_unit(translation)
    if not isinstance(translation, dict):
        raise ValueError("a translation is a string or an object")
    if "stringUnit" in translation or "variations" in translation:
        return marked_translated(translation)
    if "plural" in translation:
        forms = translation["plural"]
        if not isinstance(forms, dict) or not all(isinstance(text, str) for text in forms.values()):
            raise ValueError("\"plural\" maps each CLDR category to its text")
        return {"variations": plural_variations(forms)}
    if "value" in translation:
        localization: dict = string_unit(translation["value"])
        substitutions = translation.get("substitutions") or {}
        if substitutions:
            source_substitutions = (
                source.get("substitutions") if isinstance(source, dict) else None
            ) or {}
            expanded = {}
            for name, forms in substitutions.items():
                forms = dict(forms)
                source_substitution = source_substitutions.get(name) or {}
                argument = forms.pop("argNum", source_substitution.get("argNum"))
                specifier = forms.pop("formatSpecifier", source_substitution.get("formatSpecifier"))
                if argument is None or specifier is None:
                    raise ValueError(f"substitution {name!r} needs argNum and formatSpecifier")
                forms = forms.get("plural", forms)
                expanded[name] = {
                    "argNum": argument,
                    "formatSpecifier": specifier,
                    "variations": plural_variations(forms),
                }
            localization["substitutions"] = expanded
        return localization
    raise ValueError("unrecognized translation shape")


def set_localization(entry: dict, language: str, localization: dict) -> None:
    localizations = entry.setdefault("localizations", {})
    localizations[language] = localization
    entry["localizations"] = dict(sorted(localizations.items()))


def entry_check_failures(
    key: str, source_language: str, source: object, language: str, localization: dict
) -> list[str]:
    catalog = {
        "sourceLanguage": source_language,
        "strings": {
            key: {
                "extractionState": "manual",
                "localizations": {source_language: source, language: localization},
            }
        },
    }
    return catalog_entry_failures(catalog, languages=(source_language, language))


# MARK: - Export


def export_document(root: Path, language: str, catalog_filter: str | None = None) -> dict:
    catalog_items: list[dict] = []
    paths = [resolve_catalog(root, catalog_filter)] if catalog_filter else catalog_paths(root)
    for path in paths:
        relative = path.relative_to(root).as_posix()
        catalog = load_catalog(path)
        source_language = catalog.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
        for key, entry in catalog.get("strings", {}).items():
            localizations = entry.get("localizations", {})
            if is_translated(localizations.get(language)):
                continue
            item: dict = {"catalog": relative, "key": key}
            if entry.get("comment"):
                item["comment"] = entry["comment"]
            item["source"] = localizations.get(source_language)
            references = {
                other: value
                for other, value in localizations.items()
                if other not in (source_language, language)
            }
            if references:
                item["references"] = references
            if language in localizations:
                item["current"] = localizations[language]
            item["translation"] = None
            catalog_items.append(item)

    info_plist_items: list[dict] = []
    if catalog_filter is None:
        for source_file in info_plist_source_files(root):
            target = source_file.parent.parent.name
            existing = read_info_plist_strings(info_plist_file(source_file, language))
            references = {
                other_file.parent.name.removesuffix(".lproj"): read_info_plist_strings(other_file)
                for other_file in sorted(source_file.parent.parent.glob("*.lproj/InfoPlist.strings"))
                if other_file.parent.name not in (
                    f"{DEFAULT_SOURCE_LANGUAGE}.lproj", f"{language}.lproj")
            }
            for key, source in read_info_plist_strings(source_file).items():
                if existing.get(key, "").strip():
                    continue
                item = {"target": target, "key": key, "source": source}
                item_references = {
                    other: values[key] for other, values in references.items() if key in values
                }
                if item_references:
                    item["references"] = item_references
                item["translation"] = None
                info_plist_items.append(item)

    return {
        "language": language,
        "sourceLanguage": DEFAULT_SOURCE_LANGUAGE,
        "pluralCategories": plural_categories_document(language),
        "catalogItems": catalog_items,
        "infoPlistItems": info_plist_items,
    }


def plural_categories_document(language: str) -> dict | None:
    """The CLDR plural categories `language` requires and allows, or None when
    the verifier declares none for it."""
    rules = plural_rules_for(language)
    return {"required": sorted(rules[0]), "allowed": sorted(rules[1])} if rules else None


def export_multi_document(
    root: Path, languages: Sequence[str], catalog_filter: str | None = None
) -> dict:
    """The export of several languages as one document.

    An item is listed when at least one language lacks it, and its
    `translations` object has a null slot for each language that does. Source
    text and comment are carried once per item; the other shipped languages'
    translations are left out.
    """
    catalog_items: list[dict] = []
    paths = [resolve_catalog(root, catalog_filter)] if catalog_filter else catalog_paths(root)
    for path in paths:
        relative = path.relative_to(root).as_posix()
        catalog = load_catalog(path)
        source_language = catalog.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
        for key, entry in catalog.get("strings", {}).items():
            localizations = entry.get("localizations", {})
            lacking = [
                language for language in languages
                if not is_translated(localizations.get(language))
            ]
            if not lacking:
                continue
            item: dict = {"catalog": relative, "key": key}
            if entry.get("comment"):
                item["comment"] = entry["comment"]
            item["source"] = localizations.get(source_language)
            current = {
                language: localizations[language]
                for language in lacking if language in localizations
            }
            if current:
                item["current"] = current
            item["translations"] = {language: None for language in lacking}
            catalog_items.append(item)

    info_plist_items: list[dict] = []
    if catalog_filter is None:
        for source_file in info_plist_source_files(root):
            target = source_file.parent.parent.name
            existing = {
                language: read_info_plist_strings(info_plist_file(source_file, language))
                for language in languages
            }
            for key, source in read_info_plist_strings(source_file).items():
                lacking = [
                    language for language in languages
                    if not existing[language].get(key, "").strip()
                ]
                if lacking:
                    info_plist_items.append({
                        "target": target,
                        "key": key,
                        "source": source,
                        "translations": {language: None for language in lacking},
                    })

    return {
        "languages": list(languages),
        "sourceLanguage": DEFAULT_SOURCE_LANGUAGE,
        "pluralCategories": {
            language: plural_categories_document(language) for language in languages
        },
        "catalogItems": catalog_items,
        "infoPlistItems": info_plist_items,
    }


def is_multi_language(document: dict) -> bool:
    """Whether an export document is the several-language form."""
    return "languages" in document


def windowed_document(document: dict, offset: int = 0, limit: int | None = None) -> dict:
    """`document` reduced to the catalog items `offset..<offset+limit`.

    The InfoPlist.strings items belong to the window that reaches the end of
    the catalog items, as they do in the text view.
    """
    items = document["catalogItems"]
    end = len(items) if limit is None else min(len(items), offset + limit)
    return {
        **document,
        "catalogItems": items[offset:end],
        "infoPlistItems": document["infoPlistItems"] if end == len(items) else [],
    }


def describe_localization(localization: object) -> str:
    """A localization on one line: its text, then its plural forms or its
    substitutions' plural forms, each as `category=text`."""
    if not isinstance(localization, dict):
        return "(none)"

    def forms(plural: object) -> str:
        if not isinstance(plural, dict):
            return ""
        return " | ".join(
            f"{category}={describe_localization(form)}" for category, form in sorted(plural.items()))

    parts = []
    unit = localization.get("stringUnit")
    if isinstance(unit, dict):
        parts.append(str(unit.get("value", "")))
    plural = (localization.get("variations") or {}).get("plural")
    if plural:
        parts.append(f"plural: {forms(plural)}")
    for name, substitution in sorted((localization.get("substitutions") or {}).items()):
        parts.append(f"%#@{name}@: {forms((substitution.get('variations') or {}).get('plural'))}")
    return "   ".join(parts) if parts else "(none)"


def lacks_line(document: dict, item: dict) -> str | None:
    """The "lacks" line of a several-language item that misses only some of
    the document's languages, or None when it misses all of them."""
    lacking = list(item["translations"])
    if len(lacking) == len(document["languages"]):
        return None
    return f"  lacks: {', '.join(lacking)}"


def document_text(document: dict, offset: int = 0, limit: int | None = None) -> str:
    """A translator's view of an export document: each catalog item in the
    window `offset..<offset+limit` with its comment and its source, then the
    InfoPlist.strings items when the window reaches the end of the catalog
    items. A single-language document also shows the other shipped languages'
    translations as references; a several-language one names the languages an
    item lacks when that is not all of them."""
    items = document["catalogItems"]
    end = len(items) if limit is None else min(len(items), offset + limit)
    source_language = document["sourceLanguage"]
    multi = is_multi_language(document)
    if multi:
        lines = [f"{', '.join(document['languages'])}: catalog items {offset}..<{end} of {len(items)}"]
        for language, rules in document["pluralCategories"].items():
            rules = rules or {}
            lines.append(
                f"  {language}: plural categories required {rules.get('required')}, "
                f"allowed {rules.get('allowed')}")
        lines.append("")
    else:
        language = document["language"]
        rules = document.get("pluralCategories") or {}
        lines = [
            f"{language}: catalog items {offset}..<{end} of {len(items)}; "
            f"plural categories required {rules.get('required')}, allowed {rules.get('allowed')}",
            "",
        ]
    for index in range(offset, end):
        item = items[index]
        lines.append(f"[{index}] {item['catalog']} :: {item['key']}")
        if item.get("comment"):
            lines.append(f"  comment: {item['comment']}")
        lines.append(f"  {source_language}: {describe_localization(item['source'])}")
        for other, reference in item.get("references", {}).items():
            lines.append(f"  {other}: {describe_localization(reference)}")
        if multi:
            if (lacking := lacks_line(document, item)) is not None:
                lines.append(lacking)
            for current_language, current in item.get("current", {}).items():
                lines.append(f"  current {current_language}: {describe_localization(current)}")
        elif "current" in item:
            lines.append(f"  current {language}: {describe_localization(item['current'])}")
    if end == len(items):
        for item in document["infoPlistItems"]:
            lines.append(f"[InfoPlist {item['target']}] {item['key']}")
            lines.append(f"  {source_language}: {item['source']}")
            for other, reference in item.get("references", {}).items():
                lines.append(f"  {other}: {reference}")
            if multi and (lacking := lacks_line(document, item)) is not None:
                lines.append(lacking)
    return "\n".join(lines) + "\n"


# MARK: - Import


def import_slots(
    root: Path,
    document: dict,
    languages: Sequence[str],
    slots_of: Callable[[dict], object],
    tagged: bool,
) -> list[str]:
    """Write the valid translation slots of a filled document's items.

    `slots_of(item)` returns an item's slots as a mapping of language to
    translation; a language an item has no slot for is left alone. `languages`
    are the languages the document covers: a slot for a language outside them,
    or one the verifier declares no plural categories for, is rejected. A
    problem about a single slot names its language when `tagged` is set, which
    a several-language document needs and a single-language one does not.
    Each catalog file and each InfoPlist.strings file is written as soon as its
    items are done. Returns the skipped items' reasons.
    """
    problems: list[str] = []
    usable: list[str] = []
    for language in languages:
        if plural_rules_for(language) is None:
            problems.append(
                f"{language!r} has no CLDR plural categories in verify_localization_catalog.py's "
                "PLURAL_CATEGORIES; declare them first")
        else:
            usable.append(language)
    if not usable:
        return problems

    def slot_label(label: str, language: str) -> str:
        return f"{label} {language}" if tagged else label

    def slots(item: dict, label: str) -> dict[str, object]:
        found = slots_of(item)
        if not isinstance(found, dict):
            problems.append(f"{label}: \"translations\" maps each language to its translation")
            return {}
        result: dict[str, object] = {}
        for language, translation in found.items():
            if language in usable:
                result[language] = translation
            elif language not in languages:
                problems.append(f"{label}: names {language}, which the document does not list")
        return result

    items_by_catalog: dict[str, list[dict]] = {}
    for item in document.get("catalogItems", []):
        items_by_catalog.setdefault(item["catalog"], []).append(item)
    for relative, items in items_by_catalog.items():
        path = root / relative
        if not path.is_file():
            problems.extend(f"{relative} {item['key']}: catalog not found" for item in items)
            continue
        catalog = load_catalog(path)
        source_language = catalog.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
        changed = False
        for item in items:
            label = f"{relative} {item['key']}"
            filled: dict[str, object] = {}
            for language, translation in slots(item, label).items():
                if translation is None:
                    problems.append(f"{slot_label(label, language)}: no translation")
                else:
                    filled[language] = translation
            if not filled:
                continue
            entry = catalog.get("strings", {}).get(item["key"])
            if entry is None:
                problems.append(f"{label}: the key is not in the catalog")
                continue
            source = entry.get("localizations", {}).get(source_language)
            if source != item.get("source"):
                problems.append(f"{label}: the source text changed since the export; export again")
                continue
            for language, translation in filled.items():
                try:
                    localization = expand_translation(translation, source)
                except ValueError as error:
                    problems.append(f"{slot_label(label, language)}: {error}")
                    continue
                failures = entry_check_failures(
                    item["key"], source_language, source, language, localization)
                if failures:
                    problems.extend(f"{relative}: {failure}" for failure in failures)
                    continue
                set_localization(entry, language, localization)
                changed = True
        if changed:
            write_catalog(path, catalog)

    items_by_target: dict[str, list[dict]] = {}
    for item in document.get("infoPlistItems", []):
        items_by_target.setdefault(item["target"], []).append(item)
    for target, items in items_by_target.items():
        source_file = (
            root / "Config" / "InfoPlist" / target / f"{DEFAULT_SOURCE_LANGUAGE}.lproj"
            / "InfoPlist.strings")
        if not source_file.is_file():
            problems.extend(f"InfoPlist {target} {item['key']}: target not found" for item in items)
            continue
        source_entries = read_info_plist_strings(source_file)
        values_by_language: dict[str, dict[str, str]] = {}
        changed_languages: list[str] = []
        for item in items:
            label = f"InfoPlist {target} {item['key']}"
            for language, translation in slots(item, label).items():
                slot = slot_label(label, language)
                if not isinstance(translation, str) or not translation.strip():
                    problems.append(f"{slot}: no translation")
                elif item["key"] not in source_entries:
                    problems.append(f"{slot}: the key is no longer in the source file")
                elif source_entries[item["key"]] != item.get("source"):
                    problems.append(f"{slot}: the source text changed since the export; export again")
                elif any(ord(character) < 0x20 for character in translation):
                    problems.append(f"{slot}: control characters are not allowed")
                else:
                    if language not in values_by_language:
                        values_by_language[language] = read_info_plist_strings(
                            info_plist_file(source_file, language))
                    values_by_language[language][item["key"]] = translation
                    if language not in changed_languages:
                        changed_languages.append(language)
        for language in changed_languages:
            values = values_by_language[language]
            write_info_plist_strings(
                info_plist_file(source_file, language),
                [(key, values[key]) for key in source_entries if key in values])
    return problems


def import_document(root: Path, language: str, document: dict) -> list[str]:
    """Write a filled single-language document's valid items; returns the
    skipped items' reasons."""
    return import_slots(
        root, document, [language], lambda item: {language: item.get("translation")},
        tagged=False)


def document_languages(document: dict) -> list[str]:
    """The languages a several-language document names, or when it names none,
    the languages its items have slots for, in order of appearance."""
    named = document.get("languages")
    if isinstance(named, list) and all(isinstance(language, str) for language in named):
        return list(dict.fromkeys(named))
    found: dict[str, None] = {}
    for item in [*document.get("catalogItems", []), *document.get("infoPlistItems", [])]:
        translations = item.get("translations")
        if isinstance(translations, dict):
            found.update(dict.fromkeys(translations))
    return list(found)


def import_multi_document(root: Path, document: dict) -> list[str]:
    """Write every language of a filled several-language document; returns the
    skipped slots' reasons. Each slot is checked on its own, so one language of
    an item may be written while another is reported."""
    return import_slots(
        root, document, document_languages(document),
        lambda item: item.get("translations"), tagged=True)


def apply_document(root: Path, catalog: str, translations: dict[str, object]) -> dict:
    """An import document carrying `translations` (key to translation) for one catalog.

    Each item takes its source text from the catalog as it is now, so the
    document applies to the current catalog whether or not the language
    already has the key. A key the catalog lacks gets a null source, and
    `import_document` reports it.
    """
    path = resolve_catalog(root, catalog)
    relative = path.relative_to(root).as_posix()
    contents = load_catalog(path)
    source_language = contents.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
    strings = contents.get("strings", {})
    items = []
    for key, translation in translations.items():
        entry = strings.get(key) or {}
        items.append({
            "catalog": relative,
            "key": key,
            "source": entry.get("localizations", {}).get(source_language),
            "translation": translation,
        })
    return {"catalogItems": items, "infoPlistItems": []}


def apply_multi_document(
    root: Path, catalog: str, languages: Sequence[str], translations: dict[str, object]
) -> dict:
    """A several-language import document carrying `translations` for one catalog.

    `translations` maps each key to an object of language to translation. As
    in `apply_document`, each item takes its source text from the catalog as it
    is now, and a language an item leaves out is not touched.
    """
    path = resolve_catalog(root, catalog)
    relative = path.relative_to(root).as_posix()
    contents = load_catalog(path)
    source_language = contents.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
    strings = contents.get("strings", {})
    items = []
    for key, by_language in translations.items():
        entry = strings.get(key) or {}
        items.append({
            "catalog": relative,
            "key": key,
            "source": entry.get("localizations", {}).get(source_language),
            "translations": by_language,
        })
    return {"languages": list(languages), "catalogItems": items, "infoPlistItems": []}


def checkout_entries_by_key(other_root: Path) -> dict[str, list[dict]]:
    """Every catalog entry of another checkout, grouped by key across catalogs."""
    entries: dict[str, list[dict]] = {}
    for path in catalog_paths(other_root):
        for key, entry in load_catalog(path).get("strings", {}).items():
            entries.setdefault(key, []).append(entry)
    return entries


def moved_key_translation(
    candidates: list[dict], language: str, source_language: str, source: object
) -> object | None:
    """The one translation the other checkout's catalogs agree on for a key that
    is not in the matching catalog there, or None when none or several do."""
    translations = []
    for entry in candidates:
        localizations = entry.get("localizations", {})
        candidate = localizations.get(language)
        if is_translated(candidate) and localizations.get(source_language) == source:
            if candidate not in translations:
                translations.append(candidate)
    return translations[0] if len(translations) == 1 else None


def import_from_checkout(root: Path, language: str, other_root: Path) -> tuple[int, list[str]]:
    """Copy translations whose source matches; returns (copied, still missing).

    An entry takes the translation under its key in the same catalog of
    `other_root`. When that catalog lacks the key (it moved between catalogs on
    one side), the translation comes from the other catalogs holding the key
    with the same source text, provided they agree on one."""
    copied = 0
    missing: list[str] = []
    entries_by_key = checkout_entries_by_key(other_root)
    for path in catalog_paths(root):
        relative = path.relative_to(root).as_posix()
        other_path = other_root / relative
        other_strings = load_catalog(other_path).get("strings", {}) if other_path.is_file() else {}
        catalog = load_catalog(path)
        source_language = catalog.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
        changed = False
        for key, entry in catalog.get("strings", {}).items():
            localizations = entry.get("localizations", {})
            source = localizations.get(source_language)
            if key in other_strings:
                other_localizations = other_strings[key].get("localizations", {})
                candidate = other_localizations.get(language)
                if not (is_translated(candidate)
                        and other_localizations.get(source_language) == source):
                    candidate = None
            else:
                candidate = moved_key_translation(
                    entries_by_key.get(key, []), language, source_language, source)
            if candidate is not None:
                if localizations.get(language) != candidate:
                    set_localization(entry, language, copy.deepcopy(candidate))
                    changed = True
                    copied += 1
            elif not is_translated(localizations.get(language)):
                missing.append(f"{relative} {key}")
        if changed:
            write_catalog(path, catalog)

    for source_file in info_plist_source_files(root):
        target = source_file.parent.parent.name
        relative_source = source_file.relative_to(root)
        other_source = read_info_plist_strings(other_root / relative_source)
        other_values = read_info_plist_strings(
            info_plist_file(other_root / relative_source, language))
        source_entries = read_info_plist_strings(source_file)
        target_file = info_plist_file(source_file, language)
        values = read_info_plist_strings(target_file)
        changed = False
        for key, source in source_entries.items():
            candidate = other_values.get(key, "")
            if candidate.strip() and other_source.get(key) == source:
                if values.get(key) != candidate:
                    values[key] = candidate
                    changed = True
                    copied += 1
            elif not values.get(key, "").strip():
                missing.append(f"InfoPlist {target} {key}")
        if changed:
            write_info_plist_strings(
                target_file,
                [(key, values[key]) for key in source_entries if key in values])
    return copied, missing


# MARK: - Source entries


def shipped_languages(root: Path) -> tuple[str, ...]:
    """The languages the catalogs under `root` carry, which every entry needs."""
    return required_languages([load_catalog(path) for path in catalog_paths(root)])


def with_key_inserted(strings: dict, key: str, entry: dict) -> dict:
    """`strings` with `key` added before the first key that sorts after it."""
    items = list(strings.items())
    index = next((i for i, (existing, _) in enumerate(items) if existing > key), len(items))
    items.insert(index, (key, entry))
    return dict(items)


def define_entries(root: Path, catalog: str, specs: dict[str, object]) -> list[str]:
    """Create or replace whole entries of one catalog; returns the rejected specs' reasons.

    Each spec carries an optional `comment` and the text of every shipped
    language in the shapes `expand_translation` accepts; the source language's
    text is expanded on its own and the others against it. Valid specs are
    written even when others are rejected.
    """
    path = resolve_catalog(root, catalog)
    relative = path.relative_to(root).as_posix()
    contents = load_catalog(path)
    source_language = contents.get("sourceLanguage", DEFAULT_SOURCE_LANGUAGE)
    languages = shipped_languages(root)
    strings = contents.setdefault("strings", {})
    problems: list[str] = []
    changed = False
    for key, spec in specs.items():
        label = f"{relative} {key}"
        if not isinstance(spec, dict):
            problems.append(f"{label}: a spec is an object of an optional comment and per-language text")
            continue
        texts = {name: value for name, value in spec.items() if name != "comment"}
        missing = [language for language in languages if language not in texts]
        unknown = sorted(set(texts) - set(languages))
        if missing or unknown:
            reasons = []
            if missing:
                reasons.append(f"lacks {missing}")
            if unknown:
                reasons.append(f"names {unknown}, which the catalogs do not ship")
            problems.append(f"{label}: the spec {' and '.join(reasons)}")
            continue
        try:
            source = expand_translation(texts[source_language], None)
            localizations = {
                language: source if language == source_language
                else expand_translation(texts[language], source)
                for language in languages
            }
        except ValueError as error:
            problems.append(f"{label}: {error}")
            continue
        entry: dict = {}
        if spec.get("comment"):
            entry["comment"] = spec["comment"]
        entry["extractionState"] = "manual"
        entry["localizations"] = dict(sorted(localizations.items()))
        failures = catalog_entry_failures(
            {"sourceLanguage": source_language, "strings": {key: entry}}, languages=languages)
        if failures:
            problems.extend(f"{relative}: {failure}" for failure in failures)
            continue
        if key in strings:
            strings[key] = entry
        else:
            strings = with_key_inserted(strings, key, entry)
            contents["strings"] = strings
        changed = True
    if changed:
        write_catalog(path, contents)
    return problems


def remove_entries(root: Path, catalog: str, keys: list[str]) -> list[str]:
    """Delete `keys` from one catalog; returns a reason for each key it lacks."""
    path = resolve_catalog(root, catalog)
    relative = path.relative_to(root).as_posix()
    contents = load_catalog(path)
    strings = contents.get("strings", {})
    problems = [f"{relative} {key}: the key is not in the catalog" for key in keys if key not in strings]
    present = [key for key in keys if key in strings]
    for key in present:
        del strings[key]
    if present:
        write_catalog(path, contents)
    return problems


# MARK: - Command line


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    export = commands.add_parser("export", help="list the entries that lack a language")
    export.add_argument(
        "--language", action="append", required=True,
        help="the language to export; repeat it to export several languages in one document")
    export.add_argument("--catalog", help="limit the export to one catalog (a path)")
    export.add_argument("--output", type=Path, help="write the document here instead of stdout")
    export.add_argument(
        "--text", action="store_true",
        help="print a readable listing for translators instead of the JSON document")
    export.add_argument("--offset", type=int, default=0, help="the first catalog item to list")
    export.add_argument("--limit", type=int, help="how many catalog items to list")

    importing = commands.add_parser("import", help="write translations into the catalogs")
    importing.add_argument(
        "--language", action="append",
        help="the document's language, or each language to copy with --from-checkout; "
        "a document names its own language or languages when this is left out")
    source = importing.add_mutually_exclusive_group(required=True)
    source.add_argument("document", nargs="?", type=Path, help="a filled export document")
    source.add_argument(
        "--from-checkout", type=Path,
        help="another checkout (a localization branch's worktree) to copy translations from")

    applying = commands.add_parser("apply", help="write a key-to-translation map into one catalog")
    applying.add_argument(
        "--language", action="append", required=True,
        help="the language the map translates into; repeat it for a map of several languages")
    applying.add_argument("--catalog", required=True, help="the catalog the keys belong to (a path)")
    applying.add_argument(
        "translations", type=Path,
        help="a JSON object mapping each key to its translation, or with several --language "
        "options to an object of language to translation")

    defining = commands.add_parser(
        "define", help="create or replace entries in every shipped language")
    defining.add_argument("--catalog", required=True, help="the catalog the keys belong to (a path)")
    defining.add_argument(
        "specs", type=Path,
        help="a JSON object mapping each key to its comment and per-language text")

    removing = commands.add_parser("remove", help="delete entries from one catalog")
    removing.add_argument("--catalog", required=True, help="the catalog the keys belong to (a path)")
    removing.add_argument("keys", nargs="+", help="the keys to delete")

    args = parser.parse_args(argv)
    if hasattr(args, "language"):
        args.language = list(dict.fromkeys(args.language or []))
    if args.command == "import" and args.from_checkout and not args.language:
        parser.error("--from-checkout needs at least one --language")
    return args


def entry_count(count: int) -> str:
    return f"{count} entry" if count == 1 else f"{count} entries"


def report(problems: list[str], success: str, action: str = "imported") -> int:
    if problems:
        print(f"{len(problems)} item(s) were not {action}:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    print(success)
    return 0


def import_file(root: Path, languages: list[str], document: dict) -> int:
    """Import a filled export document of either form; `languages` are the
    ones named on the command line, which may be empty."""
    if is_multi_language(document):
        named = document_languages(document)
        if languages and sorted(languages) != sorted(named):
            print(f"the document is for {named}, not {languages}", file=sys.stderr)
            return 1
        return report(
            import_multi_document(root, document), f"imported every item in {', '.join(named)}")
    if len(languages) > 1:
        print(
            f"the document is for {document.get('language')!r}, not {languages}", file=sys.stderr)
        return 1
    language = languages[0] if languages else document.get("language")
    if not isinstance(language, str):
        print("the document names no language; pass --language", file=sys.stderr)
        return 1
    if document.get("language") not in (None, language):
        print(f"the document is for {document['language']!r}, not {language!r}", file=sys.stderr)
        return 1
    return report(import_document(root, language, document), f"imported every {language} item")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.command == "export":
        if len(args.language) == 1:
            document = export_document(ROOT, args.language[0], args.catalog)
            lacking = args.language[0]
        else:
            document = export_multi_document(ROOT, args.language, args.catalog)
            lacking = f"at least one of {', '.join(args.language)}"
        if args.text:
            text = document_text(document, args.offset, args.limit)
        else:
            text = json.dumps(
                windowed_document(document, args.offset, args.limit),
                indent=2, ensure_ascii=False) + "\n"
        if args.output:
            args.output.write_text(text, encoding="utf-8")
            print(
                f"{len(document['catalogItems'])} catalog entries and "
                f"{len(document['infoPlistItems'])} InfoPlist keys lack {lacking}",
                file=sys.stderr)
        else:
            sys.stdout.write(text)
        return 0

    if args.command == "define":
        specs = json.loads(args.specs.read_text(encoding="utf-8"))
        if not isinstance(specs, dict):
            print("the specs file is a JSON object mapping each key to its spec", file=sys.stderr)
            return 1
        return report(
            define_entries(ROOT, args.catalog, specs), f"defined {entry_count(len(specs))}",
            action="defined")

    if args.command == "remove":
        return report(
            remove_entries(ROOT, args.catalog, args.keys), f"removed {entry_count(len(args.keys))}",
            action="removed")

    if args.command == "apply":
        translations = json.loads(args.translations.read_text(encoding="utf-8"))
        if len(args.language) == 1:
            if not isinstance(translations, dict):
                print("the translations file is a JSON object mapping each key to its translation",
                      file=sys.stderr)
                return 1
            document = apply_document(ROOT, args.catalog, translations)
            return report(
                import_document(ROOT, args.language[0], document),
                f"applied all {len(translations)} {args.language[0]} translations")
        if not isinstance(translations, dict):
            print("the translations file is a JSON object mapping each key to an object of "
                  "language to translation", file=sys.stderr)
            return 1
        document = apply_multi_document(ROOT, args.catalog, args.language, translations)
        return report(
            import_multi_document(ROOT, document),
            f"applied all {entry_count(len(translations))} in {', '.join(args.language)}")

    if args.from_checkout:
        other_root = checkout_app_root(args.from_checkout)
        for language in args.language:
            copied, missing = import_from_checkout(ROOT, language, other_root)
            print(f"copied {copied} {language} translations")
            if missing:
                print(f"{len(missing)} entries still lack {language}:")
                for label in missing:
                    print(f"- {label}")
        return 0

    return import_file(ROOT, args.language, json.loads(args.document.read_text(encoding="utf-8")))


if __name__ == "__main__":
    raise SystemExit(main())
