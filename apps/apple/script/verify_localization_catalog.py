#!/usr/bin/env python3
"""Verify Apple string catalogs and source key references.

Every catalog must carry every language declared by any Apple string catalog.
The required language set is discovered from the catalogs themselves so adding
another locale only requires catalog + bundle metadata changes, not verifier
code changes. The LorvexApple catalog is referenced through native,
bundle-qualified `String(localized:)`, `Text`, and `LocalizedStringResource`
calls; module catalogs are referenced through their `<Module>L10n.*` helpers
and equivalent native bundle-qualified calls.

App-Intent metadata (titles, `@Parameter` labels, AppEnum case representations,
and the dialog / confirmation prompts returned from `perform()`) instead uses a
raw `LocalizedStringResource("key", … table: … bundle: <Helper>.bundle)`
literal, with no `<Helper>.string/resource(...)` call for the literal scanner to
key on. Those references are checked for existence against the catalog their
`bundle:` argument names, exactly like the module-helper references — otherwise a
string reached only through an App Intent could name a key the catalog does not
carry and still pass (it renders in English regardless of the request locale).
"""

from __future__ import annotations

import argparse
import functools
import json
import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "Sources" / "LorvexApple" / "Resources" / "Localizable.xcstrings"
DEFAULT_SOURCE_LANGUAGE = "en"
SOURCE_LANGUAGE = DEFAULT_SOURCE_LANGUAGE
SOURCE_ROOTS = [
    ROOT / "Sources" / "LorvexApple",
    ROOT / "Sources" / "LorvexMobile",
    ROOT / "Sources" / "LorvexWatch",
    ROOT / "Sources" / "LorvexSystemIntents",
]

# Per-module catalogs reached through a legacy helper or an explicitly
# bundle-qualified native lookup. Each catalog must contain every key its
# source roots reference, with all required languages.
# (helper-name, catalog-path, [source-roots]). WidgetSupportL10n is public and
# shared: the widget extension, widget intents, and Watch complication localize
# metadata and snapshot fallbacks through the LorvexWidgetKitSupport catalog,
# so every consuming source directory is scanned.
MODULE_CATALOGS = [
    ("MobileL10n", ROOT / "Sources" / "LorvexMobile" / "Resources" / "Localizable.xcstrings",
     [ROOT / "Sources" / "LorvexMobile"]),
    ("WatchL10n", ROOT / "Sources" / "LorvexWatch" / "Resources" / "Localizable.xcstrings",
     [ROOT / "Sources" / "LorvexWatch"]),
    ("SystemL10n",
     ROOT / "Sources" / "LorvexSystemIntents" / "Resources" / "Localizable.xcstrings",
     [ROOT / "Sources" / "LorvexSystemIntents"]),
    ("WidgetL10n", ROOT / "Sources" / "LorvexWidgetViews" / "Resources" / "Localizable.xcstrings",
     [
         ROOT / "Sources" / "LorvexWidgetViews",
         ROOT / "Sources" / "LorvexWidgetExtension",
     ]),
    ("WidgetSupportL10n",
     ROOT / "Sources" / "LorvexWidgetKitSupport" / "Resources" / "Localizable.xcstrings",
     [
         ROOT / "Sources" / "LorvexWidgetKitSupport",
         ROOT / "Sources" / "LorvexWidgetExtension",
         ROOT / "Sources" / "LorvexWidgetIntents",
         ROOT / "Sources" / "LorvexWatch",
     ]),
    ("CarPlayL10n", ROOT / "Sources" / "LorvexCarPlay" / "Resources" / "Localizable.xcstrings",
     [ROOT / "Sources" / "LorvexCarPlay"]),
]
CONFIG_ROOT = ROOT / "Config"
INFO_PLIST_RESOURCE_TARGETS = {
    "LorvexMobileApp-Info.plist": "LorvexMobileApp",
    "LorvexVisionApp-Info.plist": "LorvexVisionApp",
    "LorvexWatchApp-Info.plist": "LorvexWatchApp",
    "LorvexWatchComplication-Info.plist": "LorvexWatchComplication",
    "LorvexWidgetExtension-Info.plist": "LorvexFocusWidgetExtension",
    "LorvexFocusFilterExtension-Info.plist": "LorvexFocusFilterExtension",
}
REQUIRED_KEYS = {
    "sidebar.section.plan",
    "sidebar.item.today",
    "sidebar.item.tasks",
    "sidebar.item.lists",
    "sidebar.item.calendar",
    "sidebar.item.habits",
    "sidebar.item.reviews",
    "sidebar.item.memory",
    "sidebar.settings",
    "today.empty.no_tasks_title",
    "today.empty.no_tasks_description",
    "window.title.task_detail",
    "task_command.show_detail",
    "task_command.save",
    "task_command.add_to_focus",
    "task_command.remove_from_focus",
    "task_command.defer_to_tomorrow",
    "task_command.complete",
    "task_command.reopen",
    "task_command.cancel",
    "app.command.refresh",
}
MODULE_REQUIRED_KEYS = {
    "MobileL10n": {
        # Retained for catalog compatibility until the Mobile catalog-cleanup
        # checkpoint decides whether this currently unreferenced key ships.
        "permissions.calendar",
    },
}

# These are product names rather than translatable prose. Every shipped Mobile
# locale intentionally presents the same CloudKit name.
MOBILE_IDENTICAL_TRANSLATION_ALLOWLIST = {
    "settings.sync.backend.cloudkit",
    "settings.sync.backend.record_plan",
}


class DuplicateJSONKeyError(ValueError):
    pass


def reject_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    """Build one JSON object while rejecting keys the ordinary decoder hides.

    ``json.loads`` otherwise keeps only the last occurrence of a duplicate key.
    In a String Catalog that can silently discard a localization, a variation,
    or even an entire key entry before the rest of this verifier sees it.
    """
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateJSONKeyError(f"duplicate JSON object key {key!r}")
        value[key] = item
    return value


def load_catalog(path: Path) -> tuple[dict[str, object], list[str]]:
    if not path.is_file():
        return {}, [f"string catalog missing: {path}"]
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_json_keys,
        )
    except (json.JSONDecodeError, DuplicateJSONKeyError) as error:
        return {}, [f"string catalog is not valid JSON: {error}"]
    if not isinstance(value, dict):
        return {}, [f"string catalog root is not an object: {type(value).__name__}"]
    return value, []


