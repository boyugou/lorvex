#!/usr/bin/env python3
"""Verify the Apple sync payload's versioned operation-shape contracts.

``LorvexVersion.payloadSchemaVersion`` is the wire compatibility boundary used
by both outbound envelopes and inbound apply.  A field added to or removed from
an entity payload is therefore a protocol change, even when no SQLite DDL
changes.  The numbered manifests in ``schema/sync_payload/`` make that boundary
explicit and reviewable:

* files are contiguous from ``001.json`` through the Swift version constant;
* every file is canonical JSON with sorted, duplicate-free operation shapes and
  recursive JSON types, nullability, formats, enums, numeric units/ranges, and
  explicit nested object/array policies;
* every numbered manifest pins an independently checked-in canonical golden
  envelope set by SHA-256, including one populated upsert for every entity;
* the current manifest is exercised against final production-funnel envelopes by
  ``SyncPayloadContractTests`` and ``SyncFieldRoundTripProbeTests``;
* once ``schema/migration_policy.json`` is armed, every released manifest hash
  captured in ``frozen_baseline.sync_payload_contracts`` is immutable.

The schema freeze's ``--arm`` operation imports this module and freezes the
payload contracts atomically with the SQLite baseline.  This script is a
read-only verification gate; it never rewrites a manifest or policy file.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
import unicodedata
from datetime import date, datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sync_payload_evolution import (
    adjacent_contract_violations,
    field_evolution_violations,
)


REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_DIR = REPO_ROOT / "schema" / "sync_payload"
EMBEDDED_MANIFEST_DIR = (
    REPO_ROOT
    / "apps"
    / "apple"
    / "core"
    / "Sources"
    / "LorvexSync"
    / "Resources"
    / "SyncPayloadContracts"
)
VERSION_SOURCE_PATH = (
    REPO_ROOT / "apps" / "apple" / "core" / "Sources" / "LorvexDomain" / "Version.swift"
)
POLICY_PATH = REPO_ROOT / "schema" / "migration_policy.json"

MANIFEST_NAME = re.compile(r"^(\d{3,})\.json$")
ENTITY_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
VERSION_DECLARATION = re.compile(
    r"^\s*public\s+static\s+let\s+payloadSchemaVersion\s*:\s*UInt32\s*=\s*(\d+)\s*$",
    re.MULTILINE,
)
CONTRACT_FORMAT = 3
TOP_LEVEL_KEYS = {
    "contract_format",
    "entities",
    "field_evolution",
    "golden_fixture",
    "golden_fixture_sha256",
    "payload_schema_version",
    "shadow_reserved_keys",
}
ENTITY_KEYS = {"fields", "operations", "synthetic_keys"}
OPERATION_KEYS = {"delete", "upsert"}
UPSERT_KEYS = {"optional_keys", "required_keys"}
DELETE_KEYS = {"shapes"}
DELETE_SHAPE_REQUIRED_KEYS = {"name", "optional_keys", "required_keys"}
DELETE_SHAPE_OPTIONAL_KEYS = {"marker_key"}
JSON_TYPES = {"array", "boolean", "integer", "null", "number", "object", "string"}
JSON_TYPE_ORDER = ["array", "boolean", "integer", "null", "number", "object", "string"]
FIELD_REQUIRED_KEYS = {"types"}
FIELD_OPTIONAL_KEYS = {
    "additional_properties",
    "enum",
    "format",
    "items",
    "maximum",
    "max_items",
    "minimum",
    "min_items",
    "properties",
    "required_properties",
    "unit",
    "unique_items",
}
STRING_FORMATS = {
    "calendar-url",
    "civil-date",
    "hlc",
    "hh-mm",
    "iana-time-zone",
    "json-array-string",
    "json-object-string",
    "json-string",
    "rfc3339-utc",
    "uuid",
    "uuid-or-inbox",
}
NUMERIC_UNITS = {"minute-of-day", "minutes"}
GOLDEN_TOP_LEVEL_KEYS = {"envelopes", "payload_schema_version"}
GOLDEN_ENVELOPE_KEYS = {
    "device_id",
    "entity_id",
    "entity_type",
    "operation",
    "payload",
    "version",
}

REMEDIATION = (
    "Do not edit a released payload contract. Restore the frozen manifest, bump "
    "LorvexVersion.payloadSchemaVersion, copy the previous manifest to the next "
    "contiguous NNN.json, and add only compatible entities or optional fields. "
    "Every field added to an existing entity also needs immutable field_evolution "
    "legacy-absence metadata."
)


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _reject_nonfinite_json_constant(token: str) -> None:
    raise ValueError(f"non-finite JSON number {token!r} is forbidden")


def _parse_finite_json_float(token: str) -> float:
    value = float(token)
    if not math.isfinite(value):
        raise ValueError(f"non-finite JSON number {token!r} is forbidden")
    return value


def strict_json_loads(raw: str | bytes) -> Any:
    """Parse JSON while rejecting named and exponent-overflow nonfinite numbers."""
    return json.loads(
        raw,
        parse_constant=_reject_nonfinite_json_constant,
        parse_float=_parse_finite_json_float,
    )


def _read_swift_version(path: Path) -> tuple[int | None, list[str]]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return None, [f"cannot read Swift payload version source {path}: {error}"]
    matches = VERSION_DECLARATION.findall(source)
    if len(matches) != 1:
        return None, [
            f"{path} must declare exactly one literal "
            "`public static let payloadSchemaVersion: UInt32 = N`; "
            f"found {len(matches)}"
        ]
    version = int(matches[0])
    if version < 1:
        return None, [f"payloadSchemaVersion must be at least 1; found {version}"]
    return version, []


def _validate_sorted_field_array(
    value: Any, *, path: Path, context: str, allow_empty: bool
) -> list[str]:
    if not isinstance(value, list) or (not allow_empty and not value):
        qualifier = "an array" if allow_empty else "a non-empty array"
        return [f"payload contract {path.name} {context} must be {qualifier}"]
    if any(
        not isinstance(field, str) or ENTITY_NAME.fullmatch(field) is None
        for field in value
    ):
        return [f"payload contract {path.name} {context} has an invalid field name"]
    if value != sorted(set(value)):
        return [f"payload contract {path.name} {context} must be sorted unique"]
    return []


def _validate_field_spec(spec: Any, *, path: Path, context: str) -> list[str]:
    """Validate one recursive contract-format-3 JSON value specification."""
    if not isinstance(spec, dict):
        return [f"payload contract {path.name} {context} must be an object"]
    allowed = FIELD_REQUIRED_KEYS | FIELD_OPTIONAL_KEYS
    if not FIELD_REQUIRED_KEYS.issubset(spec) or not set(spec).issubset(allowed):
        return [
            f"payload contract {path.name} {context} must contain types and only "
            f"{sorted(allowed)}; found {sorted(spec)}"
        ]

    violations: list[str] = []
    types = spec.get("types")
    if (
        not isinstance(types, list)
        or not types
        or any(not isinstance(value, str) or value not in JSON_TYPES for value in types)
        or types != [value for value in JSON_TYPE_ORDER if value in set(types)]
    ):
        violations.append(
            f"payload contract {path.name} {context} types must be non-empty, unique, "
            f"and ordered as {JSON_TYPE_ORDER}"
        )
        types_set: set[str] = set()
    else:
        types_set = set(types)

    enum = spec.get("enum")
    if enum is not None:
        if not isinstance(enum, list) or not enum or enum != sorted(set(enum)):
            violations.append(
                f"payload contract {path.name} {context} enum must be sorted unique and non-empty"
            )
        elif any(not isinstance(value, str) for value in enum) or "string" not in types_set:
            violations.append(
                f"payload contract {path.name} {context} enum currently supports string values only"
            )

    format_name = spec.get("format")
    if format_name is not None:
        if not isinstance(format_name, str) or format_name not in STRING_FORMATS:
            violations.append(
                f"payload contract {path.name} {context} has unknown format {format_name!r}"
            )
        elif "string" not in types_set:
            violations.append(
                f"payload contract {path.name} {context} format requires string in types"
            )

    for bound in ("minimum", "maximum"):
        value = spec.get(bound)
        if value is not None and (type(value) not in (int, float) or not types_set & {"integer", "number"}):
            violations.append(
                f"payload contract {path.name} {context} {bound} requires a numeric type"
            )
    minimum = spec.get("minimum")
    maximum = spec.get("maximum")
    if minimum is not None and maximum is not None and minimum > maximum:
        violations.append(
            f"payload contract {path.name} {context} minimum must not exceed maximum"
        )

    unit = spec.get("unit")
    if unit is not None:
        if not isinstance(unit, str) or unit not in NUMERIC_UNITS:
            violations.append(
                f"payload contract {path.name} {context} has unknown numeric unit {unit!r}"
            )
        if not types_set & {"integer", "number"}:
            violations.append(
                f"payload contract {path.name} {context} unit requires a numeric type"
            )
        if unit == "minute-of-day" and (minimum != 0 or maximum != 1440):
            violations.append(
                f"payload contract {path.name} {context} minute-of-day must declare "
                "minimum=0 and maximum=1440"
            )

    items = spec.get("items")
    if items is not None:
        if "array" not in types_set:
            violations.append(
                f"payload contract {path.name} {context} items requires array in types"
            )
        violations.extend(
            _validate_field_spec(items, path=path, context=f"{context}.items")
        )
    for bound in ("min_items", "max_items"):
        value = spec.get(bound)
        if value is not None and (
            type(value) is not int or value < 0 or "array" not in types_set
        ):
            violations.append(
                f"payload contract {path.name} {context} {bound} must be a nonnegative "
                "integer on an array"
            )
    if (
        spec.get("min_items") is not None
        and spec.get("max_items") is not None
        and spec["min_items"] > spec["max_items"]
    ):
        violations.append(
            f"payload contract {path.name} {context} min_items must not exceed max_items"
        )
    if "unique_items" in spec and (
        type(spec["unique_items"]) is not bool or "array" not in types_set
    ):
        violations.append(
            f"payload contract {path.name} {context} unique_items must be boolean on an array"
        )

    properties = spec.get("properties")
    required_properties = spec.get("required_properties")
    additional = spec.get("additional_properties")
    if "object" in types_set and properties is None:
        violations.append(
            f"payload contract {path.name} {context} includes object in types and must "
            "explicitly declare properties, required_properties, and additional_properties; "
            "use an empty properties object plus additional_properties=true for an "
            "intentionally open object"
        )
    if properties is not None:
        if "object" not in types_set or not isinstance(properties, dict):
            violations.append(
                f"payload contract {path.name} {context} properties requires an object type"
            )
        else:
            if list(properties) != sorted(properties):
                violations.append(
                    f"payload contract {path.name} {context} properties must be sorted"
                )
            for key, child in properties.items():
                if not isinstance(key, str) or ENTITY_NAME.fullmatch(key) is None:
                    violations.append(
                        f"payload contract {path.name} {context} has invalid property {key!r}"
                    )
                    continue
                violations.extend(
                    _validate_field_spec(
                        child, path=path, context=f"{context}.properties.{key}"
                    )
                )
        violations.extend(
            _validate_sorted_field_array(
                required_properties,
                path=path,
                context=f"{context} required_properties",
                allow_empty=True,
            )
        )
        if isinstance(properties, dict) and isinstance(required_properties, list):
            outside = sorted(set(required_properties) - set(properties))
            if outside:
                violations.append(
                    f"payload contract {path.name} {context} required properties are undeclared: "
                    f"{outside}"
                )
        if type(additional) is not bool:
            violations.append(
                f"payload contract {path.name} {context} with properties must declare "
                "additional_properties as boolean"
            )
    elif required_properties is not None or additional is not None:
        violations.append(
            f"payload contract {path.name} {context} object policy requires properties"
        )
    return violations


def _json_type(value: Any) -> str:
    if value is None:
        return "null"
    if type(value) is bool:
        return "boolean"
    if type(value) is int:
        return "integer"
    if type(value) is float:
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def _format_valid(value: str, format_name: str) -> bool:
    try:
        if format_name == "civil-date":
            return len(value) == 10 and date.fromisoformat(value).isoformat() == value
        if format_name == "hh-mm":
            return re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value) is not None
        if format_name == "rfc3339-utc":
            if re.fullmatch(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z", value
            ) is None:
                return False
            return (
                datetime.fromisoformat(value[:-1] + "+00:00").isoformat(
                    timespec="milliseconds"
                )
                == value[:-1] + "+00:00"
            )
        if format_name == "hlc":
            return re.fullmatch(r"\d{13}_\d{4}_[0-9a-f]{16}", value) is not None
        if format_name == "uuid":
            return re.fullmatch(
                r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                value,
            ) is not None
        if format_name == "uuid-or-inbox":
            return value == "inbox" or _format_valid(value, "uuid")
        if format_name == "iana-time-zone":
            ZoneInfo(value)
            return True
        if format_name == "calendar-url":
            if any(
                character.isspace()
                or unicodedata.category(character) in {"Cc", "Cf"}
                for character in value
            ):
                return False
            return value.startswith(("http://", "https://", "webcal://"))
        if format_name in {"json-string", "json-array-string", "json-object-string"}:
            parsed = strict_json_loads(value)
            if format_name == "json-array-string":
                return isinstance(parsed, list)
            if format_name == "json-object-string":
                return isinstance(parsed, dict)
            return True
    except (ValueError, TypeError, ZoneInfoNotFoundError, json.JSONDecodeError):
        return False
    return False


def field_value_violations(value: Any, spec: dict, *, context: str) -> list[str]:
    """Validate one actual JSON value against a structurally-valid field spec."""
    violations: list[str] = []
    actual_type = _json_type(value)
    if type(value) is float and not math.isfinite(value):
        return [f"{context} contains a non-finite JSON number"]
    if actual_type not in spec["types"]:
        return [
            f"{context} has JSON type {actual_type}; allowed types are {spec['types']}"
        ]
    if value is None:
        return []
    if "enum" in spec and value not in spec["enum"]:
        violations.append(f"{context} value {value!r} is outside enum {spec['enum']}")
    if "format" in spec and isinstance(value, str) and not _format_valid(value, spec["format"]):
        violations.append(f"{context} value {value!r} violates format {spec['format']}")
    if actual_type in {"integer", "number"}:
        if "minimum" in spec and value < spec["minimum"]:
            violations.append(f"{context} value {value} is below minimum {spec['minimum']}")
        if "maximum" in spec and value > spec["maximum"]:
            violations.append(f"{context} value {value} exceeds maximum {spec['maximum']}")
    if isinstance(value, list):
        if "min_items" in spec and len(value) < spec["min_items"]:
            violations.append(f"{context} has fewer than {spec['min_items']} items")
        if "max_items" in spec and len(value) > spec["max_items"]:
            violations.append(f"{context} has more than {spec['max_items']} items")
        if spec.get("unique_items"):
            encoded = [json.dumps(item, sort_keys=True, ensure_ascii=False) for item in value]
            if len(encoded) != len(set(encoded)):
                violations.append(f"{context} items must be unique")
        if "items" in spec:
            for index, item in enumerate(value):
                violations.extend(
                    field_value_violations(item, spec["items"], context=f"{context}[{index}]")
                )
    if isinstance(value, dict) and "properties" in spec:
        properties = spec["properties"]
        missing = sorted(set(spec["required_properties"]) - set(value))
        if missing:
            violations.append(f"{context} is missing required properties {missing}")
        extra = sorted(set(value) - set(properties))
        if extra and not spec["additional_properties"]:
            violations.append(f"{context} has unexpected properties {extra}")
        for key in set(value) & set(properties):
            violations.extend(
                field_value_violations(
                    value[key], properties[key], context=f"{context}.{key}"
                )
            )
    return violations


def _validate_entities(path: Path, entities: Any) -> list[str]:
    violations: list[str] = []
    if not isinstance(entities, dict) or not entities:
        return [f"payload contract {path} entities must be a non-empty object"]

    for entity, contract in entities.items():
        if not isinstance(entity, str) or ENTITY_NAME.fullmatch(entity) is None:
            violations.append(
                f"payload contract {path.name} has invalid entity name {entity!r}"
            )
            continue
        context = f"entity {entity}"
        used_fields: set[str] = set()
        if not isinstance(contract, dict) or set(contract) != ENTITY_KEYS:
            found = sorted(contract) if isinstance(contract, dict) else type(contract).__name__
            violations.append(
                f"payload contract {path.name} {context} must contain exactly "
                f"{sorted(ENTITY_KEYS)}; found {found}"
            )
            continue

        synthetic = contract.get("synthetic_keys")
        violations.extend(
            _validate_sorted_field_array(
                synthetic, path=path, context=f"{context} synthetic_keys", allow_empty=True
            )
        )

        fields = contract.get("fields")
        if not isinstance(fields, dict) or not fields:
            violations.append(
                f"payload contract {path.name} {context} fields must be a non-empty object"
            )
            fields = {}
        else:
            if list(fields) != sorted(fields):
                violations.append(
                    f"payload contract {path.name} {context} fields must be sorted"
                )
            for field, spec in fields.items():
                if not isinstance(field, str) or ENTITY_NAME.fullmatch(field) is None:
                    violations.append(
                        f"payload contract {path.name} {context} has invalid field name {field!r}"
                    )
                    continue
                violations.extend(
                    _validate_field_spec(
                        spec, path=path, context=f"{context} fields.{field}"
                    )
                )

        operations = contract.get("operations")
        if not isinstance(operations, dict) or set(operations) != OPERATION_KEYS:
            found = sorted(operations) if isinstance(operations, dict) else type(operations).__name__
            violations.append(
                f"payload contract {path.name} {context} operations must contain exactly "
                f"{sorted(OPERATION_KEYS)}; found {found}"
            )
            continue

        upsert = operations.get("upsert")
        if not isinstance(upsert, dict) or set(upsert) != UPSERT_KEYS:
            found = sorted(upsert) if isinstance(upsert, dict) else type(upsert).__name__
            violations.append(
                f"payload contract {path.name} {context} upsert must contain exactly "
                f"{sorted(UPSERT_KEYS)}; found {found}"
            )
            upsert_required: list[str] = []
            upsert_optional: list[str] = []
        else:
            upsert_required = upsert.get("required_keys")
            upsert_optional = upsert.get("optional_keys")
            violations.extend(
                _validate_sorted_field_array(
                    upsert_required,
                    path=path,
                    context=f"{context} upsert required_keys",
                    allow_empty=False,
                )
            )
            violations.extend(
                _validate_sorted_field_array(
                    upsert_optional,
                    path=path,
                    context=f"{context} upsert optional_keys",
                    allow_empty=True,
                )
            )
            if isinstance(upsert_required, list) and isinstance(upsert_optional, list):
                overlap = sorted(set(upsert_required) & set(upsert_optional))
                if overlap:
                    violations.append(
                        f"payload contract {path.name} {context} upsert required/optional "
                        f"keys overlap: {overlap}"
                    )
                if "version" not in upsert_required:
                    violations.append(
                        f"payload contract {path.name} {context} upsert must require version"
                    )
                if isinstance(synthetic, list):
                    outside = sorted(set(synthetic) - set(upsert_required) - set(upsert_optional))
                    if outside:
                        violations.append(
                            f"payload contract {path.name} {context} synthetic keys are not "
                            f"declared by upsert: {outside}"
                        )
                declared = set(upsert_required) | set(upsert_optional)
                used_fields.update(declared)
                if not declared.issubset(fields):
                    violations.append(
                        f"payload contract {path.name} {context} upsert keys have no typed "
                        f"field declaration: {sorted(declared - set(fields))}"
                    )

        delete = operations.get("delete")
        if not isinstance(delete, dict) or set(delete) != DELETE_KEYS:
            found = sorted(delete) if isinstance(delete, dict) else type(delete).__name__
            violations.append(
                f"payload contract {path.name} {context} delete must contain exactly "
                f"{sorted(DELETE_KEYS)}; found {found}"
            )
            continue
        shapes = delete.get("shapes")
        if not isinstance(shapes, list):
            violations.append(
                f"payload contract {path.name} {context} delete shapes must be an array"
            )
            continue
        shape_names: list[str] = []
        for index, shape in enumerate(shapes):
            shape_context = f"{context} delete shape[{index}]"
            allowed_shape_keys = DELETE_SHAPE_REQUIRED_KEYS | DELETE_SHAPE_OPTIONAL_KEYS
            if (
                not isinstance(shape, dict)
                or not DELETE_SHAPE_REQUIRED_KEYS.issubset(shape)
                or not set(shape).issubset(allowed_shape_keys)
            ):
                found = sorted(shape) if isinstance(shape, dict) else type(shape).__name__
                violations.append(
                    f"payload contract {path.name} {shape_context} must contain "
                    f"{sorted(DELETE_SHAPE_REQUIRED_KEYS)} with optional marker_key; "
                    f"found {found}"
                )
                continue
            name = shape.get("name")
            if not isinstance(name, str) or ENTITY_NAME.fullmatch(name) is None:
                violations.append(
                    f"payload contract {path.name} {shape_context} has invalid name {name!r}"
                )
            else:
                shape_names.append(name)
            required = shape.get("required_keys")
            optional = shape.get("optional_keys")
            violations.extend(
                _validate_sorted_field_array(
                    required,
                    path=path,
                    context=f"{shape_context} required_keys",
                    allow_empty=False,
                )
            )
            violations.extend(
                _validate_sorted_field_array(
                    optional,
                    path=path,
                    context=f"{shape_context} optional_keys",
                    allow_empty=True,
                )
            )
            if isinstance(required, list) and isinstance(optional, list):
                used_fields.update(required)
                used_fields.update(optional)
                overlap = sorted(set(required) & set(optional))
                if overlap:
                    violations.append(
                        f"payload contract {path.name} {shape_context} required/optional "
                        f"keys overlap: {overlap}"
                    )
                if "version" not in required:
                    violations.append(
                        f"payload contract {path.name} {shape_context} must require version"
                    )
                outside = sorted((set(required) | set(optional)) - set(fields))
                if outside:
                    violations.append(
                        f"payload contract {path.name} {shape_context} keys have no typed "
                        f"field declaration: {outside}"
                    )
            marker_key = shape.get("marker_key")
            if marker_key is not None:
                if not isinstance(marker_key, str) or ENTITY_NAME.fullmatch(marker_key) is None:
                    violations.append(
                        f"payload contract {path.name} {shape_context} has invalid marker_key"
                    )
                elif not isinstance(required, list) or marker_key not in required:
                    violations.append(
                        f"payload contract {path.name} {shape_context} marker_key "
                        f"{marker_key!r} must be required by that exact shape"
                    )
        if shape_names != sorted(set(shape_names)):
            violations.append(
                f"payload contract {path.name} {context} delete shape names must be sorted unique"
            )
        unused_fields = sorted(set(fields) - used_fields)
        if unused_fields:
            violations.append(
                f"payload contract {path.name} {context} typed fields are unused by every "
                f"operation shape: {unused_fields}"
            )
    return violations


def _validate_shadow_reserved_keys(
    path: Path, entities: Any, reserved: Any
) -> list[str]:
    """Validate non-wire spellings an older payload shadow must keep stripping."""
    if not isinstance(reserved, dict):
        return [f"payload contract {path.name} shadow_reserved_keys must be an object"]
    violations: list[str] = []
    if list(reserved) != sorted(reserved):
        violations.append(
            f"payload contract {path.name} shadow_reserved_keys must be sorted"
        )
    entity_map = entities if isinstance(entities, dict) else {}
    for entity, keys in reserved.items():
        if entity not in entity_map:
            violations.append(
                f"payload contract {path.name} shadow_reserved_keys has unknown entity {entity!r}"
            )
            continue
        entity_contract = entity_map[entity]
        if not isinstance(entity_contract, dict):
            violations.append(
                f"payload contract {path.name} shadow_reserved_keys references malformed "
                f"entity {entity!r}"
            )
            continue
        key_violations = _validate_sorted_field_array(
            keys,
            path=path,
            context=f"shadow_reserved_keys.{entity}",
            allow_empty=False,
        )
        violations.extend(key_violations)
        if not key_violations:
            fields = entity_contract.get("fields", {})
            collision = sorted(set(keys) & set(fields if isinstance(fields, dict) else {}))
            if collision:
                violations.append(
                    f"payload contract {path.name} entity {entity} reserves active wire fields "
                    f"{collision}; reserved shadow keys must remain non-wire"
                )
    return violations


def _payload_violations(
    payload: Any, *, entity_name: str, operation: str, entity: dict, context: str
) -> list[str]:
    if not isinstance(payload, dict):
        return [f"{context} payload must be an object"]
    operations = entity["operations"]
    fields = entity["fields"]
    candidates: list[tuple[list[str], list[str], str]] = []
    if operation == "upsert":
        shape = operations["upsert"]
        candidates.append((shape["required_keys"], shape["optional_keys"], "upsert"))
    elif operation == "delete":
        for shape in operations["delete"]["shapes"]:
            candidates.append(
                (shape["required_keys"], shape["optional_keys"], shape["name"])
            )
    else:
        return [f"{context} operation must be upsert or delete"]
    if not candidates:
        return [f"{context} operation {operation} is not supported for {entity_name}"]

    actual = set(payload)
    key_matches = [
        candidate
        for candidate in candidates
        if set(candidate[0]).issubset(actual)
        and actual.issubset(set(candidate[0]) | set(candidate[1]))
    ]
    if not key_matches:
        return [
            f"{context} keys {sorted(actual)} match no {operation} shape for {entity_name}"
        ]
    violations: list[str] = []
    for key, value in payload.items():
        violations.extend(
            field_value_violations(value, fields[key], context=f"{context}.payload.{key}")
        )
    return violations


def _validate_golden_fixture(
    manifest_path: Path, manifest: dict, file_version: int
) -> list[str]:
    fixture_name = manifest.get("golden_fixture")
    expected_sha = manifest.get("golden_fixture_sha256")
    if not isinstance(fixture_name, str) or not re.fullmatch(
        rf"fixtures/{file_version:03d}\.golden\.json", fixture_name
    ):
        return [
            f"payload contract {manifest_path.name} golden_fixture must equal "
            f"fixtures/{file_version:03d}.golden.json"
        ]
    if not isinstance(expected_sha, str) or re.fullmatch(r"[0-9a-f]{64}", expected_sha) is None:
        return [
            f"payload contract {manifest_path.name} golden_fixture_sha256 must be lowercase SHA-256"
        ]
    fixture_path = manifest_path.parent / fixture_name
    try:
        raw = fixture_path.read_bytes()
        fixture = strict_json_loads(raw)
    except (OSError, UnicodeError, ValueError) as error:
        return [f"cannot parse payload golden fixture {fixture_path}: {error}"]

    violations: list[str] = []
    actual_sha = hashlib.sha256(raw).hexdigest()
    if actual_sha != expected_sha:
        violations.append(
            f"payload contract {manifest_path.name} golden fixture SHA changed "
            f"(declared {expected_sha[:16]}..., actual {actual_sha[:16]}...)"
        )
    if raw != canonical_json_bytes(fixture):
        violations.append(
            f"payload golden fixture {fixture_path} is not canonical JSON "
            "(UTF-8, sorted keys, two-space indent, trailing newline)"
        )
    if not isinstance(fixture, dict) or set(fixture) != GOLDEN_TOP_LEVEL_KEYS:
        found = sorted(fixture) if isinstance(fixture, dict) else type(fixture).__name__
        return violations + [
            f"payload golden fixture {fixture_path} must contain exactly "
            f"{sorted(GOLDEN_TOP_LEVEL_KEYS)}; found {found}"
        ]
    if fixture.get("payload_schema_version") != file_version:
        violations.append(
            f"payload golden fixture {fixture_path} payload_schema_version must equal {file_version}"
        )
    envelopes = fixture.get("envelopes")
    if not isinstance(envelopes, list) or not envelopes:
        return violations + [f"payload golden fixture {fixture_path} envelopes must be non-empty"]

    entities = manifest.get("entities")
    seen: list[str] = []
    for index, envelope in enumerate(envelopes):
        context = f"golden fixture {fixture_path.name} envelope[{index}]"
        if not isinstance(envelope, dict) or set(envelope) != GOLDEN_ENVELOPE_KEYS:
            found = sorted(envelope) if isinstance(envelope, dict) else type(envelope).__name__
            violations.append(
                f"{context} must contain exactly {sorted(GOLDEN_ENVELOPE_KEYS)}; found {found}"
            )
            continue
        entity_name = envelope.get("entity_type")
        operation = envelope.get("operation")
        if not isinstance(entity_name, str) or entity_name not in entities:
            violations.append(f"{context} has unknown entity_type {entity_name!r}")
            continue
        if operation != "upsert":
            violations.append(
                f"{context} must be the canonical upsert golden for {entity_name}"
            )
            continue
        seen.append(entity_name)
        for key in ("device_id", "entity_id", "version"):
            if not isinstance(envelope.get(key), str) or not envelope[key]:
                violations.append(f"{context} {key} must be a non-empty string")
        version = envelope.get("version")
        if isinstance(version, str) and not _format_valid(version, "hlc"):
            violations.append(f"{context} version must be a canonical HLC")
        payload = envelope.get("payload")
        if isinstance(payload, dict) and payload.get("version") != version:
            violations.append(f"{context} payload.version must equal envelope.version")
        if isinstance(payload, dict):
            upsert = entities[entity_name]["operations"]["upsert"]
            expected_keys = set(upsert["required_keys"]) | set(upsert["optional_keys"])
            actual_keys = set(payload)
            if actual_keys != expected_keys:
                violations.append(
                    f"{context} golden upsert must populate every declared field; "
                    f"missing {sorted(expected_keys - actual_keys)}, "
                    f"extra {sorted(actual_keys - expected_keys)}"
                )
        violations.extend(
            _payload_violations(
                payload,
                entity_name=entity_name,
                operation=operation,
                entity=entities[entity_name],
                context=context,
            )
        )
    expected_entities = sorted(entities)
    if seen != expected_entities:
        violations.append(
            f"payload golden fixture {fixture_path} must contain exactly one sorted upsert "
            f"per entity; found {seen}, expected {expected_entities}"
        )
    return violations


def _validate_manifest(path: Path, file_version: int) -> tuple[dict | None, list[str]]:
    violations: list[str] = []
    try:
        raw = path.read_bytes()
        value = strict_json_loads(raw)
    except (OSError, UnicodeError, ValueError) as error:
        return None, [f"cannot parse payload contract {path}: {error}"]

    if not isinstance(value, dict):
        return None, [f"payload contract {path} must be a JSON object"]
    if set(value) != TOP_LEVEL_KEYS:
        violations.append(
            f"payload contract {path} must contain exactly "
            f"{sorted(TOP_LEVEL_KEYS)}; found {sorted(value)}"
        )
    contract_format = value.get("contract_format")
    if type(contract_format) is not int or contract_format != CONTRACT_FORMAT:
        violations.append(
            f"payload contract {path.name} contract_format must equal "
            f"{CONTRACT_FORMAT}; found {contract_format!r}"
        )
    declared_version = value.get("payload_schema_version")
    if type(declared_version) is not int or declared_version != file_version:
        violations.append(
            f"payload contract {path.name} payload_schema_version must equal its "
            f"filename version {file_version}; found {declared_version!r}"
        )

    entity_violations = _validate_entities(path, value.get("entities"))
    violations.extend(entity_violations)
    if not entity_violations:
        violations.extend(
            field_evolution_violations(
                value,
                manifest_version=file_version,
                value_validator=field_value_violations,
            )
        )
    violations.extend(
        _validate_shadow_reserved_keys(
            path, value.get("entities"), value.get("shadow_reserved_keys")
        )
    )
    if (
        not entity_violations
        and set(value) == TOP_LEVEL_KEYS
        and isinstance(value.get("entities"), dict)
    ):
        violations.extend(_validate_golden_fixture(path, value, file_version))

    if raw != canonical_json_bytes(value):
        violations.append(
            f"payload contract {path} is not canonical JSON "
            "(UTF-8, sorted keys, two-space indent, trailing newline)"
        )
    return value, violations


def inspect_contracts(
    manifest_dir: Path = MANIFEST_DIR,
    version_source_path: Path = VERSION_SOURCE_PATH,
) -> tuple[dict[str, str], list[str]]:
    """Return ``({zero-padded version: raw-file sha256}, violations)``.

    Hashes are returned only for parseable, structurally valid, canonical
    manifests.  Callers must reject any accompanying violation before freezing
    the returned map.
    """
    version, violations = _read_swift_version(version_source_path)
    if not manifest_dir.is_dir():
        return {}, violations + [f"missing payload contract directory: {manifest_dir}"]

    paths_by_version: dict[int, Path] = {}
    for path in sorted(manifest_dir.glob("*.json")):
        match = MANIFEST_NAME.fullmatch(path.name)
        if match is None:
            violations.append(
                f"payload contract filename must be zero-padded NNN.json: {path.name}"
            )
            continue
        number = int(match.group(1))
        if number < 1:
            violations.append(f"payload contract version must be at least 1: {path.name}")
            continue
        if number in paths_by_version:
            violations.append(
                f"duplicate payload contract version {number}: "
                f"{paths_by_version[number].name} and {path.name}"
            )
            continue
        if path.name != f"{number:03d}.json":
            violations.append(
                f"payload contract {path.name} is not minimally zero-padded; "
                f"rename it to {number:03d}.json"
            )
        paths_by_version[number] = path

    if version is not None:
        expected = set(range(1, version + 1))
        actual = set(paths_by_version)
        for missing in sorted(expected - actual):
            violations.append(
                f"missing payload contract {missing:03d}.json required by "
                f"payloadSchemaVersion {version}"
            )
        for extra in sorted(actual - expected):
            violations.append(
                f"payload contract {extra:03d}.json is ahead of Swift "
                f"payloadSchemaVersion {version}"
            )

    hashes: dict[str, str] = {}
    valid_manifests: dict[int, dict[str, Any]] = {}
    for number, path in sorted(paths_by_version.items()):
        manifest, manifest_violations = _validate_manifest(path, number)
        violations.extend(manifest_violations)
        if not manifest_violations and manifest is not None:
            hashes[f"{number:03d}"] = hashlib.sha256(path.read_bytes()).hexdigest()
            valid_manifests[number] = manifest

    for current_number in sorted(valid_manifests):
        previous_number = current_number - 1
        if previous_number not in valid_manifests:
            continue
        violations.extend(
            adjacent_contract_violations(
                valid_manifests[previous_number],
                valid_manifests[current_number],
                previous_version=previous_number,
                current_version=current_number,
            )
        )
    return hashes, violations


def frozen_contract_violations(
    policy: dict, current_hashes: dict[str, str]
) -> list[str]:
    """Reject mutation/removal of released manifests once launch is armed."""
    if not policy.get("launched", False):
        return []
    frozen = (policy.get("frozen_baseline") or {}).get("sync_payload_contracts")
    if not isinstance(frozen, dict) or not frozen:
        return [
            "migration_policy.json is launched but "
            "frozen_baseline.sync_payload_contracts is empty. Run "
            "`apps/apple/script/verify_schema_freeze.py --arm` to atomically freeze "
            "the shipped SQLite and sync-payload contracts before release."
        ]

    violations: list[str] = []
    for version in sorted(frozen):
        frozen_sha = frozen[version]
        current_sha = current_hashes.get(version)
        if current_sha is None:
            violations.append(
                f"released sync payload contract {version} was removed "
                f"(frozen {str(frozen_sha)[:16]}...). {REMEDIATION}"
            )
        elif current_sha != frozen_sha:
            violations.append(
                f"released sync payload contract {version} changed "
                f"(frozen {str(frozen_sha)[:16]}..., now {current_sha[:16]}...). "
                f"{REMEDIATION}"
            )
    return violations


def embedded_manifest_violations(
    authority_dir: Path = MANIFEST_DIR,
    embedded_dir: Path = EMBEDDED_MANIFEST_DIR,
) -> list[str]:
    """Require production SwiftPM manifests to byte-match the Apple authority."""
    if not authority_dir.is_dir():
        return [f"missing payload contract authority directory: {authority_dir}"]
    if not embedded_dir.is_dir():
        return [f"missing bundled payload contract directory: {embedded_dir}"]

    authority = {
        path.name: path
        for path in authority_dir.glob("*.json")
        if MANIFEST_NAME.fullmatch(path.name)
    }
    embedded = {
        path.name: path
        for path in embedded_dir.glob("*.json")
        if MANIFEST_NAME.fullmatch(path.name)
    }
    violations: list[str] = []
    for name in sorted(authority.keys() - embedded.keys()):
        violations.append(
            f"bundled payload contract is missing authority manifest {name}"
        )
    for name in sorted(embedded.keys() - authority.keys()):
        violations.append(
            f"bundled payload contract {name} has no authority manifest"
        )
    for name in sorted(authority.keys() & embedded.keys()):
        if authority[name].read_bytes() != embedded[name].read_bytes():
            violations.append(
                f"bundled payload contract {name} differs byte-for-byte from "
                f"schema/sync_payload/{name}"
            )
    return violations


def main() -> int:
    try:
        policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"sync payload contract verification failed: cannot read {POLICY_PATH}: {error}")
        return 1

    hashes, violations = inspect_contracts()
    violations.extend(embedded_manifest_violations())
    violations.extend(frozen_contract_violations(policy, hashes))
    if violations:
        print("Sync payload contract verification failed:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    current = max(int(version) for version in hashes)
    frozen = (policy.get("frozen_baseline") or {}).get("sync_payload_contracts") or {}
    regime = "armed" if policy.get("launched", False) else "pre-launch"
    print(
        "Sync payload contract verification passed: "
        f"versions 1...{current} contiguous, payloadSchemaVersion={current}, "
        f"{len(frozen)} released contract(s) frozen ({regime})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
