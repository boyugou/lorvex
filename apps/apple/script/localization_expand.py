#!/usr/bin/env python3
"""Expand the Apple String Catalogs to additional languages.

The Apple app and the Tauri app share product semantics, and the Tauri tree
ships professionally-maintained locale catalogs for ~30 languages. This tool
seeds the Apple `.xcstrings` catalogs from those translations by *exact English
source match*, so adding a language is mostly free where the two apps say the
same thing, and only genuinely app-specific strings need fresh translation.

Subcommands
-----------
seed   Fill target-language entries from Tauri where the English source matches
       exactly and carries no `%` format placeholder (placeholder strings are
       left as gaps so the Apple `%@`/`%lld` tokens are never crossed with
       Tauri's `{{var}}` style). Dry-run unless `--write`.

gaps   Emit the still-missing (catalog, key, english, [languages]) set as JSON
       for translation (e.g. by subagents).

translation-pack
       Emit one JSON artifact containing the remaining `.xcstrings` and
       InfoPlist.strings gaps for the current non-RTL expansion set.

apply-pack
       Validate and apply a combined translation response. The response can
       either be compact `{english:{lang:value}}` / `{target:{key:{lang:value}}}`
       tables or the original translation-pack shape with nested `translations`.

The verifier (`verify_localization_catalog.py`) enforces parity, placeholder
match, and `state: translated` afterwards, so this tool only has to produce
well-formed entries; correctness is gated downstream.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_ROOT = ROOT / "Config"
SOURCE_LANGUAGE = "en"

# Remaining non-RTL expansion set after the landed 13-language Apple baseline
# (de/en/es/fr/it/ja/ko/pl/pt/ru/tr/zh-Hans/zh-Hant). Tauri ships all of these.
DEFAULT_TARGET_LANGUAGES = [
    "hi",
    "id",
    "vi",
    "uk",
    "nl",
    "th",
    "ro",
    "ms",
    "bn",
    "el",
    "ta",
    "te",
    "mr",
    "ml",
]

# Map an Apple target language code to the Tauri locale file stem. Tauri uses
# `zh` for Simplified and `zh-Hant` for Traditional.
APPLE_TO_TAURI_LANG = {
    "zh-Hans": "zh",
    "zh-Hant": "zh-Hant",
}
INFO_PLIST_RESOURCE_TARGETS = [
    "LorvexFocusWidgetExtension",
    "LorvexMobileApp",
    "LorvexVisionApp",
    "LorvexWatchApp",
    "LorvexWatchComplication",
]


def tauri_locale_candidates() -> list[Path]:
    env_path = os.environ.get("LORVEX_TAURI_LOCALES")
    candidates: list[Path] = []
    if env_path:
        candidates.append(Path(env_path).expanduser())
    candidates.extend(
        [
            ROOT.parent / "tauri" / "app" / "src" / "locales",
            ROOT.parents[3] / "lorvex_original" / "app" / "src" / "locales",
        ]
    )
    return candidates


def tauri_locales() -> Path:
    for candidate in tauri_locale_candidates():
        if (candidate / "en.json").is_file():
            return candidate
    searched = ", ".join(str(path) for path in tauri_locale_candidates())
    raise FileNotFoundError(
        "Tauri locale catalog not found. Set LORVEX_TAURI_LOCALES or provide one of: "
        f"{searched}"
    )


def apple_catalogs() -> list[Path]:
    return sorted(ROOT.glob("Sources/*/Resources/Localizable.xcstrings"))


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_catalog(path: Path, data: dict) -> None:
    # Preserve the catalog's existing key order (the files are not Xcode-sorted)
    # so a language expansion shows as pure additions rather than a full reorder.
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=False)
    path.write_text(text + "\n", encoding="utf-8")


def escaped_strings_value(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def parse_strings_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    entries: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if "=" not in stripped or not stripped.endswith(";"):
            continue
        key_part, value_part = stripped[:-1].split("=", 1)
        try:
            key = json.loads(key_part.strip())
            value = json.loads(value_part.strip())
        except json.JSONDecodeError:
            continue
        if isinstance(key, str) and isinstance(value, str):
            entries[key] = value
    return entries


def write_strings_file(path: Path, entries: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"{escaped_strings_value(key)} = {escaped_strings_value(value)};"
        for key, value in sorted(entries.items())
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def has_placeholder(text: str) -> bool:
    """True if the string carries a printf-style format placeholder.

    Conservative: any `%` (other than an escaped `%%`) disqualifies the string
    from English-match reuse so Apple's `%@`/`%lld` tokens are never replaced by
    a translation written for a different placeholder syntax.
    """
    return "%" in text.replace("%%", "")


def format_placeholders(text: str) -> list[str]:
    placeholders: list[tuple[int | None, str]] = []
    index = 0
    length = len(text)
    pattern = re.compile(
        r"%(?:(\d+)\$)?"
        r"(?:[-+#0 ]*\d*(?:\.\d+)?)?"
        r"((?:hh|h|ll|l|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp])"
    )

    while index < length:
        if text[index] != "%":
            index += 1
            continue
        if index + 1 < length and text[index + 1] == "%":
            index += 2
            continue
        match = pattern.match(text, index)
        if not match:
            index += 1
            continue
        position = int(match.group(1)) if match.group(1) else None
        placeholders.append((position, match.group(2)))
        index = match.end()

    if any(position is not None for position, _ in placeholders):
        unpositioned_start = len(placeholders) + 1
        normalized = [
            (position if position is not None else unpositioned_start + offset, token)
            for offset, (position, token) in enumerate(placeholders)
        ]
        return [token for _, token in sorted(normalized, key=lambda item: item[0])]
    return [token for _, token in placeholders]


def source_value(entry: dict) -> str | None:
    unit = entry.get("localizations", {}).get(SOURCE_LANGUAGE, {})
    string_unit = unit.get("stringUnit", {}) if isinstance(unit, dict) else {}
    value = string_unit.get("value")
    return value if isinstance(value, str) and value.strip() else None


def build_tauri_index(languages: list[str]) -> dict[str, dict[str, str]]:
    """english_value -> {apple_lang: translation}, excluding ambiguous mappings.

    A given English string is only reusable for a language when every Tauri key
    with that English source agrees on a single non-English translation for the
    language; conflicting translations (context-dependent) are dropped so reuse
    never guesses wrong.
    """
    locales = tauri_locales()
    en = load_json(locales / "en.json")
    # english -> lang -> set(distinct translations)
    candidates: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    lang_catalogs: dict[str, dict[str, str]] = {}
    for apple_lang in languages:
        stem = APPLE_TO_TAURI_LANG.get(apple_lang, apple_lang)
        path = locales / f"{stem}.json"
        lang_catalogs[apple_lang] = load_json(path) if path.is_file() else {}

    for key, en_value in en.items():
        if not isinstance(en_value, str) or has_placeholder(en_value):
            continue
        for apple_lang, catalog in lang_catalogs.items():
            translated = catalog.get(key)
            if isinstance(translated, str) and translated.strip() and translated != en_value:
                candidates[en_value][apple_lang].add(translated)

    index: dict[str, dict[str, str]] = {}
    for en_value, by_lang in candidates.items():
        resolved = {lang: next(iter(vals)) for lang, vals in by_lang.items() if len(vals) == 1}
        if resolved:
            index[en_value] = resolved
    return index


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def seed(languages: list[str], write: bool) -> dict:
    index = build_tauri_index(languages)
    report: dict[str, dict] = {}
    for catalog_path in apple_catalogs():
        data = load_json(catalog_path)
        strings = data.get("strings", {})
        reused = {lang: 0 for lang in languages}
        gaps = {lang: 0 for lang in languages}
        total = 0
        changed = False
        for entry in strings.values():
            if not isinstance(entry, dict):
                continue
            src = source_value(entry)
            if src is None:
                continue
            total += 1
            localizations = entry.setdefault("localizations", {})
            reuse = index.get(src, {})
            for lang in languages:
                if lang in localizations:
                    continue
                if lang in reuse:
                    localizations[lang] = make_unit(reuse[lang])
                    reused[lang] += 1
                    changed = True
                else:
                    gaps[lang] += 1
        rel = str(catalog_path.relative_to(ROOT))
        report[rel] = {"total": total, "reused": reused, "gaps": gaps}
        if write and changed:
            dump_catalog(catalog_path, data)
    return report


def emit_gaps(languages: list[str], out_path: Path) -> dict:
    """Write the per-catalog keys still missing any target language."""
    payload: dict[str, dict] = {}
    counts: dict[str, int] = {lang: 0 for lang in languages}
    for catalog_path in apple_catalogs():
        data = load_json(catalog_path)
        strings = data.get("strings", {})
        rel = str(catalog_path.relative_to(ROOT))
        entries: dict[str, dict] = {}
        for key, entry in strings.items():
            if not isinstance(entry, dict):
                continue
            src = source_value(entry)
            if src is None:
                continue
            localizations = entry.get("localizations", {})
            missing = [lang for lang in languages if lang not in localizations]
            if missing:
                # Carry existing translations (notably zh-Hans) as reference so a
                # translator/subagent has parallel context, and zh-Hant can be
                # derived from the Simplified entry rather than re-translated cold.
                ref = {}
                for ref_lang in ("en", "zh-Hans"):
                    unit = localizations.get(ref_lang, {})
                    su = unit.get("stringUnit", {}) if isinstance(unit, dict) else {}
                    if isinstance(su.get("value"), str):
                        ref[ref_lang] = su["value"]
                entries[key] = {"en": src, "ref": ref, "missing": missing}
                for lang in missing:
                    counts[lang] += 1
        if entries:
            payload[rel] = entries
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return counts


def emit_unique_gaps(languages: list[str], out_path: Path) -> int:
    """Emit the *deduplicated* English strings needing translation.

    Many identical English strings recur across keys and catalogs; translating
    each unique string once (into all languages that any occurrence is missing)
    avoids redundant work. Output: list of {en, zhHans, langs:[...]}.
    """
    by_en: dict[str, dict] = {}
    for catalog_path in apple_catalogs():
        strings = load_json(catalog_path).get("strings", {})
        for entry in strings.values():
            if not isinstance(entry, dict):
                continue
            src = source_value(entry)
            if src is None:
                continue
            localizations = entry.get("localizations", {})
            missing = [lang for lang in languages if lang not in localizations]
            if not missing:
                continue
            slot = by_en.setdefault(src, {"en": src, "zhHans": None, "langs": set()})
            slot["langs"].update(missing)
            if slot["zhHans"] is None:
                unit = localizations.get("zh-Hans", {})
                su = unit.get("stringUnit", {}) if isinstance(unit, dict) else {}
                if isinstance(su.get("value"), str):
                    slot["zhHans"] = su["value"]
    payload = [
        {"en": s["en"], "zhHans": s["zhHans"], "langs": sorted(s["langs"])}
        for s in sorted(by_en.values(), key=lambda s: s["en"])
    ]
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(payload)


def unique_catalog_gaps(languages: list[str]) -> list[dict]:
    """Return deduplicated `.xcstrings` gaps without writing a side file."""
    by_en: dict[str, dict] = {}
    for catalog_path in apple_catalogs():
        strings = load_json(catalog_path).get("strings", {})
        rel = str(catalog_path.relative_to(ROOT))
        for key, entry in strings.items():
            if not isinstance(entry, dict):
                continue
            src = source_value(entry)
            if src is None:
                continue
            localizations = entry.get("localizations", {})
            missing = [lang for lang in languages if lang not in localizations]
            if not missing:
                continue
            slot = by_en.setdefault(
                src,
                {
                    "en": src,
                    "zhHans": None,
                    "langs": set(),
                    "occurrences": [],
                },
            )
            slot["langs"].update(missing)
            slot["occurrences"].append({"catalog": rel, "key": key})
            if slot["zhHans"] is None:
                unit = localizations.get("zh-Hans", {})
                su = unit.get("stringUnit", {}) if isinstance(unit, dict) else {}
                if isinstance(su.get("value"), str):
                    slot["zhHans"] = su["value"]
    return [
        {
            "en": slot["en"],
            "zhHans": slot["zhHans"],
            "langs": sorted(slot["langs"]),
            "occurrences": slot["occurrences"],
        }
        for slot in sorted(by_en.values(), key=lambda item: item["en"])
    ]


def normalize_english_translations(table: object) -> dict | None:
    if isinstance(table, list):
        normalized: dict[str, dict] = {}
        for row in table:
            if not isinstance(row, dict):
                return None
            english = row.get("en")
            if not isinstance(english, str):
                return None
            normalized[english] = row.get("translations", {})
        return normalized
    return table if isinstance(table, dict) else None


def english_translation_requirements(table: object) -> dict[str, set[str]]:
    if not isinstance(table, list):
        return {}

    requirements: dict[str, set[str]] = {}
    for row in table:
        if not isinstance(row, dict):
            continue
        english = row.get("en")
        langs = row.get("langs")
        if not isinstance(english, str) or not isinstance(langs, list):
            continue
        required = {lang for lang in langs if isinstance(lang, str) and lang.strip()}
        if required:
            requirements[english] = required
    return requirements


def catalog_pack_metadata_failures(table: object) -> list[str]:
    if not isinstance(table, list):
        return []

    failures: list[str] = []
    for row in table:
        if not isinstance(row, dict):
            continue
        english = row.get("en")
        label = repr(english) if isinstance(english, str) else "catalog row"
        if "langs" in row:
            langs = row.get("langs")
            if not isinstance(langs, list) or not langs:
                failures.append(f"{label} langs metadata must be a non-empty array")
            elif not all(isinstance(lang, str) and lang.strip() for lang in langs):
                failures.append(f"{label} langs metadata must contain only non-empty strings")
            elif len(set(langs)) != len(langs):
                failures.append(f"{label} langs metadata contains duplicate languages")
        if "occurrences" in row:
            occurrences = row.get("occurrences")
            if not isinstance(occurrences, list) or not occurrences:
                failures.append(f"{label} occurrences metadata must be a non-empty array")
                continue
            for occurrence in occurrences:
                if not isinstance(occurrence, dict):
                    failures.append(f"{label} contains an invalid catalog occurrence")
                    continue
                catalog = occurrence.get("catalog")
                key = occurrence.get("key")
                if not isinstance(catalog, str) or not catalog.strip() or not isinstance(key, str) or not key.strip():
                    failures.append(f"{label} contains an invalid catalog occurrence")
                    continue
                path = ROOT / catalog
                try:
                    path.resolve().relative_to(ROOT.resolve())
                except ValueError:
                    failures.append(f"{label} catalog occurrence path escapes the Apple root: {catalog!r}")
    return failures


def validate_catalog_pack_sources(table: object) -> list[str]:
    if not isinstance(table, list):
        return []

    failures: list[str] = []
    catalog_cache: dict[str, dict] = {}
    for row in table:
        if not isinstance(row, dict):
            continue
        english = row.get("en")
        occurrences = row.get("occurrences")
        required_languages = english_translation_requirements([row]).get(english, set())
        if not isinstance(english, str) or not isinstance(occurrences, list):
            continue
        if not occurrences:
            failures.append(f"{english!r} has no catalog occurrences")
            continue
        for occurrence in occurrences:
            if not isinstance(occurrence, dict):
                failures.append(f"{english!r} contains an invalid catalog occurrence")
                continue
            catalog = occurrence.get("catalog")
            key = occurrence.get("key")
            if not isinstance(catalog, str) or not catalog.strip() or not isinstance(key, str) or not key.strip():
                failures.append(f"{english!r} contains an invalid catalog occurrence")
                continue
            path = ROOT / catalog
            try:
                path.resolve().relative_to(ROOT.resolve())
            except ValueError:
                failures.append(f"{english!r} catalog occurrence path escapes the Apple root: {catalog!r}")
                continue
            if catalog not in catalog_cache:
                if not path.is_file():
                    failures.append(f"{english!r} catalog occurrence missing file {catalog!r}")
                    catalog_cache[catalog] = {}
                    continue
                catalog_cache[catalog] = load_json(path)
            strings = catalog_cache[catalog].get("strings", {})
            entry = strings.get(key) if isinstance(strings, dict) else None
            if not isinstance(entry, dict):
                failures.append(f"{english!r} catalog occurrence missing key {catalog!r} {key!r}")
                continue
            current_english = source_value(entry)
            if current_english != english:
                failures.append(
                    f"{english!r} catalog occurrence {catalog!r} {key!r} source mismatch: {current_english!r}"
                )
                continue
            localizations = entry.get("localizations", {})
            if isinstance(localizations, dict):
                already_present = sorted(lang for lang in required_languages if lang in localizations)
                if already_present:
                    failures.append(
                        f"{english!r} catalog occurrence {catalog!r} {key!r} already has translations for "
                        f"{already_present}"
                    )
    return failures


def apply_english_table(table: object) -> dict:
    """Apply {en_value: {lang: translation}} to every matching catalog entry.

    For each catalog entry whose English source matches a provided key and whose
    target language is still missing, fill it. Placeholder/parity correctness is
    gated by the verifier afterwards.
    """
    table = normalize_english_translations(table)
    if table is None:
        raise ValueError("catalog translation payload must be an object or list")

    applied: dict[str, int] = {}
    for catalog_path in apple_catalogs():
        data = load_json(catalog_path)
        strings = data.get("strings", {})
        count = 0
        for entry in strings.values():
            if not isinstance(entry, dict):
                continue
            src = source_value(entry)
            if src is None or src not in table:
                continue
            localizations = entry.setdefault("localizations", {})
            for lang, value in table[src].items():
                if lang not in localizations and isinstance(value, str) and value.strip():
                    localizations[lang] = make_unit(value)
                    count += 1
        if count:
            dump_catalog(catalog_path, data)
        applied[str(catalog_path.relative_to(ROOT))] = count
    return applied


def apply_by_english(in_path: Path) -> dict:
    table = json.loads(in_path.read_text(encoding="utf-8"))
    return apply_english_table(table)


def apply_translations(in_path: Path) -> dict:
    """Apply {catalog_rel: {key: {lang: value}}} into the catalogs."""
    translations = json.loads(in_path.read_text(encoding="utf-8"))
    applied: dict[str, int] = {}
    for rel, by_key in translations.items():
        catalog_path = ROOT / rel
        data = load_json(catalog_path)
        strings = data.get("strings", {})
        count = 0
        for key, by_lang in by_key.items():
            entry = strings.get(key)
            if not isinstance(entry, dict):
                continue
            localizations = entry.setdefault("localizations", {})
            for lang, value in by_lang.items():
                if isinstance(value, str) and value.strip():
                    localizations[lang] = make_unit(value)
                    count += 1
        if count:
            dump_catalog(catalog_path, data)
        applied[rel] = count
    return applied


def emit_info_plist_gaps(
    languages: list[str],
    out_path: Path,
    config_root: Path = CONFIG_ROOT,
) -> dict[str, dict[str, int]]:
    """Emit missing per-target InfoPlist.strings entries for target languages."""
    payload: dict[str, dict[str, dict]] = {}
    counts: dict[str, dict[str, int]] = {}

    for target in INFO_PLIST_RESOURCE_TARGETS:
        source_path = config_root / "InfoPlist" / target / f"{SOURCE_LANGUAGE}.lproj" / "InfoPlist.strings"
        source_entries = parse_strings_file(source_path)
        target_entries: dict[str, dict] = {}
        target_counts = {lang: 0 for lang in languages}

        for key, source in source_entries.items():
            missing: list[str] = []
            for lang in languages:
                lang_path = config_root / "InfoPlist" / target / f"{lang}.lproj" / "InfoPlist.strings"
                localized = parse_strings_file(lang_path).get(key, "").strip()
                if not localized:
                    missing.append(lang)
                    target_counts[lang] += 1
            if missing:
                target_entries[key] = {"en": source, "missing": missing}

        if target_entries:
            payload[target] = target_entries
        counts[target] = target_counts

    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return counts


def info_plist_gap_payload(
    languages: list[str],
    config_root: Path = CONFIG_ROOT,
) -> dict[str, dict[str, dict]]:
    payload: dict[str, dict[str, dict]] = {}
    for target in INFO_PLIST_RESOURCE_TARGETS:
        source_path = config_root / "InfoPlist" / target / f"{SOURCE_LANGUAGE}.lproj" / "InfoPlist.strings"
        source_entries = parse_strings_file(source_path)
        target_entries: dict[str, dict] = {}
        for key, source in source_entries.items():
            missing: list[str] = []
            for lang in languages:
                lang_path = config_root / "InfoPlist" / target / f"{lang}.lproj" / "InfoPlist.strings"
                localized = parse_strings_file(lang_path).get(key, "").strip()
                if not localized:
                    missing.append(lang)
            if missing:
                target_entries[key] = {"en": source, "missing": missing}
        if target_entries:
            payload[target] = target_entries
    return payload


def emit_translation_pack(
    languages: list[str],
    out_path: Path,
    config_root: Path = CONFIG_ROOT,
) -> dict[str, int]:
    catalog_gaps = unique_catalog_gaps(languages)
    info_plist_gaps = info_plist_gap_payload(languages, config_root=config_root)
    payload = {
        "languages": languages,
        "instructions": [
            "Return translations as JSON only.",
            "Preferred response shape: keep catalogStrings rows and InfoPlist entries intact, then add a translations object to each item.",
            "Compact fallback is also accepted: catalogStrings as {english: {language: translation}} and infoPlistStrings as {target: {key: {language: translation}}}.",
            "When langs/missing metadata is present, every listed language must be present in translations and no unlisted language may be returned for that item.",
            "Preserve printf placeholders exactly; positional placeholders such as %1$d are allowed.",
            "Leave product names such as Lorvex unchanged unless the existing locale convention already localizes them.",
        ],
        "catalogStrings": catalog_gaps,
        "infoPlistStrings": info_plist_gaps,
    }
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return {
        "catalogStrings": len(catalog_gaps),
        "infoPlistTargets": len(info_plist_gaps),
        "infoPlistEntries": sum(len(entries) for entries in info_plist_gaps.values()),
    }


def apply_info_plist_table(
    translations: object,
    config_root: Path = CONFIG_ROOT,
) -> dict[str, int]:
    """Apply {target: {key: {lang: value}}} into InfoPlist.strings files."""
    translations = normalize_info_plist_translations(translations)
    if translations is None:
        raise ValueError("InfoPlist translation payload must be an object")

    applied: dict[str, int] = {}

    for target, by_key in translations.items():
        if not isinstance(by_key, dict):
            continue
        count = 0
        for key, by_lang in by_key.items():
            if not isinstance(by_lang, dict):
                continue
            for lang, value in by_lang.items():
                if not isinstance(value, str) or not value.strip():
                    continue
                path = config_root / "InfoPlist" / target / f"{lang}.lproj" / "InfoPlist.strings"
                entries = parse_strings_file(path)
                entries[key] = value
                write_strings_file(path, entries)
                count += 1
        applied[target] = count
    return applied


def normalize_info_plist_translations(translations: object) -> dict | None:
    if not isinstance(translations, dict):
        return None

    normalized: dict[str, dict[str, dict]] = {}
    for target, by_key in translations.items():
        if not isinstance(by_key, dict):
            normalized[target] = by_key
            continue
        normalized[target] = {}
        for key, by_lang in by_key.items():
            if isinstance(by_lang, dict) and isinstance(by_lang.get("translations"), dict):
                normalized[target][key] = by_lang["translations"]
            else:
                normalized[target][key] = by_lang
    return normalized


def info_plist_translation_requirements(translations: object) -> dict[tuple[str, str], set[str]]:
    if not isinstance(translations, dict):
        return {}

    requirements: dict[tuple[str, str], set[str]] = {}
    for target, by_key in translations.items():
        if not isinstance(target, str) or not isinstance(by_key, dict):
            continue
        for key, by_lang in by_key.items():
            if not isinstance(key, str) or not isinstance(by_lang, dict):
                continue
            missing = by_lang.get("missing")
            if not isinstance(missing, list):
                continue
            required = {lang for lang in missing if isinstance(lang, str) and lang.strip()}
            if required:
                requirements[(target, key)] = required
    return requirements


def info_plist_pack_metadata_failures(translations: object) -> list[str]:
    if not isinstance(translations, dict):
        return []

    failures: list[str] = []
    for target, by_key in translations.items():
        if not isinstance(target, str) or not isinstance(by_key, dict):
            continue
        for key, entry in by_key.items():
            label = f"{target} {key!r}"
            if not isinstance(entry, dict):
                continue
            if "en" in entry and (not isinstance(entry.get("en"), str) or not entry.get("en", "").strip()):
                failures.append(f"{label} en metadata must be a non-empty string")
            if "missing" in entry:
                missing = entry.get("missing")
                if not isinstance(missing, list) or not missing:
                    failures.append(f"{label} missing metadata must be a non-empty array")
                elif not all(isinstance(lang, str) and lang.strip() for lang in missing):
                    failures.append(f"{label} missing metadata must contain only non-empty strings")
                elif len(set(missing)) != len(missing):
                    failures.append(f"{label} missing metadata contains duplicate languages")
    return failures


def validate_info_plist_pack_sources(
    translations: object,
    config_root: Path = CONFIG_ROOT,
) -> list[str]:
    if not isinstance(translations, dict):
        return []

    failures: list[str] = []
    source_cache: dict[str, dict[str, str]] = {}
    for target, by_key in translations.items():
        if not isinstance(target, str) or not isinstance(by_key, dict) or target not in INFO_PLIST_RESOURCE_TARGETS:
            continue
        for key, entry in by_key.items():
            if not isinstance(key, str) or not isinstance(entry, dict):
                continue
            expected_source = entry.get("en")
            required_languages = info_plist_translation_requirements({target: {key: entry}}).get((target, key), set())
            if "en" not in entry and not required_languages:
                continue
            if target not in source_cache:
                source_path = config_root / "InfoPlist" / target / f"{SOURCE_LANGUAGE}.lproj" / "InfoPlist.strings"
                source_cache[target] = parse_strings_file(source_path)
            source_entries = source_cache[target]
            current_source = source_entries.get(key)
            if current_source is None:
                failures.append(f"{target} {key!r} InfoPlist source key is missing")
                continue
            if isinstance(expected_source, str) and current_source != expected_source:
                failures.append(
                    f"{target} {key!r} InfoPlist source mismatch: {current_source!r}; expected {expected_source!r}"
                )
            already_present: list[str] = []
            for lang in sorted(required_languages):
                lang_path = config_root / "InfoPlist" / target / f"{lang}.lproj" / "InfoPlist.strings"
                if parse_strings_file(lang_path).get(key, "").strip():
                    already_present.append(lang)
            if already_present:
                failures.append(f"{target} {key!r} InfoPlist already has translations for {already_present}")
    return failures


def apply_info_plist_translations(
    in_path: Path,
    config_root: Path = CONFIG_ROOT,
) -> dict[str, int]:
    translations = json.loads(in_path.read_text(encoding="utf-8"))
    return apply_info_plist_table(translations, config_root=config_root)


def validate_english_table(
    table: object,
    languages: list[str],
) -> list[str]:
    requirements = english_translation_requirements(table)
    table = normalize_english_translations(table)
    if table is None:
        return ["catalog translation payload must be an object or list"]

    failures: list[str] = []
    allowed = set(languages)
    for english, by_lang in table.items():
        if not isinstance(english, str) or not english.strip():
            failures.append("catalog translation payload contains an empty English key")
            continue
        if not isinstance(by_lang, dict):
            failures.append(f"{english!r} translations must be an object")
            continue
        if not by_lang:
            failures.append(f"{english!r} has no translations")
            continue
        required_languages = requirements.get(english, set())
        missing_languages = sorted(required_languages - set(by_lang.keys()))
        if missing_languages:
            failures.append(f"{english!r} is missing translations for {missing_languages}")
        extra_languages = sorted(set(by_lang.keys()) - required_languages) if required_languages else []
        if extra_languages:
            failures.append(f"{english!r} has translations for languages not listed by metadata: {extra_languages}")
        expected_placeholders = format_placeholders(english)
        for lang, translated in by_lang.items():
            if lang not in allowed:
                failures.append(f"{english!r} has unexpected language {lang!r}; expected one of {languages}")
                continue
            if not isinstance(translated, str) or not translated.strip():
                failures.append(f"{english!r} {lang} translation is empty")
                continue
            placeholders = format_placeholders(translated)
            if placeholders != expected_placeholders:
                failures.append(
                    f"{english!r} {lang} format placeholder mismatch: {placeholders}; "
                    f"expected {expected_placeholders}"
                )
    return failures


def validate_english_translations(
    in_path: Path,
    languages: list[str],
) -> list[str]:
    table = json.loads(in_path.read_text(encoding="utf-8"))
    return validate_english_table(table, languages)


def validate_info_plist_table(
    translations: object,
    languages: list[str],
) -> list[str]:
    requirements = info_plist_translation_requirements(translations)
    translations = normalize_info_plist_translations(translations)
    if translations is None:
        return ["InfoPlist translation payload must be an object"]

    failures: list[str] = []
    allowed_targets = set(INFO_PLIST_RESOURCE_TARGETS)
    allowed_languages = set(languages)
    for target, by_key in translations.items():
        if target not in allowed_targets:
            failures.append(f"unknown InfoPlist target {target!r}")
            continue
        if not isinstance(by_key, dict):
            failures.append(f"{target} translations must be an object")
            continue
        for key, by_lang in by_key.items():
            if not isinstance(key, str) or not key.strip():
                failures.append(f"{target} contains an empty InfoPlist key")
                continue
            if not isinstance(by_lang, dict):
                failures.append(f"{target} {key!r} translations must be an object")
                continue
            if not by_lang:
                failures.append(f"{target} {key!r} has no translations")
                continue
            required_languages = requirements.get((target, key), set())
            missing_languages = sorted(required_languages - set(by_lang.keys()))
            if missing_languages:
                failures.append(f"{target} {key!r} is missing translations for {missing_languages}")
            extra_languages = sorted(set(by_lang.keys()) - required_languages) if required_languages else []
            if extra_languages:
                failures.append(
                    f"{target} {key!r} has translations for languages not listed by metadata: {extra_languages}"
                )
            expected_placeholders = format_placeholders(key)
            for lang, translated in by_lang.items():
                if lang not in allowed_languages:
                    failures.append(f"{target} {key!r} has unexpected language {lang!r}; expected one of {languages}")
                    continue
                if not isinstance(translated, str) or not translated.strip():
                    failures.append(f"{target} {key!r} {lang} translation is empty")
                    continue
                placeholders = format_placeholders(translated)
                if placeholders != expected_placeholders:
                    failures.append(
                        f"{target} {key!r} {lang} format placeholder mismatch: {placeholders}; "
                        f"expected {expected_placeholders}"
                    )
    return failures


def validate_info_plist_translations(
    in_path: Path,
    languages: list[str],
) -> list[str]:
    translations = json.loads(in_path.read_text(encoding="utf-8"))
    return validate_info_plist_table(translations, languages)


def apply_translation_pack(
    in_path: Path,
    languages: list[str] | None,
    config_root: Path = CONFIG_ROOT,
) -> dict:
    payload = json.loads(in_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return {"failures": ["translation pack must be an object"], "catalog": {}, "infoPlist": {}}

    required_keys = ["catalogStrings", "infoPlistStrings"]
    missing_keys = [key for key in required_keys if key not in payload]
    if missing_keys:
        return {
            "failures": [f"translation pack missing required top-level key(s): {missing_keys}"],
            "catalog": {},
            "infoPlist": {},
        }

    resolved_languages, language_failures = translation_pack_languages(payload, languages)
    if language_failures:
        return {"failures": language_failures, "catalog": {}, "infoPlist": {}}

    catalog_table = payload["catalogStrings"]
    info_plist_table = payload["infoPlistStrings"]
    failures = validate_english_table(catalog_table, resolved_languages)
    failures.extend(validate_info_plist_table(info_plist_table, resolved_languages))
    failures.extend(catalog_pack_metadata_failures(catalog_table))
    failures.extend(info_plist_pack_metadata_failures(info_plist_table))
    failures.extend(validate_catalog_pack_sources(catalog_table))
    failures.extend(validate_info_plist_pack_sources(info_plist_table, config_root=config_root))
    if failures:
        return {"failures": failures, "catalog": {}, "infoPlist": {}}

    return {
        "failures": [],
        "catalog": apply_english_table(catalog_table),
        "infoPlist": apply_info_plist_table(info_plist_table, config_root=config_root),
    }


def translation_pack_languages(payload: dict, override: list[str] | None) -> tuple[list[str], list[str]]:
    if override is not None:
        return override, []

    languages = payload.get("languages")
    if languages is None:
        return list(DEFAULT_TARGET_LANGUAGES), []
    if not isinstance(languages, list) or not languages:
        return [], ["translation pack languages must be a non-empty array when present"]
    resolved: list[str] = []
    for language in languages:
        if not isinstance(language, str) or not language.strip():
            return [], ["translation pack languages must contain only non-empty strings"]
        resolved.append(language.strip())
    if len(set(resolved)) != len(resolved):
        return [], ["translation pack languages must not contain duplicates"]
    return resolved, []


def parse_languages(value: str | None) -> list[str]:
    if not value:
        return list(DEFAULT_TARGET_LANGUAGES)
    return [lang.strip() for lang in value.split(",") if lang.strip()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_seed = sub.add_parser("seed", help="reuse Tauri translations by English match")
    p_seed.add_argument("--languages")
    p_seed.add_argument("--write", action="store_true")

    p_gaps = sub.add_parser("gaps", help="emit still-missing entries as JSON")
    p_gaps.add_argument("--languages")
    p_gaps.add_argument("--out", required=True)

    p_gapsu = sub.add_parser("gaps-unique", help="emit deduplicated English strings to translate")
    p_gapsu.add_argument("--languages")
    p_gapsu.add_argument("--out", required=True)

    p_apply = sub.add_parser("apply", help="apply a per-key translations JSON")
    p_apply.add_argument("--in", dest="in_path", required=True)

    p_applye = sub.add_parser("apply-english", help="apply an {en: {lang: value}} table")
    p_applye.add_argument("--in", dest="in_path", required=True)

    p_plist_gaps = sub.add_parser("info-plist-gaps", help="emit missing InfoPlist.strings entries")
    p_plist_gaps.add_argument("--languages")
    p_plist_gaps.add_argument("--out", required=True)

    p_plist_apply = sub.add_parser("apply-info-plist", help="apply InfoPlist.strings translations")
    p_plist_apply.add_argument("--in", dest="in_path", required=True)

    p_pack = sub.add_parser("translation-pack", help="emit one combined translation input pack")
    p_pack.add_argument("--languages")
    p_pack.add_argument("--out", required=True)

    p_apply_pack = sub.add_parser("apply-pack", help="validate and apply a combined translation response pack")
    p_apply_pack.add_argument("--languages")
    p_apply_pack.add_argument("--in", dest="in_path", required=True)

    p_validatee = sub.add_parser("validate-english", help="validate an apply-english payload")
    p_validatee.add_argument("--languages")
    p_validatee.add_argument("--in", dest="in_path", required=True)

    p_validatep = sub.add_parser("validate-info-plist", help="validate an apply-info-plist payload")
    p_validatep.add_argument("--languages")
    p_validatep.add_argument("--in", dest="in_path", required=True)

    args = parser.parse_args(argv)

    if args.command == "seed":
        languages = parse_languages(args.languages)
        report = seed(languages, args.write)
        for rel, info in report.items():
            reused = sum(info["reused"].values())
            gaps = sum(info["gaps"].values())
            print(f"{rel}: {info['total']} keys | reused {reused} | gaps {gaps}")
        total_reused = sum(sum(i["reused"].values()) for i in report.values())
        total_gaps = sum(sum(i["gaps"].values()) for i in report.values())
        print(f"TOTAL reused {total_reused} | gaps {total_gaps} ({'WROTE' if args.write else 'dry-run'})")
        return 0

    if args.command == "gaps":
        languages = parse_languages(args.languages)
        counts = emit_gaps(languages, Path(args.out))
        for lang, count in counts.items():
            print(f"{lang}: {count} gap key(s)")
        print(f"wrote {args.out}")
        return 0

    if args.command == "gaps-unique":
        languages = parse_languages(args.languages)
        count = emit_unique_gaps(languages, Path(args.out))
        print(f"{count} unique English string(s) need translation; wrote {args.out}")
        return 0

    if args.command == "apply":
        applied = apply_translations(Path(args.in_path))
        for rel, count in applied.items():
            print(f"{rel}: applied {count}")
        return 0

    if args.command == "apply-english":
        applied = apply_by_english(Path(args.in_path))
        for rel, count in applied.items():
            print(f"{rel}: applied {count}")
        print(f"TOTAL applied {sum(applied.values())}")
        return 0

    if args.command == "info-plist-gaps":
        languages = parse_languages(args.languages)
        counts = emit_info_plist_gaps(languages, Path(args.out))
        for target, by_lang in counts.items():
            print(f"{target}: {sum(by_lang.values())} gap key(s)")
        print(f"wrote {args.out}")
        return 0

    if args.command == "apply-info-plist":
        applied = apply_info_plist_translations(Path(args.in_path))
        for target, count in applied.items():
            print(f"{target}: applied {count}")
        print(f"TOTAL applied {sum(applied.values())}")
        return 0

    if args.command == "translation-pack":
        languages = parse_languages(args.languages)
        counts = emit_translation_pack(languages, Path(args.out))
        print(
            f"catalogStrings: {counts['catalogStrings']} | "
            f"infoPlistTargets: {counts['infoPlistTargets']} | "
            f"infoPlistEntries: {counts['infoPlistEntries']}"
        )
        print(f"wrote {args.out}")
        return 0

    if args.command == "apply-pack":
        languages = parse_languages(args.languages) if args.languages else None
        result = apply_translation_pack(Path(args.in_path), languages)
        for failure in result["failures"]:
            print(failure)
        if result["failures"]:
            return 1
        for rel, count in result["catalog"].items():
            print(f"{rel}: applied {count}")
        for target, count in result["infoPlist"].items():
            print(f"{target}: applied {count}")
        print(f"TOTAL catalog applied {sum(result['catalog'].values())}")
        print(f"TOTAL InfoPlist applied {sum(result['infoPlist'].values())}")
        return 0

    if args.command == "validate-english":
        failures = validate_english_translations(Path(args.in_path), parse_languages(args.languages))
        for failure in failures:
            print(failure)
        return 1 if failures else 0

    if args.command == "validate-info-plist":
        failures = validate_info_plist_translations(Path(args.in_path), parse_languages(args.languages))
        for failure in failures:
            print(failure)
        return 1 if failures else 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