def swift_source_without_comments(text: str) -> str:
    """Mask Swift comments while preserving byte positions and line numbers.

    Localization-call scanners intentionally operate on source text instead of
    a compiler AST so the release gate stays fast and toolchain-independent.
    Masking (rather than deleting) comments prevents examples in documentation
    comments from becoming fake key references without shifting diagnostics.
    Swift block comments nest, so the small lexer tracks their depth. String
    literal contents are left untouched so ``//`` in a URL/default value is not
    mistaken for a comment.
    """
    output = list(text)
    index = 0
    length = len(text)

    def mask(start: int, end: int) -> None:
        for offset in range(start, end):
            if output[offset] not in "\r\n":
                output[offset] = " "

    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index + 2)
            if end < 0:
                end = length
            mask(index, end)
            index = end
            continue

        if text.startswith("/*", index):
            start = index
            depth = 1
            index += 2
            while index < length and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            mask(start, index)
            continue

        if text.startswith('"""', index):
            index += 3
            while index < length:
                if text.startswith('"""', index):
                    index += 3
                    break
                if text[index] == "\\":
                    index = min(length, index + 2)
                else:
                    index += 1
            continue

        if text[index] == '"':
            index += 1
            while index < length:
                if text[index] == "\\":
                    index = min(length, index + 2)
                elif text[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            continue

        index += 1
    return "".join(output)


def read_swift_source(path: Path) -> str:
    stat = path.stat()
    return _read_swift_source_cached(str(path), stat.st_mtime_ns, stat.st_size)


@functools.lru_cache(maxsize=None)
def _read_swift_source_cached(path: str, _mtime_ns: int, _size: int) -> str:
    return swift_source_without_comments(Path(path).read_text(encoding="utf-8"))


def catalog_source_language(catalog: dict[str, object]) -> str:
    source_language = catalog.get("sourceLanguage")
    return source_language if isinstance(source_language, str) and source_language else DEFAULT_SOURCE_LANGUAGE


def required_source_language(catalogs: list[dict[str, object]]) -> str:
    for catalog in catalogs:
        source_language = catalog.get("sourceLanguage")
        if isinstance(source_language, str) and source_language:
            return source_language
    return DEFAULT_SOURCE_LANGUAGE


def catalog_structure_failures(
    catalog: dict[str, object],
    source_language: str = DEFAULT_SOURCE_LANGUAGE,
) -> list[str]:
    failures: list[str] = []
    if catalog.get("sourceLanguage") != source_language:
        failures.append(f"sourceLanguage mismatch: {catalog.get('sourceLanguage')!r}")
    if catalog.get("version") != "1.0":
        failures.append(f"version mismatch: {catalog.get('version')!r}")
    if not isinstance(catalog.get("strings"), dict):
        failures.append(f"strings mismatch: {catalog.get('strings')!r}")
    return failures


def catalog_keys(catalog: dict[str, object]) -> set[str]:
    strings = catalog.get("strings")
    return set(strings) if isinstance(strings, dict) else set()


def catalog_languages(catalog: dict[str, object]) -> set[str]:
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return {catalog_source_language(catalog)}

    languages = {catalog_source_language(catalog)}
    for value in strings.values():
        if not isinstance(value, dict):
            continue
        localizations = value.get("localizations")
        if isinstance(localizations, dict):
            languages.update(str(language) for language in localizations)
    return languages


def format_placeholders(text: str) -> list[tuple[int, str]]:
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

    explicit_positions = {position for position, _ in placeholders if position is not None}
    assigned_positions = set(explicit_positions)
    next_implicit_position = 1
    normalized: list[tuple[int, str]] = []
    for position, token in placeholders:
        if position is None:
            while next_implicit_position in assigned_positions:
                next_implicit_position += 1
            position = next_implicit_position
            assigned_positions.add(position)
            next_implicit_position += 1
        normalized.append((position, token))
    return sorted(normalized, key=lambda item: item[0])


def localization_format_placeholders(
    localization: dict[str, object],
) -> tuple[list[tuple[int, str]], list[str]]:
    """Return a localization's wire-format argument signature.

    String Catalog plural substitutions use `%#@name@` markers in the outer
    string and carry the real argument position/type in `substitutions`. Treat
    those exactly like the equivalent positional printf placeholder so a locale
    may correctly use `.stringsdict` while the source locale uses `.strings`.
    """
    string_unit = localization.get("stringUnit")
    text = string_unit.get("value") if isinstance(string_unit, dict) else None
    if not isinstance(text, str):
        return [], []

    substitutions = localization.get("substitutions")
    if not isinstance(substitutions, dict) or not substitutions:
        return format_placeholders(text), []

    marker_pattern = re.compile(r"%(?:(\d+)\$)?#@([A-Za-z0-9_]+)@")
    referenced_names: set[str] = set()
    argument_numbers: dict[str, int] = {}
    failures: list[str] = []

    def replace_marker(match: re.Match[str]) -> str:
        explicit_position = int(match.group(1)) if match.group(1) else None
        name = match.group(2)
        first_reference = name not in referenced_names
        referenced_names.add(name)
        substitution = substitutions.get(name)
        if not isinstance(substitution, dict):
            failures.append(f"substitution marker {name!r} has no definition")
            return match.group(0)

        argument_number = substitution.get("argNum")
        specifier = substitution.get("formatSpecifier")
        if not isinstance(argument_number, int) or argument_number < 1:
            failures.append(f"substitution {name!r} has invalid argNum {argument_number!r}")
            return match.group(0)
        if explicit_position is not None and explicit_position != argument_number:
            failures.append(
                f"substitution {name!r} marker position {explicit_position} "
                f"does not match argNum {argument_number}"
            )
        valid_specifier = (
            re.fullmatch(
                r"(?:hh|h|ll|l|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp]",
                specifier,
            )
            if isinstance(specifier, str)
            else None
        )
        if valid_specifier is None:
            failures.append(
                f"substitution {name!r} has invalid formatSpecifier {specifier!r}"
            )
            return match.group(0)

        if first_reference:
            argument_numbers[name] = argument_number
            variations = substitution.get("variations")
            plural = variations.get("plural") if isinstance(variations, dict) else None
            if not isinstance(plural, dict) or not plural:
                failures.append(f"substitution {name!r} is missing plural variations")
            else:
                if "other" not in plural:
                    failures.append(f"substitution {name!r} plural variations missing 'other'")
                for category, variant in plural.items():
                    unit = variant.get("stringUnit") if isinstance(variant, dict) else None
                    value = unit.get("value") if isinstance(unit, dict) else None
                    state = unit.get("state") if isinstance(unit, dict) else None
                    if not isinstance(value, str) or not value.strip():
                        failures.append(
                            f"substitution {name!r} plural {category!r} missing stringUnit.value"
                        )
                    elif "%arg" not in value:
                        failures.append(
                            f"substitution {name!r} plural {category!r} must contain %arg"
                        )
                    if state != "translated":
                        failures.append(
                            f"substitution {name!r} plural {category!r} state mismatch: {state!r}"
                        )
        return f"%{argument_number}${specifier}"

    normalized = marker_pattern.sub(replace_marker, text)
    unreferenced = sorted(set(substitutions) - referenced_names)
    if unreferenced:
        failures.append(f"unreferenced substitution definition(s): {unreferenced}")
    numbers = list(argument_numbers.values())
    if len(numbers) != len(set(numbers)):
        failures.append(f"duplicate substitution argNum values: {numbers}")
    return format_placeholders(normalized), failures


def required_languages(catalogs: list[dict[str, object]]) -> tuple[str, ...]:
    languages: set[str] = set()
    for catalog in catalogs:
        languages.update(catalog_languages(catalog))
    if not languages:
        languages.add(DEFAULT_SOURCE_LANGUAGE)
    return tuple(sorted(languages))


def shipping_bundle_plists(config_root: Path = CONFIG_ROOT) -> list[Path]:
    return sorted(config_root.glob("*-Info.plist"))


def plist_localization_failures(
    path: Path,
    languages: tuple[str, ...],
    source_language: str = DEFAULT_SOURCE_LANGUAGE,
) -> list[str]:
    if not path.is_file():
        return [f"shipping bundle Info.plist missing: {path}"]
    try:
        value = plistlib.loads(path.read_bytes())
    except Exception as error:
        return [f"shipping bundle Info.plist is not valid plist: {path}: {error}"]
    localizations = value.get("CFBundleLocalizations")
    if not isinstance(localizations, list) or not all(isinstance(item, str) for item in localizations):
        return [f"{path} missing CFBundleLocalizations array"]
    actual = tuple(sorted(localizations))
    development_region = value.get("CFBundleDevelopmentRegion")
    allowed_development_regions = {source_language, "$(DEVELOPMENT_LANGUAGE)"}
    if development_region not in allowed_development_regions:
        return [
            f"{path} CFBundleDevelopmentRegion mismatch: "
            f"{development_region!r}; expected {source_language!r}"
        ]
    if actual != languages:
        return [f"{path} CFBundleLocalizations mismatch: {actual}; expected {languages}"]
    return []


def localized_info_plist_keys(value: dict[str, object]) -> set[str]:
    keys: set[str] = set()
    for key in [
        "CFBundleDisplayName",
        "CFBundleName",
        "NSCalendarsWriteOnlyAccessUsageDescription",
        "NSCalendarsFullAccessUsageDescription",
    ]:
        if isinstance(value.get(key), str):
            keys.add(key)

    shortcut_items = value.get("UIApplicationShortcutItems")
    if isinstance(shortcut_items, list):
        for item in shortcut_items:
            if not isinstance(item, dict):
                continue
            for key in ["UIApplicationShortcutItemTitle", "UIApplicationShortcutItemSubtitle"]:
                title = item.get(key)
                if isinstance(title, str) and title:
                    keys.add(title)
    return keys


def parse_info_plist_strings(path: Path) -> tuple[dict[str, str], list[str]]:
    if not path.is_file():
        return {}, [f"InfoPlist.strings missing: {path}"]
    text = path.read_text(encoding="utf-8")
    entries: dict[str, str] = {}
    failures: list[str] = []
    pattern = re.compile(r'^\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;\s*$')

    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        match = pattern.match(line)
        if not match:
            failures.append(f"{path}:{line_number} malformed InfoPlist.strings entry")
            continue
        try:
            key = json.loads(match.group(1))
            value = json.loads(match.group(2))
        except json.JSONDecodeError as error:
            failures.append(f"{path}:{line_number} invalid string escape: {error}")
            continue
        if not isinstance(key, str) or not isinstance(value, str):
            failures.append(f"{path}:{line_number} key/value must be strings")
            continue
        entries[key] = value
    return entries, failures


def info_plist_strings_failures(
    path: Path,
    languages: tuple[str, ...],
    config_root: Path = CONFIG_ROOT,
) -> list[str]:
    if not path.is_file():
        return [f"shipping bundle Info.plist missing: {path}"]
    try:
        value = plistlib.loads(path.read_bytes())
    except Exception as error:
        return [f"shipping bundle Info.plist is not valid plist: {path}: {error}"]
    if not isinstance(value, dict):
        return [f"shipping bundle Info.plist is not a dictionary: {path}"]

    # A background-only agent (LSUIElement + LSBackgroundOnly) never presents its
    # bundle name in any user-visible surface (no Dock tile, menu bar, or window
    # title), so its CFBundleName/DisplayName are technical identifiers, not
    # localized user-facing strings, and need no per-language InfoPlist.strings.
    if value.get("LSUIElement") is True and value.get("LSBackgroundOnly") is True:
        return []

    required_keys = localized_info_plist_keys(value)
    if not required_keys:
        return []

    resource_target = INFO_PLIST_RESOURCE_TARGETS.get(path.name)
    if resource_target is None:
        return [f"{path} has localized system-facing strings but no InfoPlist resource target mapping"]

    failures: list[str] = []
    for language in languages:
        strings_path = config_root / "InfoPlist" / resource_target / f"{language}.lproj" / "InfoPlist.strings"
        entries, parse_failures = parse_info_plist_strings(strings_path)
        failures.extend(parse_failures)
        for key in sorted(required_keys):
            localized_value = entries.get(key, "").strip()
            if not localized_value:
                failures.append(f"{strings_path} missing non-empty localization for {key}")
    return failures


def sync_plist_localizations(
    path: Path,
    languages: tuple[str, ...],
    source_language: str = DEFAULT_SOURCE_LANGUAGE,
) -> bool:
    """Rewrite a bundle plist only when its shipped language metadata drifts."""
    if not path.is_file():
        return False
    value = plistlib.loads(path.read_bytes())
    if not isinstance(value, dict):
        return False

    changed = False
    allowed_development_regions = {source_language, "$(DEVELOPMENT_LANGUAGE)"}
    if value.get("CFBundleDevelopmentRegion") not in allowed_development_regions:
        value["CFBundleDevelopmentRegion"] = source_language
        changed = True
    if value.get("CFBundleLocalizations") != list(languages):
        value["CFBundleLocalizations"] = list(languages)
        changed = True

    if changed:
        path.write_bytes(
            plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=False)
        )
    return changed


