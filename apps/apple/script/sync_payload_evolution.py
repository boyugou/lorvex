#!/usr/bin/env python3
"""Cross-version evolution rules for Apple sync payload manifests.

The structural validator proves that each numbered manifest is internally
coherent.  This module proves the separate rolling-version invariant: once a
field or operation shape exists, a later manifest cannot reinterpret or remove
it.  The only automatically safe evolution for an existing entity is a new
optional top-level upsert field.  Older clients preserve that field in the
payload shadow, while newer clients must tolerate its absence from old peers.

Anything else needs an explicit version adapter or a whole-envelope hold.  The
default gate deliberately has no waiver flag: adding such a mechanism belongs
in the same reviewed change as the adapter that makes it safe.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from typing import Any


NAME = re.compile(r"^[a-z][a-z0-9_]*$")
FIELD_EVOLUTION_KEYS = {
    "introduced_in",
    "legacy_insert_default",
    "legacy_update",
    "meaning",
}

# These entities can collapse independently-authored rows with different ids
# onto one logical aggregate. Whole-row HLC arbitration cannot prove provenance
# for a field absent from an older payload, so evolution stays release-blocked
# until the same change introduces an executable entity-specific adapter and
# extends this verifier to recognize its exact field coverage.
CROSS_ID_COLLISION_ENTITIES = frozenset(
    {
        "calendar_event",
        "habit",
        "habit_reminder_policy",
        "memory",
        "tag",
        "task",
    }
)


def field_evolution_violations(
    manifest: dict[str, Any],
    *,
    manifest_version: int,
    value_validator: Callable[..., list[str]],
) -> list[str]:
    """Validate one manifest's legacy-absence metadata and typed defaults."""

    evolution = manifest.get("field_evolution")
    if not isinstance(evolution, dict):
        return [
            f"payload contract {manifest_version:03d} field_evolution must be an object"
        ]
    if manifest_version == 1 and evolution:
        return [
            "payload contract 001 field_evolution must be empty; version-1 fields "
            "have no legacy-absence history"
        ]

    violations: list[str] = []
    entities = manifest.get("entities")
    entity_map = entities if isinstance(entities, dict) else {}
    for qualified_name, entry in evolution.items():
        context = (
            f"payload contract {manifest_version:03d} "
            f"field_evolution.{qualified_name}"
        )
        if not isinstance(qualified_name, str):
            violations.append(
                f"payload contract {manifest_version:03d} field_evolution keys "
                "must use entity.field names"
            )
            continue
        parts = qualified_name.split(".")
        if len(parts) != 2 or any(NAME.fullmatch(part) is None for part in parts):
            violations.append(f"{context} must use a canonical entity.field key")
            continue
        entity_name, field_name = parts

        if entity_name in CROSS_ID_COLLISION_ENTITIES:
            violations.append(
                f"{context} is unsafe on a cross-id collision aggregate; "
                "ship an executable entity-specific collision adapter and "
                "cross-id convergence probe before enabling this field evolution"
            )

        if not isinstance(entry, dict) or set(entry) != FIELD_EVOLUTION_KEYS:
            found = sorted(entry) if isinstance(entry, dict) else type(entry).__name__
            violations.append(
                f"{context} must contain exactly {sorted(FIELD_EVOLUTION_KEYS)}; "
                f"found {found}"
            )
            continue

        introduced_in = entry["introduced_in"]
        if (
            type(introduced_in) is not int
            or introduced_in < 2
            or introduced_in > manifest_version
        ):
            violations.append(
                f"{context}.introduced_in must be an integer from 2 through "
                f"{manifest_version}; found {introduced_in!r}"
            )
        if entry["legacy_update"] != "preserve":
            violations.append(
                f"{context}.legacy_update must equal 'preserve'; found "
                f"{entry['legacy_update']!r}"
            )
        meaning = entry["meaning"]
        if not isinstance(meaning, str) or not meaning.strip():
            violations.append(f"{context}.meaning must be a non-empty string")

        entity = entity_map.get(entity_name)
        fields = entity.get("fields") if isinstance(entity, dict) else None
        if not isinstance(fields, dict) or field_name not in fields:
            violations.append(
                f"{context} references unknown wire field {qualified_name!r}"
            )
            continue
        violations.extend(
            value_validator(
                entry["legacy_insert_default"],
                fields[field_name],
                context=f"{context}.legacy_insert_default",
            )
        )
    return violations


def _context(previous_version: int, current_version: int, entity: str) -> str:
    return (
        f"payload contract {previous_version:03d}->{current_version:03d} "
        f"entity {entity}"
    )