def catalog_entry_failures(
    catalog: dict[str, object],
    required_keys: set[str] | None = None,
    languages: tuple[str, ...] = (DEFAULT_SOURCE_LANGUAGE,),
) -> list[str]:
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return []

    failures: list[str] = []
    missing_required = sorted((required_keys or set()) - set(strings))
    if missing_required:
        failures.append(f"required localization key(s) missing: {missing_required}")

    for key, value in strings.items():
        if not isinstance(value, dict):
            failures.append(f"{key} entry is not an object")
            continue
        if value.get("extractionState") != "manual":
            failures.append(f"{key} extractionState mismatch: {value.get('extractionState')!r}")
        localizations = value.get("localizations")
        source_language = catalog_source_language(catalog)
        source_localization = (
            localizations.get(source_language) if isinstance(localizations, dict) else None
        )
        source_plural = (
            source_localization.get("variations", {}).get("plural")
            if isinstance(source_localization, dict)
            else None
        )
        # A plural leaf may deliberately omit the rendered count ("1 record")
        # while another locale includes it ("%lld rekord"). It may not invent a
        # new argument position or reinterpret an existing argument's type. Build
        # the source locale's union as the ABI, then validate EVERY leaf against
        # it; the old check compared only each locale's `other` leaf.
        plural_argument_types: dict[int, str] = {}
        if isinstance(source_plural, dict):
            for category, variant in source_plural.items():
                unit = variant.get("stringUnit") if isinstance(variant, dict) else None
                text = unit.get("value") if isinstance(unit, dict) else None
                if not isinstance(text, str):
                    continue
                for position, token in format_placeholders(text):
                    previous = plural_argument_types.get(position)
                    if previous is not None and previous != token:
                        failures.append(
                            f"{key} {source_language} plural '{category}' changes argument "
                            f"{position} type to {token!r}; expected {previous!r}"
                        )
                    else:
                        plural_argument_types[position] = token
        placeholders_by_language: dict[str, list[tuple[int, str]]] = {}
        for language in languages:
            unit = localizations.get(language) if isinstance(localizations, dict) else None
            plural = (
                unit.get("variations", {}).get("plural")
                if isinstance(unit, dict)
                else None
            )
            if isinstance(plural, dict) and plural:
                # Plural-variation entry: every category carries its own
                # stringUnit, and the language must at minimum provide
                # CLDR's required "other" category. The representative text
                # for placeholder comparison is the "other" form.
                if "other" not in plural:
                    failures.append(f"{key} {language} plural variations missing 'other'")
                for category, variant in plural.items():
                    v_unit = variant.get("stringUnit") if isinstance(variant, dict) else None
                    v_text = v_unit.get("value") if isinstance(v_unit, dict) else None
                    if not isinstance(v_text, str) or not v_text.strip():
                        failures.append(
                            f"{key} {language} plural '{category}' missing stringUnit.value")
                    v_state = v_unit.get("state") if isinstance(v_unit, dict) else None
                    if v_state != "translated":
                        failures.append(
                            f"{key} {language} plural '{category}' state mismatch: {v_state!r}")
                    if isinstance(v_text, str):
                        for position, token in format_placeholders(v_text):
                            expected = plural_argument_types.get(position)
                            if expected is None:
                                failures.append(
                                    f"{key} {language} plural '{category}' introduces "
                                    f"unknown argument {position} ({token})"
                                )
                            elif expected != token:
                                failures.append(
                                    f"{key} {language} plural '{category}' argument "
                                    f"{position} type mismatch: {token!r}; expected {expected!r}"
                                )
                other_unit = plural.get("other", {})
                other_text = (
                    other_unit.get("stringUnit", {}).get("value")
                    if isinstance(other_unit, dict)
                    else None
                )
                if isinstance(other_text, str):
                    placeholders_by_language[language] = format_placeholders(other_text)
                continue
            string_unit = unit.get("stringUnit") if isinstance(unit, dict) else None
            text = string_unit.get("value") if isinstance(string_unit, dict) else None
            if not isinstance(text, str) or not text.strip():
                failures.append(f"{key} missing non-empty {language} stringUnit.value")
            elif isinstance(text, str):
                placeholders, substitution_failures = localization_format_placeholders(unit)
                placeholders_by_language[language] = placeholders
                failures.extend(
                    f"{key} {language} {failure}" for failure in substitution_failures
                )
            state = string_unit.get("state") if isinstance(string_unit, dict) else None
            if state != "translated":
                failures.append(f"{key} {language} stringUnit.state mismatch: {state!r}")
        source_placeholders = placeholders_by_language.get(source_language)
        if source_placeholders is not None:
            for language, placeholders in placeholders_by_language.items():
                if language == source_language:
                    continue
                if placeholders != source_placeholders:
                    failures.append(
                        f"{key} {language} format placeholder mismatch: {placeholders}; "
                        f"expected {source_placeholders}"
                    )
    return failures


def copied_source_translation_failures(
    catalog: dict[str, object],
    languages: tuple[str, ...],
    allowlist: set[str] | frozenset[str] = frozenset(),
) -> list[str]:
    """Reject prose copied verbatim into every non-source localization.

    A single translation may legitimately match English (proper names and
    shared technical vocabulary are common). Requiring *every* shipped locale
    to match the English prose, however, is a reliable signal that a batch
    catalog migration stamped source text into the translation slots. Pure
    placeholder/punctuation templates are excluded because there is no prose
    to translate; intentional product names must be explicitly allowlisted.
    """
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return []

    source_language = catalog_source_language(catalog)
    target_languages = tuple(language for language in languages if language != source_language)
    if not target_languages:
        return []

    failures: list[str] = []

    def contains_prose(texts: list[str]) -> bool:
        text = " ".join(texts)
        text = re.sub(r"%(?:(?:\d+)\$)?#@[A-Za-z0-9_]+@", "", text)
        text = text.replace("%arg", "")
        text = re.sub(
            r"%(?:(?:\d+)\$)?(?:[-+#0 ]*\d*(?:\.\d+)?)?"
            r"(?:hh|h|ll|l|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp]",
            "",
            text,
        )
        return re.search(r"[A-Za-z]", text) is not None

    for key, entry_value in strings.items():
        if key in allowlist or not isinstance(entry_value, dict):
            continue
        localizations = entry_value.get("localizations")
        if not isinstance(localizations, dict):
            continue
        source = localizations.get(source_language)
        source_plural = (
            source.get("variations", {}).get("plural")
            if isinstance(source, dict)
            else None
        )
        if isinstance(source_plural, dict) and source_plural:
            source_forms = {
                category: variant.get("stringUnit", {}).get("value")
                for category, variant in source_plural.items()
                if isinstance(variant, dict)
            }
            if not all(isinstance(text, str) for text in source_forms.values()):
                continue
            source_other = source_forms.get("other")
            if not isinstance(source_other, str) or not contains_prose(list(source_forms.values())):
                continue

            copied = True
            for language in target_languages:
                target = localizations.get(language)
                target_plural = (
                    target.get("variations", {}).get("plural")
                    if isinstance(target, dict)
                    else None
                )
                if not isinstance(target_plural, dict) or not target_plural:
                    copied = False
                    break
                for category, variant in target_plural.items():
                    unit = variant.get("stringUnit") if isinstance(variant, dict) else None
                    target_text = unit.get("value") if isinstance(unit, dict) else None
                    expected = source_forms.get(category, source_other)
                    if not isinstance(target_text, str) or target_text != expected:
                        copied = False
                        break
                if not copied:
                    break
            if copied:
                failures.append(
                    f"{key} copies source-language prose into every non-source localization"
                )
            continue

        source_substitutions = (
            source.get("substitutions") if isinstance(source, dict) else None
        )
        if isinstance(source_substitutions, dict) and source_substitutions:
            source_unit = source.get("stringUnit")
            source_outer = (
                source_unit.get("value") if isinstance(source_unit, dict) else None
            )
            source_substitution_forms: dict[str, dict[str, str]] = {}
            for name, substitution in source_substitutions.items():
                plural = (
                    substitution.get("variations", {}).get("plural")
                    if isinstance(substitution, dict)
                    else None
                )
                if not isinstance(plural, dict) or not plural:
                    source_substitution_forms = {}
                    break
                forms: dict[str, str] = {}
                for category, variant in plural.items():
                    unit = variant.get("stringUnit") if isinstance(variant, dict) else None
                    text = unit.get("value") if isinstance(unit, dict) else None
                    if not isinstance(text, str):
                        forms = {}
                        break
                    forms[category] = text
                if not forms or "other" not in forms:
                    source_substitution_forms = {}
                    break
                source_substitution_forms[name] = forms

            source_leaf_texts = [
                text
                for forms in source_substitution_forms.values()
                for text in forms.values()
            ]
            if (
                isinstance(source_outer, str)
                and source_substitution_forms
                and contains_prose([source_outer, *source_leaf_texts])
            ):
                copied = True
                for language in target_languages:
                    target = localizations.get(language)
                    target_unit = target.get("stringUnit") if isinstance(target, dict) else None
                    target_outer = (
                        target_unit.get("value") if isinstance(target_unit, dict) else None
                    )
                    target_substitutions = (
                        target.get("substitutions") if isinstance(target, dict) else None
                    )
                    if target_outer != source_outer or not isinstance(
                        target_substitutions, dict
                    ):
                        copied = False
                        break
                    for name, source_forms in source_substitution_forms.items():
                        target_substitution = target_substitutions.get(name)
                        target_plural = (
                            target_substitution.get("variations", {}).get("plural")
                            if isinstance(target_substitution, dict)
                            else None
                        )
                        if not isinstance(target_plural, dict) or not target_plural:
                            copied = False
                            break
                        for category, variant in target_plural.items():
                            unit = (
                                variant.get("stringUnit")
                                if isinstance(variant, dict)
                                else None
                            )
                            target_text = unit.get("value") if isinstance(unit, dict) else None
                            expected = source_forms.get(category, source_forms["other"])
                            if not isinstance(target_text, str) or target_text != expected:
                                copied = False
                                break
                        if not copied:
                            break
                    if not copied:
                        break
                if copied:
                    failures.append(
                        f"{key} copies source-language prose into every non-source localization"
                    )
                continue

        source_unit = source.get("stringUnit") if isinstance(source, dict) else None
        source_text = source_unit.get("value") if isinstance(source_unit, dict) else None
        if not isinstance(source_text, str) or not contains_prose([source_text]):
            continue

        target_values: list[str] = []
        for language in target_languages:
            localization = localizations.get(language)
            string_unit = (
                localization.get("stringUnit") if isinstance(localization, dict) else None
            )
            value = string_unit.get("value") if isinstance(string_unit, dict) else None
            if not isinstance(value, str):
                target_values = []
                break
            target_values.append(value)
        if target_values and all(value == source_text for value in target_values):
            failures.append(
                f"{key} copies source-language prose into every non-source localization"
            )
    return failures


def referenced_app_keys(source_roots: list[Path] = SOURCE_ROOTS) -> set[str]:
    keys: set[str] = set()
    native_by_token = native_localized_string_bundle_keys(source_roots)
    for token in APP_NATIVE_BUNDLE_TOKENS:
        keys |= native_by_token.get(token, set())
    native_text_by_token = native_localized_text_bundle_keys(source_roots)
    for token in APP_NATIVE_BUNDLE_TOKENS:
        keys |= native_text_by_token.get(token, set())
    keys |= bundle_owned_resource_keys(APP_RESOURCE_BUNDLE_TOKENS, source_roots)
    return keys


def source_reference_failures(
    catalog: dict[str, object],
    source_roots: list[Path] = SOURCE_ROOTS,
) -> list[str]:
    catalog_key_set = catalog_keys(catalog)
    referenced_keys = referenced_app_keys(source_roots)
    missing = sorted(referenced_keys - catalog_key_set)
    if missing:
        return [f"source references localization key(s) missing from catalog: {missing}"]
    return []


# Reverse of the missing-key check: every catalog key must be referenced
# somewhere in the app (or allowlisted in REQUIRED_KEYS), so dead keys can't
# accumulate undetected. Scans the WHOLE tree — Sources (every module, not just
# the four primary app surfaces) plus Tests — so a key used only
# in CarPlay, a widget, the core, or a test is never falsely flagged.
DEAD_KEY_SCAN_ROOTS = [ROOT / "Sources", ROOT / "Tests"]


def unreferenced_app_key_failures(
    catalog: dict[str, object], source_roots: list[Path] = DEAD_KEY_SCAN_ROOTS
) -> list[str]:
    referenced = referenced_app_keys(source_roots)
    dead = sorted(catalog_keys(catalog) - referenced - REQUIRED_KEYS)
    if dead:
        return [
            "catalog has unreferenced key(s) (not used via an app-owned helper/native "
            f"lookup/resource and not in REQUIRED_KEYS): {dead}"
        ]
    return []


def unreferenced_module_key_failures(
    helper: str,
    catalog: dict[str, object],
    source_roots: list[Path] = DEAD_KEY_SCAN_ROOTS,
) -> list[str]:
    referenced = module_owned_reference_keys(helper, source_roots)
    dead = sorted(catalog_keys(catalog) - referenced - MODULE_REQUIRED_KEYS.get(helper, set()))
    if dead:
        return [
            f"{helper} catalog has unreferenced key(s) "
            f"(not used via a helper/native lookup or bundle-owned resource): {dead}"
        ]
    return []