def adjacent_contract_violations(
    previous: dict[str, Any],
    current: dict[str, Any],
    *,
    previous_version: int,
    current_version: int,
) -> list[str]:
    """Reject non-monotonic changes between two structurally valid manifests."""

    violations: list[str] = []
    previous_entities = previous["entities"]
    current_entities = current["entities"]
    previous_reserved = previous["shadow_reserved_keys"]
    current_reserved = current["shadow_reserved_keys"]
    previous_evolution = previous["field_evolution"]
    current_evolution = current["field_evolution"]

    removed_evolution = sorted(set(previous_evolution) - set(current_evolution))
    if removed_evolution:
        violations.append(
            f"payload contract {previous_version:03d}->{current_version:03d} "
            f"removed historical field_evolution entries {removed_evolution}; "
            "legacy-absence semantics are immutable"
        )
    for key in sorted(set(previous_evolution) & set(current_evolution)):
        if previous_evolution[key] != current_evolution[key]:
            violations.append(
                f"payload contract {previous_version:03d}->{current_version:03d} "
                f"mutated historical field_evolution entry {key!r}; "
                "legacy-absence semantics are immutable"
            )

    removed_entities = sorted(set(previous_entities) - set(current_entities))
    if removed_entities:
        violations.append(
            f"payload contract {previous_version:03d}->{current_version:03d} "
            f"removed existing entities {removed_entities}; released entities are permanent"
        )

    required_evolution: set[str] = set()
    for entity_name in sorted(set(previous_entities) & set(current_entities)):
        before = previous_entities[entity_name]
        after = current_entities[entity_name]
        context = _context(previous_version, current_version, entity_name)

        before_fields = before["fields"]
        after_fields = after["fields"]
        removed_fields = sorted(set(before_fields) - set(after_fields))
        if removed_fields:
            violations.append(
                f"{context} removed existing fields {removed_fields}; deprecated wire keys "
                "must remain parseable and emitted"
            )

        for field_name in sorted(set(before_fields) & set(after_fields)):
            if before_fields[field_name] != after_fields[field_name]:
                violations.append(
                    f"{context} changed recursive wire spec for existing field "
                    f"{field_name!r}; type, nullability, format, enum, range, and nested "
                    "shape are immutable without an explicit version adapter"
                )

        new_fields = set(after_fields) - set(before_fields)
        required_evolution.update(
            f"{entity_name}.{field_name}" for field_name in new_fields
        )
        old_reserved = set(previous_reserved.get(entity_name, []))
        new_reserved = set(current_reserved.get(entity_name, []))
        removed_reserved = sorted(old_reserved - new_reserved)
        reserved_wire_collisions = sorted(new_fields & new_reserved)
        if removed_reserved or reserved_wire_collisions:
            violations.append(
                f"{context} changed shadow-reserved spellings unsafely "
                f"(removed={removed_reserved}, new_wire_collisions={reserved_wire_collisions}); "
                "a key stripped by any older client can never become a wire field"
            )
        before_upsert = before["operations"]["upsert"]
        after_upsert = after["operations"]["upsert"]
        if before_upsert["required_keys"] != after_upsert["required_keys"]:
            violations.append(
                f"{context} changed upsert required-key presence semantics; existing required "
                "keys are immutable and new fields must be optional"
            )

        expected_optional = set(before_upsert["optional_keys"]) | new_fields
        actual_optional = set(after_upsert["optional_keys"])
        if actual_optional != expected_optional:
            added = sorted(actual_optional - set(before_upsert["optional_keys"]))
            removed = sorted(set(before_upsert["optional_keys"]) - actual_optional)
            missing_new = sorted(new_fields - actual_optional)
            violations.append(
                f"{context} has non-additive upsert optional keys "
                f"(added={added}, removed={removed}, new_fields_not_optional={missing_new}); "
                "every new top-level field must be optional and existing presence is immutable"
            )

        before_synthetic = set(before["synthetic_keys"])
        after_synthetic = set(after["synthetic_keys"])
        removed_synthetic = sorted(before_synthetic - after_synthetic)
        reclassified_existing = sorted((after_synthetic - before_synthetic) - new_fields)
        if removed_synthetic or reclassified_existing:
            violations.append(
                f"{context} changed synthetic-field classification "
                f"(removed={removed_synthetic}, reclassified_existing={reclassified_existing})"
            )

        before_shapes = {
            shape["name"]: shape for shape in before["operations"]["delete"]["shapes"]
        }
        after_shapes = {
            shape["name"]: shape for shape in after["operations"]["delete"]["shapes"]
        }
        if set(before_shapes) != set(after_shapes):
            violations.append(
                f"{context} changed delete-shape inventory "
                f"(before={sorted(before_shapes)}, after={sorted(after_shapes)}); an existing "
                "entity cannot gain, remove, or rename a delete semantic"
            )

        for shape_name in sorted(set(before_shapes) & set(after_shapes)):
            old_shape = before_shapes[shape_name]
            new_shape = after_shapes[shape_name]
            if old_shape.get("marker_key") != new_shape.get("marker_key"):
                violations.append(
                    f"{context} delete shape {shape_name!r} changed marker_key"
                )
            if old_shape["required_keys"] != new_shape["required_keys"]:
                violations.append(
                    f"{context} delete shape {shape_name!r} changed required-key semantics"
                )
            old_optional = set(old_shape["optional_keys"])
            new_optional = set(new_shape["optional_keys"])
            removed_optional = sorted(old_optional - new_optional)
            unrelated_additions = sorted((new_optional - old_optional) - new_fields)
            if removed_optional or unrelated_additions:
                violations.append(
                    f"{context} delete shape {shape_name!r} changed optional keys outside "
                    f"new top-level fields (removed={removed_optional}, "
                    f"unrelated_additions={unrelated_additions})"
                )

    new_evolution = set(current_evolution) - set(previous_evolution)
    missing_evolution = sorted(required_evolution - new_evolution)
    unexpected_evolution = sorted(new_evolution - required_evolution)
    if missing_evolution or unexpected_evolution:
        violations.append(
            f"payload contract {previous_version:03d}->{current_version:03d} has "
            "non-canonical field_evolution inventory "
            f"(missing={missing_evolution}, unexpected={unexpected_evolution}); each field "
            "added to an existing entity needs exactly one new metadata entry, while fields "
            "of a new entity need none"
        )
    for qualified_name in sorted(required_evolution & set(current_evolution)):
        entry = current_evolution[qualified_name]
        if entry.get("introduced_in") != current_version:
            violations.append(
                f"payload contract {previous_version:03d}->{current_version:03d} "
                f"field_evolution entry {qualified_name!r} introduced_in must equal "
                f"{current_version}"
            )

    return violations