def referenced_module_keys(helper: str, source_roots: list[Path]) -> set[str]:
    keys: set[str] = set()
    pattern = re.compile(
        helper + r"\.(?:string|text|resource|plural|catalogPlural)\s*\(\s*\"([^\"]+)\"")
    for source_root in source_roots:
        if not source_root.exists():
            continue
        for path in source_root.rglob("*.swift"):
            keys.update(pattern.findall(read_swift_source(path)))
    native_by_token = native_localized_string_bundle_keys(source_roots)
    for token in NATIVE_STRING_BUNDLE_TOKENS.get(helper, set()):
        keys |= native_by_token.get(token, set())
    native_text_by_token = native_localized_text_bundle_keys(source_roots)
    for token in NATIVE_STRING_BUNDLE_TOKENS.get(helper, set()):
        keys |= native_text_by_token.get(token, set())
    return keys


def legacy_plain_module_keys(helper: str, source_roots: list[Path]) -> set[str]:
    """Literal keys still routed through an eager legacy helper."""
    keys: set[str] = set()
    pattern = re.compile(
        helper + r"\.(?:string|text|resource)\s*\(\s*\"([^\"]+)\"")
    for root in source_roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            keys.update(pattern.findall(read_swift_source(path)))
    return keys


def plural_catalog_keys(catalog: dict[str, object]) -> set[str]:
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return set()
    plural: set[str] = set()
    for key, value in strings.items():
        if not isinstance(value, dict):
            continue
        localizations = value.get("localizations")
        if not isinstance(localizations, dict):
            continue
        if any(
            isinstance(localization, dict)
            and isinstance(localization.get("variations"), dict)
            and "plural" in localization["variations"]
            for localization in localizations.values()
        ):
            plural.add(key)
    return plural


def plain_helper_plural_reference_failures(
    helper: str, catalog: dict[str, object], source_roots: list[Path]
) -> list[str]:
    invalid = sorted(legacy_plain_module_keys(helper, source_roots) & plural_catalog_keys(catalog))
    if invalid:
        return [
            f"{helper} routes plural catalog key(s) through an eager plain helper; "
            f"use native integer interpolation: {invalid}"
        ]
    return []


def module_reference_failures(
    helper: str, catalog: dict[str, object], source_roots: list[Path]
) -> list[str]:
    missing = sorted(referenced_module_keys(helper, source_roots) - catalog_keys(catalog))
    if missing:
        return [f"{helper} references key(s) missing from its catalog: {missing}"]
    return []


# The `bundle:` argument identifies which module catalog a raw
# `LocalizedStringResource("key", … bundle: <token>)` reference resolves against.
# App-Intent titles, `@Parameter` labels, AppEnum case representations, and
# dialog / confirmation prompts use this raw form, so their key existence must be
# asserted the same way `<Helper>.string(...)` references are — the literal
# scanner in `referenced_module_keys` cannot see them (there is no helper call).
# Maps a catalog helper -> the explicit `bundle:` identifiers whose
# LocalizedStringResource keys live in that helper's catalog. Configuration
# metadata references WidgetL10n.bundle directly; a resolver alias must not
# become a second, hand-maintained ownership path.
MODULE_RESOURCE_BUNDLE_TOKENS = {
    "MobileL10n": {"MobileL10n.bundle"},
    "WatchL10n": {"WatchL10n.bundle"},
    "SystemL10n": {"SystemL10n.bundle"},
    "WidgetSupportL10n": {"WidgetSupportL10n.bundle"},
    "WidgetL10n": {"WidgetL10n.bundle"},
    "CarPlayL10n": {"CarPlayL10n.bundle"},
}
APP_RESOURCE_BUNDLE_TOKENS = {"LorvexL10n.bundle"}

# Native `String(localized:defaultValue:table:bundle:)` calls carry the same
# catalog ownership in their explicit bundle token. Phase 1 migrated plurals to
# this form before the remaining helper calls are removed in Phase 2, so the
# verifier must understand both forms throughout the transition.
APP_NATIVE_BUNDLE_TOKENS = {"LorvexL10n.bundle"}
NATIVE_STRING_BUNDLE_TOKENS = {
    "MobileL10n": {"MobileL10n.bundle"},
    "WatchL10n": {"WatchL10n.bundle"},
    "SystemL10n": {"SystemL10n.bundle"},
    "WidgetL10n": {"WidgetL10n.bundle"},
    "WidgetSupportL10n": {"WidgetSupportL10n.bundle"},
    "CarPlayL10n": {"CarPlayL10n.bundle"},
}


def _iter_keyed_localization_call_details(
    text: str, opener: re.Pattern[str]
) -> list[tuple[str | None, str | None, str, int]]:
    """Yield `(key, bundle_token, body, start)` for each localization call.

    `opener` must end immediately before the first key expression while already
    inside the outer call's parentheses. The scanner tracks parenthesis depth and
    string state, so `\\(…)` interpolations and escaped quotes inside
    `defaultValue` never break the argument boundary. `key` is the first
    string-literal argument; `bundle_token` is the identifier chain passed to the
    trailing `bundle:` label, or `None` when either value is not literal/explicit.
    """
    calls: list[tuple[str | None, str | None, str, int]] = []
    n = len(text)
    for match in opener.finditer(text):
        cursor = match.end()
        depth = 1
        index = cursor
        while index < n and depth > 0:
            char = text[index]
            if char == '"':
                if text.startswith('"""', index):
                    index += 3
                    while index < n:
                        if text.startswith('"""', index):
                            index += 3
                            break
                        if text[index] == "\\":
                            index += 2
                            continue
                        index += 1
                    continue
                index += 1
                while index < n:
                    if text[index] == "\\":
                        index += 2
                        continue
                    if text[index] == '"':
                        index += 1
                        break
                    if text[index] == "\n":
                        break
                    index += 1
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        body = text[cursor:index]
        key_match = re.match(r'\s*"((?:[^"\\]|\\.)*)"', body)
        key = key_match.group(1) if key_match else None
        bundle_matches = list(re.finditer(
            r"\bbundle:\s*([A-Za-z_][A-Za-z0-9_.]*)(?=\s*(?:,|$))", body
        ))
        bundle_match = bundle_matches[-1] if bundle_matches else None
        bundle_token = bundle_match.group(1) if bundle_match else None
        calls.append((key, bundle_token, body, match.start()))
    return calls


def _iter_keyed_localization_calls(
    text: str, opener: re.Pattern[str]
) -> list[tuple[str | None, str | None]]:
    return [
        (key, bundle_token)
        for key, bundle_token, _body, _start in _iter_keyed_localization_call_details(
            text, opener
        )
    ]


def _iter_localized_string_resource_calls(text: str) -> list[tuple[str | None, str | None]]:
    return _iter_keyed_localization_calls(
        text, re.compile(r"LocalizedStringResource\s*\(")
    )


def _iter_native_localized_string_calls(text: str) -> list[tuple[str | None, str | None]]:
    return _iter_keyed_localization_calls(
        text, re.compile(r"String\s*\(\s*localized:\s*")
    )


def _iter_native_localized_text_calls(text: str) -> list[tuple[str | None, str | None]]:
    return _iter_keyed_localization_calls(text, re.compile(r"\bText\s*\("))


def localized_string_resource_bundle_keys(source_roots: list[Path]) -> dict[str, set[str]]:
    """Map each `bundle:` argument token to the set of keys referenced by a raw
    `LocalizedStringResource("key", … bundle: <token>)` literal under `source_roots`."""
    by_token: dict[str, set[str]] = {}
    for root in source_roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            for key, token in _iter_localized_string_resource_calls(
                read_swift_source(path)
            ):
                if key is None or token is None:
                    continue
                by_token.setdefault(token, set()).add(key)
    return by_token


def native_localized_string_bundle_keys(source_roots: list[Path]) -> dict[str, set[str]]:
    """Map explicit bundle tokens to native `String(localized:)` literal keys."""
    by_token: dict[str, set[str]] = {}
    for root in source_roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            for key, token in _iter_native_localized_string_calls(
                read_swift_source(path)
            ):
                if key is None or token is None:
                    continue
                by_token.setdefault(token, set()).add(key)
    return by_token


def native_localized_text_bundle_keys(source_roots: list[Path]) -> dict[str, set[str]]:
    """Map explicit bundle tokens to native `Text("key", bundle:)` literal keys."""
    by_token: dict[str, set[str]] = {}
    for root in source_roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            for key, token in _iter_native_localized_text_calls(
                read_swift_source(path)
            ):
                if key is None or token is None:
                    continue
                by_token.setdefault(token, set()).add(key)
    return by_token


LOCALIZATION_SHAPED_KEY = re.compile(
    r"^[a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$"
)


def bare_localization_text_failures(
    source_roots: list[Path] | None = None,
) -> list[str]:
    """Reject dotted catalog-shaped `Text` literals without a bundle.

    A missing catalog key cannot be looked up in ``owned_keys``, which is why a
    typo such as ``Text("settings.typo")`` used to evade both the missing-key
    and wrong-bundle checks. Verbatim/interpolated labels do not match the
    conservative dotted-key grammar and remain valid.
    """
    roots = source_roots or [ROOT / "Sources"]
    failures: list[str] = []
    opener = re.compile(r"\bText\s*\(")
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for key, bundle_token, _body, start in _iter_keyed_localization_call_details(
                text, opener
            ):
                if (
                    key is None
                    or bundle_token is not None
                    or LOCALIZATION_SHAPED_KEY.fullmatch(key) is None
                ):
                    continue
                line = text.count("\n", 0, start) + 1
                failures.append(
                    f"{path}:{line} localization-shaped Text key {key!r} must use "
                    "an explicit owning bundle"
                )
    return failures


def implicit_localized_string_resource_failures(
    source_roots: list[Path] | None = None,
) -> list[str]:
    """Reject implicit string-literal initialization of localization resources.

    `let title: LocalizedStringResource = "…"` silently resolves through the
    executable's main bundle. Framework-owned catalogs require the explicit
    initializer with table and bundle, so this form is never safe in shipping
    Lorvex source.
    """
    roots = source_roots or [ROOT / "Sources"]
    failures: list[str] = []
    pattern = re.compile(
        r"\bLocalizedStringResource\s*(?:\?)?\s*=\s*\""
    )
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{path}:{line} implicit LocalizedStringResource literal must use "
                    "an explicit table and owning bundle"
                )
    return failures


def bundle_owned_resource_keys(tokens: set[str], source_roots: list[Path]) -> set[str]:
    by_token = localized_string_resource_bundle_keys(source_roots)
    referenced: set[str] = set()
    for token in tokens:
        referenced |= by_token.get(token, set())
    return referenced


def module_owned_reference_keys(helper: str, source_roots: list[Path]) -> set[str]:
    return referenced_module_keys(helper, source_roots) | bundle_owned_resource_keys(
        MODULE_RESOURCE_BUNDLE_TOKENS.get(helper, set()), source_roots
    )


def module_reference_presence_failures(helper: str, source_roots: list[Path]) -> list[str]:
    if module_owned_reference_keys(helper, source_roots):
        return []
    return [
        f"{helper} reference scan returned zero keys; update the helper/native/resource "
        "scanner before accepting this catalog"
    ]


def module_resource_reference_failures(
    helper: str, catalog: dict[str, object], source_roots: list[Path]
) -> list[str]:
    """Assert every raw `LocalizedStringResource("key", … bundle: <token>)` whose
    `bundle:` token maps to this catalog names a key the catalog carries. Same
    treatment as `module_reference_failures`; once the key exists,
    `catalog_entry_failures` guarantees it is complete across every language."""
    referenced = bundle_owned_resource_keys(
        MODULE_RESOURCE_BUNDLE_TOKENS.get(helper, set()), source_roots
    )
    missing = sorted(referenced - catalog_keys(catalog))
    if missing:
        return [
            f"{helper} references LocalizedStringResource key(s) missing from its "
            f"catalog: {missing}"
        ]
    return []


def system_intent_bundle_qualification_failures(
    source_roots: list[Path] | None = None,
) -> list[str]:
    """Require every literal `system.*` native/resource lookup to name its catalog.

    Missing or wrong bundle/table arguments otherwise disappear from the ownership
    scanners and can silently fall back to the host app's English resources. The
    dynamic `LocalizedStringResource(stringLiteral:)` fallback used for unknown
    wire values has no catalog key and is deliberately outside this invariant.
    """
    roots = source_roots or [ROOT / "Sources" / "LorvexSystemIntents"]
    failures: list[str] = []
    openers = [
        re.compile(r"LocalizedStringResource\s*\("),
        re.compile(r"String\s*\(\s*localized:\s*"),
    ]
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for opener in openers:
                for key, bundle_token, body, start in _iter_keyed_localization_call_details(
                    text, opener
                ):
                    if key is None or not key.startswith("system."):
                        continue
                    line = text.count("\n", 0, start) + 1
                    table_match = re.search(r'\btable:\s*"([^"]+)"', body)
                    table = table_match.group(1) if table_match else None
                    if table != "Localizable":
                        failures.append(
                            f"{path}:{line} system localization key {key!r} must use "
                            f"table: \"Localizable\"; found {table!r}"
                        )
                    if bundle_token != "SystemL10n.bundle":
                        failures.append(
                            f"{path}:{line} system localization key {key!r} must use "
                            f"bundle: SystemL10n.bundle; found {bundle_token!r}"
                        )
    return failures


def mobile_native_bundle_qualification_failures(
    catalog: dict[str, object],
    source_roots: list[Path] | None = None,
) -> list[str]:
    """Require Mobile native lookups to name the framework-owned catalog.

    Every literal native String/resource lookup in LorvexMobile belongs to that
    framework. Literal Text keys are checked when the key exists in the Mobile
    catalog; verbatim punctuation and runtime Text values are deliberately
    outside the catalog-ownership invariant.
    """
    roots = source_roots or [ROOT / "Sources" / "LorvexMobile"]
    failures: list[str] = []
    owned_keys = catalog_keys(catalog)
    openers = [
        re.compile(r"LocalizedStringResource\s*\("),
        re.compile(r"String\s*\(\s*localized:\s*"),
    ]
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for opener in openers:
                for key, bundle_token, body, start in _iter_keyed_localization_call_details(
                    text, opener
                ):
                    if key is None:
                        continue
                    line = text.count("\n", 0, start) + 1
                    table_match = re.search(r'\btable:\s*"([^"]+)"', body)
                    table = table_match.group(1) if table_match else None
                    if table != "Localizable":
                        failures.append(
                            f"{path}:{line} Mobile localization key {key!r} must use "
                            f'table: "Localizable"; found {table!r}'
                        )
                    if bundle_token != "MobileL10n.bundle":
                        failures.append(
                            f"{path}:{line} Mobile localization key {key!r} must use "
                            f"bundle: MobileL10n.bundle; found {bundle_token!r}"
                        )

            for key, bundle_token, _body, start in _iter_keyed_localization_call_details(
                text, re.compile(r"\bText\s*\(")
            ):
                if key is None or key not in owned_keys:
                    continue
                if bundle_token == "MobileL10n.bundle":
                    continue
                line = text.count("\n", 0, start) + 1
                failures.append(
                    f"{path}:{line} Mobile Text key {key!r} must use "
                    f"bundle: MobileL10n.bundle; found {bundle_token!r}"
                )
    return failures


def apple_native_bundle_qualification_failures(
    catalog: dict[str, object],
    source_roots: list[Path] | None = None,
) -> list[str]:
    """Require Apple native lookups to name the app-owned catalog.

    Every literal native String/resource lookup in LorvexApple belongs to the
    app catalog. Literal Text keys are checked when the key exists in that
    catalog; verbatim punctuation and runtime Text values are deliberately
    outside the catalog-ownership invariant.
    """
    roots = source_roots or [ROOT / "Sources" / "LorvexApple"]
    failures: list[str] = []
    owned_keys = catalog_keys(catalog)
    openers = [
        re.compile(r"LocalizedStringResource\s*\("),
        re.compile(r"String\s*\(\s*localized:\s*"),
    ]
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for opener in openers:
                for key, bundle_token, body, start in _iter_keyed_localization_call_details(
                    text, opener
                ):
                    if key is None:
                        continue
                    line = text.count("\n", 0, start) + 1
                    table_match = re.search(r'\btable:\s*"([^"]+)"', body)
                    table = table_match.group(1) if table_match else None
                    if table != "Localizable":
                        failures.append(
                            f"{path}:{line} Apple localization key {key!r} must use "
                            f'table: "Localizable"; found {table!r}'
                        )
                    if bundle_token != "LorvexL10n.bundle":
                        failures.append(
                            f"{path}:{line} Apple localization key {key!r} must use "
                            f"bundle: LorvexL10n.bundle; found {bundle_token!r}"
                        )

            for key, bundle_token, _body, start in _iter_keyed_localization_call_details(
                text, re.compile(r"\bText\s*\(")
            ):
                if key is None or key not in owned_keys:
                    continue
                if bundle_token == "LorvexL10n.bundle":
                    continue
                line = text.count("\n", 0, start) + 1
                failures.append(
                    f"{path}:{line} Apple Text key {key!r} must use "
                    f"bundle: LorvexL10n.bundle; found {bundle_token!r}"
                )
    return failures


def hardcoded_system_case_display_failures(
    source_roots: list[Path] | None = None,
) -> list[str]:
    roots = source_roots or [ROOT / "Sources" / "LorvexSystemIntents"]
    failures: list[str] = []
    bare_literal_pattern = re.compile(r"^\s*\.\w+\s*:\s*\"[^\"]+\"")
    display_title_pattern = re.compile(r"DisplayRepresentation\s*\(\s*title:\s*\"[^\"]+\"")

    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            in_case_display_block = False
            for line_number, line in enumerate(read_swift_source(path).splitlines(), 1):
                if "caseDisplayRepresentations" in line:
                    in_case_display_block = True
                if in_case_display_block and bare_literal_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppEnum case display literal; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
                if in_case_display_block and display_title_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppEnum DisplayRepresentation title; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
                if in_case_display_block and line.strip() == "]":
                    in_case_display_block = False
    return failures


def hardcoded_system_intent_metadata_failures(
    source_roots: list[Path] | None = None,
    migrated_only: bool = False,
) -> list[str]:
    roots = source_roots or [
        ROOT / "Sources" / "LorvexSystemIntents",
        ROOT / "Sources" / "LorvexWidgetIntents",
    ]
    failures: list[str] = []
    title_pattern = re.compile(r"^\s*(?:public\s+)?static\s+let\s+title:\s*LocalizedStringResource\s*=\s*\"[^\"]+\"")
    description_pattern = re.compile(r"IntentDescription\s*\(\s*\"[^\"]+\"")
    description_start_pattern = re.compile(r"IntentDescription\s*\(\s*$")
    string_literal_line_pattern = re.compile(r"^\s*\"[^\"]+\"")
    parameter_title_pattern = re.compile(r"@Parameter\s*\(\s*title:\s*\"[^\"]+\"")

    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            text = read_swift_source(path)
            if migrated_only and "SystemL10n" not in text and "WidgetSupportL10n" not in text:
                continue
            in_multiline_description = False
            for line_number, line in enumerate(text.splitlines(), 1):
                if title_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppIntent title; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
                if description_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppIntent description; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
                elif in_multiline_description and string_literal_line_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppIntent description; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
                    in_multiline_description = False
                elif in_multiline_description and line.strip():
                    in_multiline_description = False
                if description_start_pattern.search(line):
                    in_multiline_description = True
                if parameter_title_pattern.search(line):
                    failures.append(
                        f"{path}:{line_number} hardcoded AppIntent parameter title; "
                        "use a bundle-qualified LocalizedStringResource"
                    )
    return failures


# --- Code default vs catalog `en` equality gate -----------------------------
#
# Every literal-default lookup resolves a key through its owning catalog, and
# the catalog value always wins over the code's `defaultValue`. If the two drift
# apart, the app ships the catalog copy while reviewers reading the call site see
# something else. This gate covers native `String(localized:)` and deferred
# `LocalizedStringResource` for LorvexApple, plus both native calls and remaining
# legacy helpers across module bundles. Defaults
# that interpolate (`\(…)`) or concatenate a non-literal, and keys whose catalog
# entry is a plural variation, are skipped because they are not directly
# comparable.

DEFAULT_VALUE_SOURCE_ROOTS = [ROOT / "Sources"]


def _parse_swift_string(text: str, pos: int) -> tuple[str, bool, int] | None:
    """Decode the Swift string literal at/after `pos`. Returns
    (value, has_interpolation, end_index) or None when no literal is present.
    Handles single-line and `\"\"\"` multiline literals (indentation strip and
    `\\`-newline line continuation)."""
    n = len(text)
    while pos < n and text[pos] in " \t\r\n":
        pos += 1
    if pos >= n or text[pos] != '"':
        return None
    if text[pos:pos + 3] == '"""':
        pos += 3
        start = pos
        while pos < n and text[pos:pos + 3] != '"""':
            pos += 1
        if pos >= n:
            return None
        raw = text[start:pos]
        end_pos = pos + 3
        lines = raw.split("\n")
        indent = lines[-1]
        body = lines[1:-1] if len(lines) >= 2 else []
        stripped = [
            line[len(indent):] if line.startswith(indent) else line.lstrip()
            for line in body
        ]
        joined = "\n".join(stripped)
        return _decode_escapes(joined, multiline=True) + (end_pos,)
    pos += 1
    buf: list[str] = []
    interp = False
    while pos < n:
        c = text[pos]
        if c == '"':
            return "".join(buf), interp, pos + 1
        if c == "\n":
            return None
        if c == "\\":
            nxt = text[pos + 1] if pos + 1 < n else ""
            if nxt == "(":
                interp = True
                depth = 0
                pos += 1
                while pos < n:
                    if text[pos] == "(":
                        depth += 1
                    elif text[pos] == ")":
                        depth -= 1
                        if depth == 0:
                            pos += 1
                            break
                    pos += 1
                continue
            decoded, advance = _decode_escape_char(text, pos)
            buf.append(decoded)
            pos += advance
            continue
        buf.append(c)
        pos += 1
    return None


def _decode_escape_char(text: str, pos: int) -> tuple[str, int]:
    """Decode a single backslash escape at `text[pos]`; returns (char, length)."""
    nxt = text[pos + 1] if pos + 1 < len(text) else ""
    simple = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}
    if nxt in simple:
        return simple[nxt], 2
    if nxt == "u" and text[pos + 2:pos + 3] == "{":
        end = text.index("}", pos + 3)
        return chr(int(text[pos + 3:end], 16)), end + 1 - pos
    return nxt, 2


def _decode_escapes(body: str, multiline: bool) -> tuple[str, bool]:
    out: list[str] = []
    interp = False
    i = 0
    m = len(body)
    while i < m:
        c = body[i]
        if c == "\\":
            nxt = body[i + 1] if i + 1 < m else ""
            if nxt == "(":
                interp = True
                depth = 0
                i += 1
                while i < m:
                    if body[i] == "(":
                        depth += 1
                    elif body[i] == ")":
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    i += 1
                continue
            if multiline and nxt == "\n":
                i += 2
                continue
            decoded, advance = _decode_escape_char(body, i)
            out.append(decoded)
            i += advance
            continue
        out.append(c)
        i += 1
    return "".join(out), interp


def _parse_concat_string(text: str, pos: int) -> tuple[str, bool, int] | None:
    """Parse a possibly `"a" + "b" + …` literal; a non-literal operand marks the
    result as non-comparable (interpolation flag True)."""
    first = _parse_swift_string(text, pos)
    if first is None:
        return None
    value, interp, end = first
    while True:
        match = re.match(r"\s*\+\s*", text[end:])
        if not match:
            break
        nxt = _parse_swift_string(text, end + match.end())
        if nxt is None:
            return value, True, end
        v2, i2, e2 = nxt
        value += v2
        interp = interp or i2
        end = e2
    return value, interp, end


def _catalog_en_values(catalog: dict[str, object]) -> dict[str, str]:
    """Plain `en` stringUnit values by key; plural-only entries are omitted."""
    out: dict[str, str] = {}
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return out
    for key, entry in strings.items():
        if not isinstance(entry, dict):
            continue
        en = entry.get("localizations", {}).get("en") if isinstance(entry.get("localizations"), dict) else None
        value = en.get("stringUnit", {}).get("value") if isinstance(en, dict) else None
        if isinstance(value, str):
            out[key] = value
    return out


def _call_site_defaults(root: Path, opener: re.Pattern[str], key_prefix: str) -> list[tuple[str, str, Path, int]]:
    """Yield (key, decoded_default, path, line) for each call site under `root`.
    `opener` matches up to and including the `(`; `key_prefix` is the regex the
    key argument is introduced by (or empty for positional module-helper keys).
    Sites whose key or default is not a comparable literal are skipped."""
    results: list[tuple[str, str, Path, int]] = []
    key_intro = re.compile(r"\s*" + key_prefix) if key_prefix else None
    for path in sorted(root.rglob("*.swift")):
        text = read_swift_source(path)
        for match in opener.finditer(text):
            cursor = match.end()
            if key_intro is not None:
                intro = key_intro.match(text, cursor)
                if not intro:
                    continue
                cursor = intro.end()
            key_parsed = _parse_swift_string(text, cursor)
            if key_parsed is None:
                continue
            key, key_interp, key_end = key_parsed
            if key_interp:
                continue
            sep = re.match(r"\s*,\s*(?:defaultValue\s*:\s*)?", text[key_end:])
            if not sep:
                continue
            default_parsed = _parse_concat_string(text, key_end + sep.end())
            if default_parsed is None:
                continue
            default, default_interp, _ = default_parsed
            if default_interp:
                continue
            line = text.count("\n", 0, match.start()) + 1
            results.append((key, default, path, line))
    return results


def _bundle_call_site_defaults(
    source_roots: list[Path],
    opener: re.Pattern[str],
    bundle_tokens: set[str],
) -> list[tuple[str, str, Path, int]]:
    """Extract literal key/default pairs from calls owned by `bundle_tokens`."""
    results: list[tuple[str, str, Path, int]] = []
    for root in source_roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            text = read_swift_source(path)
            for _key, token, body, start in _iter_keyed_localization_call_details(
                text, opener
            ):
                if token not in bundle_tokens:
                    continue
                key_parsed = _parse_swift_string(body, 0)
                if key_parsed is None:
                    continue
                key, key_interp, key_end = key_parsed
                if key_interp:
                    continue
                separator = re.match(
                    r"\s*,\s*defaultValue\s*:\s*", body[key_end:]
                )
                if separator is None:
                    continue
                default_parsed = _parse_concat_string(
                    body, key_end + separator.end()
                )
                if default_parsed is None:
                    continue
                default, default_interp, _ = default_parsed
                if default_interp:
                    continue
                line = text.count("\n", 0, start) + 1
                results.append((key, default, path, line))
    return results


def default_value_equality_failures(
    app_catalog: dict[str, object],
    module_catalogs: list[tuple[str, dict[str, object], list[Path]]],
    source_roots: list[Path] = DEFAULT_VALUE_SOURCE_ROOTS,
) -> list[str]:
    failures: list[str] = []
    checks: list[
        tuple[str, dict[str, object], list[tuple[str, str, Path, int]]]
    ] = [
        (
            "LorvexApple",
            app_catalog,
            _bundle_call_site_defaults(
                source_roots,
                re.compile(r"String\s*\(\s*localized:\s*"),
                APP_NATIVE_BUNDLE_TOKENS,
            )
            + _bundle_call_site_defaults(
                source_roots,
                re.compile(r"LocalizedStringResource\s*\("),
                APP_RESOURCE_BUNDLE_TOKENS,
            ),
        )
    ]
    for helper, catalog, roots in module_catalogs:
        legacy_sites: list[tuple[str, str, Path, int]] = []
        for root in roots:
            legacy_sites.extend(
                _call_site_defaults(
                    root,
                    re.compile(
                        rf"{re.escape(helper)}\s*\.\s*(?:string|text|resource)\s*\("
                    ),
                    "",
                )
            )
        checks.append(
            (
                helper,
                catalog,
                legacy_sites
                + _bundle_call_site_defaults(
                    roots,
                    re.compile(r"String\s*\(\s*localized:\s*"),
                    NATIVE_STRING_BUNDLE_TOKENS.get(helper, set()),
                )
                + _bundle_call_site_defaults(
                    roots,
                    re.compile(r"LocalizedStringResource\s*\("),
                    MODULE_RESOURCE_BUNDLE_TOKENS.get(helper, set()),
                ),
            )
        )

    for _module, catalog, sites in checks:
        en_values = _catalog_en_values(catalog)
        seen: set[tuple[str, str, Path, int]] = set()
        for key, default, path, line in sites:
            site = (key, default, path, line)
            if site in seen:
                continue
            seen.add(site)
            catalog_value = en_values.get(key)
            if catalog_value is None:
                continue  # missing key / plural entry — covered by other checks
            if catalog_value != default:
                try:
                    location = path.relative_to(ROOT)
                except ValueError:
                    location = path
                failures.append(
                    f"{location}:{line} catalog `en` value != code defaultValue "
                    f"for '{key}': catalog={catalog_value!r} default={default!r}"
                )
    return failures


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify Apple localization catalogs and bundle language metadata."
    )
    parser.add_argument(
        "--write-bundle-localizations",
        action="store_true",
        help=(
            "Update every Config/*-Info.plist CFBundleLocalizations from the "
            "languages discovered across all shipped string catalogs."
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    failures: list[str] = []

    catalog, load_failures = load_catalog(CATALOG_PATH)
    failures.extend(load_failures)

    loaded_module_catalogs: list[tuple[str, dict[str, object], list[Path]]] = []
    module_counts: list[str] = []
    for helper, catalog_path, source_root in MODULE_CATALOGS:
        module_catalog, module_load_failures = load_catalog(catalog_path)
        failures.extend(module_load_failures)
        if module_catalog:
            loaded_module_catalogs.append((helper, module_catalog, source_root))

    all_catalogs = [
        item for item in [catalog, *[entry[1] for entry in loaded_module_catalogs]] if item
    ]
    source_language = required_source_language(all_catalogs)
    languages = required_languages(all_catalogs)

    if catalog:
        failures.extend(catalog_structure_failures(catalog, source_language))
        failures.extend(catalog_entry_failures(catalog, REQUIRED_KEYS, languages))
        failures.extend(source_reference_failures(catalog))
        failures.extend(apple_native_bundle_qualification_failures(catalog))
        failures.extend(unreferenced_app_key_failures(catalog))

    for helper, module_catalog, source_root in loaded_module_catalogs:
        failures.extend(catalog_structure_failures(module_catalog, source_language))
        failures.extend(catalog_entry_failures(module_catalog, languages=languages))
        failures.extend(module_reference_failures(helper, module_catalog, source_root))
        failures.extend(module_resource_reference_failures(helper, module_catalog, source_root))
        failures.extend(module_reference_presence_failures(helper, source_root))
        failures.extend(
            plain_helper_plural_reference_failures(helper, module_catalog, source_root)
        )
        if helper == "MobileL10n":
            failures.extend(
                mobile_native_bundle_qualification_failures(module_catalog, source_root)
            )
            failures.extend(
                copied_source_translation_failures(
                    module_catalog,
                    languages,
                    MOBILE_IDENTICAL_TRANSLATION_ALLOWLIST,
                )
            )
        failures.extend(unreferenced_module_key_failures(helper, module_catalog))
        module_counts.append(f"{len(catalog_keys(module_catalog))} {helper}")

    if catalog:
        failures.extend(default_value_equality_failures(catalog, loaded_module_catalogs))

    if args.write_bundle_localizations:
        updated = [
            plist_path
            for plist_path in shipping_bundle_plists()
            if sync_plist_localizations(plist_path, languages, source_language)
        ]
        if updated:
            print(
                "Updated bundle localizations: "
                + ", ".join(path.name for path in updated)
            )

    for plist_path in shipping_bundle_plists():
        failures.extend(plist_localization_failures(plist_path, languages, source_language))
        failures.extend(info_plist_strings_failures(plist_path, languages))

    failures.extend(hardcoded_system_case_display_failures())
    failures.extend(hardcoded_system_intent_metadata_failures(migrated_only=True))
    failures.extend(system_intent_bundle_qualification_failures())
    failures.extend(bare_localization_text_failures())
    failures.extend(implicit_localized_string_resource_failures())

    if failures:
        print("Localization catalog verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    language_summary = "/".join(languages)
    summary = ", ".join([f"{len(catalog_keys(catalog))} app keys", *module_counts])
    summary = f"{summary}; discovered_languages={language_summary}"
    print(f"Localization catalog verification passed: {summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
