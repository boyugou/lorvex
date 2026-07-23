#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from verify_sync_payload_contract import (
    _validate_field_spec,
    canonical_json_bytes,
    embedded_manifest_violations,
    field_value_violations,
    frozen_contract_violations,
    inspect_contracts,
    strict_json_loads,
)
from sync_payload_evolution import (
    CROSS_ID_COLLISION_ENTITIES,
    adjacent_contract_violations,
)


SHA_A = "a" * 64
SHA_B = "b" * 64


def _contract(version: int, fields: list[str] | None = None) -> dict:
    if fields is None:
        fields = ["id", "title", "version"]
    return {
        "contract_format": 3,
        "entities": {
            "task": {
                "fields": {
                    field: (
                        {"format": "uuid", "types": ["string"]}
                        if field == "id"
                        else {"format": "hlc", "types": ["string"]}
                        if field == "version"
                        else {"types": ["string"]}
                    )
                    for field in sorted(set(fields))
                },
                "operations": {
                    "delete": {
                        "shapes": [
                            {
                                "name": "tombstone",
                                "optional_keys": ["id", "title"],
                                "required_keys": ["version"],
                            }
                        ]
                    },
                    "upsert": {
                        "optional_keys": [],
                        "required_keys": fields,
                    },
                },
                "synthetic_keys": [],
            },
        },
        "field_evolution": {},
        "golden_fixture": f"fixtures/{version:03d}.golden.json",
        "golden_fixture_sha256": "0" * 64,
        "payload_schema_version": version,
        "shadow_reserved_keys": {},
    }


def _multi_entity_contract(version: int = 2) -> dict:
    value = _contract(version)
    value["entities"]["list"] = json.loads(
        json.dumps(value["entities"]["task"])
    )
    value["entities"]["ai_changelog"] = {
        "fields": {
            "entity_ids": {"types": ["null", "string"]},
            "hard_delete": {"types": ["boolean"]},
            "timestamp": {"format": "rfc3339-utc", "types": ["string"]},
            "version": {"format": "hlc", "types": ["string"]},
        },
        "operations": {
            "delete": {
                "shapes": [
                    {
                        "marker_key": "hard_delete",
                        "name": "hard_delete",
                        "optional_keys": [],
                        "required_keys": ["hard_delete", "version"],
                    }
                ]
            },
            "upsert": {
                "optional_keys": [],
                "required_keys": ["entity_ids", "timestamp", "version"],
            },
        },
        "synthetic_keys": ["entity_ids", "version"],
    }
    return value


def _add_optional_field(
    contract: dict,
    entity_name: str,
    field_name: str,
    field_spec: dict,
    *,
    introduced_in: int,
    legacy_insert_default,
    meaning: str,
) -> None:
    entity = contract["entities"][entity_name]
    entity["fields"][field_name] = field_spec
    entity["operations"]["upsert"]["optional_keys"].append(field_name)
    entity["operations"]["upsert"]["optional_keys"].sort()
    contract["field_evolution"][f"{entity_name}.{field_name}"] = {
        "introduced_in": introduced_in,
        "legacy_insert_default": legacy_insert_default,
        "legacy_update": "preserve",
        "meaning": meaning,
    }


def _add_optional_task_field(
    contract: dict,
    field_name: str,
    field_spec: dict,
    *,
    introduced_in: int,
    legacy_insert_default,
    meaning: str,
) -> None:
    _add_optional_field(
        contract,
        "task",
        field_name,
        field_spec,
        introduced_in=introduced_in,
        legacy_insert_default=legacy_insert_default,
        meaning=meaning,
    )


def _canonical_json(value: dict) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _write_fixture(root: Path, version: int, contracts: dict[int, dict]) -> tuple[Path, Path]:
    manifest_dir = root / "sync_payload"
    manifest_dir.mkdir()
    (manifest_dir / "fixtures").mkdir()
    for number, value in contracts.items():
        envelopes = []
        for offset, (entity_name, entity) in enumerate(sorted(value["entities"].items()), 1):
            if not isinstance(entity, dict) or not isinstance(entity.get("fields"), dict):
                continue
            wire_version = "1760000000000_0001_0123456789abcdef"
            payload = {
                key: _sample_value(spec, key)
                for key, spec in entity["fields"].items()
                if key
                in (
                    set(entity["operations"]["upsert"]["required_keys"])
                    | set(entity["operations"]["upsert"]["optional_keys"])
                )
            }
            payload["version"] = wire_version
            envelopes.append(
                {
                    "device_id": "contract-test-device",
                    "entity_id": f"{offset:08x}-0000-7000-8000-000000000000",
                    "entity_type": entity_name,
                    "operation": "upsert",
                    "payload": payload,
                    "version": wire_version,
                }
            )
        golden = {
            "envelopes": envelopes,
            "payload_schema_version": number,
        }
        golden_raw = _canonical_json(golden)
        golden_path = manifest_dir / "fixtures" / f"{number:03d}.golden.json"
        golden_path.write_text(golden_raw, encoding="utf-8")
        value["golden_fixture"] = f"fixtures/{number:03d}.golden.json"
        value["golden_fixture_sha256"] = hashlib.sha256(golden_raw.encode()).hexdigest()
        (manifest_dir / f"{number:03d}.json").write_text(
            _canonical_json(value), encoding="utf-8"
        )
    version_source = root / "Version.swift"
    version_source.write_text(
        "public enum LorvexVersion {\n"
        f"  public static let payloadSchemaVersion: UInt32 = {version}\n"
        "}\n",
        encoding="utf-8",
    )
    return manifest_dir, version_source


def _sample_value(spec: dict, key: str):
    if "enum" in spec:
        return spec["enum"][0]
    selected_type = next(value for value in spec["types"] if value != "null")
    formats = {
        "civil-date": "2026-07-15",
        "hlc": "1760000000000_0001_0123456789abcdef",
        "rfc3339-utc": "2026-07-15T12:34:56.000Z",
        "uuid": "00000001-0000-7000-8000-000000000000",
        "uuid-or-inbox": "inbox",
    }
    if spec.get("format") in formats:
        return formats[spec["format"]]
    if selected_type == "string":
        return f"golden-{key}"
    if selected_type == "boolean":
        return True
    if selected_type == "integer":
        return spec.get("minimum", 1)
    if selected_type == "number":
        return 1.5
    if selected_type == "array":
        return [_sample_value(spec["items"], key)] if "items" in spec else []
    if selected_type == "object":
        return {
            child: _sample_value(child_spec, child)
            for child, child_spec in spec.get("properties", {}).items()
        }
    raise AssertionError(f"no sample for {key}: {spec}")


class ContractValidationTests(unittest.TestCase):
    def test_clean_contiguous_inventory_matches_swift_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: _contract(1), 2: _multi_entity_contract()}
            )

            hashes, violations = inspect_contracts(manifest_dir, version_source)

            self.assertEqual(violations, [])
            self.assertEqual(set(hashes), {"001", "002"})
            self.assertTrue(all(len(value) == 64 for value in hashes.values()))

    def test_missing_intermediate_manifest_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 3, {1: _contract(1), 3: _contract(3)}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("002.json" in violation for violation in violations))

    def test_manifest_version_must_match_filename(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(2)}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("payload_schema_version" in violation for violation in violations))

    def test_noncanonical_json_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_dir, version_source = _write_fixture(root, 1, {1: _contract(1)})
            (manifest_dir / "001.json").write_text(
                json.dumps(_contract(1)), encoding="utf-8"
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("canonical JSON" in violation for violation in violations))

    def test_duplicate_or_unsorted_fields_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1, ["title", "id", "id"])}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("sorted unique" in violation for violation in violations))

    def test_delete_marker_must_be_required_by_its_exact_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bad = _multi_entity_contract()
            shape = bad["entities"]["ai_changelog"]["operations"]["delete"]["shapes"][0]
            shape["required_keys"] = ["version"]
            shape["optional_keys"] = ["hard_delete"]
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: _contract(1), 2: bad}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("marker_key" in violation for violation in violations))

    def test_empty_delete_shape_inventory_is_a_valid_upsert_only_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            value = _multi_entity_contract()
            value["entities"]["ai_changelog"]["operations"]["delete"]["shapes"] = []
            del value["entities"]["ai_changelog"]["fields"]["hard_delete"]
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: _contract(1), 2: value}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertEqual(violations, [])

    def test_rejects_required_optional_overlap(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bad = _multi_entity_contract()
            bad["entities"]["task"]["operations"]["upsert"]["optional_keys"] = ["title"]
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: _contract(1), 2: bad}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("overlap" in violation for violation in violations))

    def test_synthetic_key_must_be_declared_by_upsert(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bad = _multi_entity_contract()
            bad["entities"]["task"]["synthetic_keys"] = ["missing_child"]
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: _contract(1), 2: bad}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("synthetic keys" in violation for violation in violations))

    def test_abandoned_flat_manifest_format_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            flat = {
                "entities": {"task": ["id", "title", "version"]},
                "payload_schema_version": 1,
            }
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: flat}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("contract_format" in violation for violation in violations))

    def test_golden_fixture_hash_is_part_of_the_manifest_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            golden_path = manifest_dir / "fixtures" / "001.golden.json"
            golden = json.loads(golden_path.read_text(encoding="utf-8"))
            golden["envelopes"][0]["device_id"] = "mutated-device"
            golden_path.write_text(_canonical_json(golden), encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("golden fixture SHA changed" in item for item in violations))

    def test_golden_fixture_catches_same_version_json_type_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            manifest_path = manifest_dir / "001.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["entities"]["task"]["fields"]["title"] = {"types": ["integer"]}
            manifest_path.write_text(_canonical_json(manifest), encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("payload.title has JSON type string" in item for item in violations))

    def test_golden_fixture_catches_nullability_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            golden_path = manifest_dir / "fixtures" / "001.golden.json"
            golden = json.loads(golden_path.read_text(encoding="utf-8"))
            golden["envelopes"][0]["payload"]["title"] = None
            raw = _canonical_json(golden)
            golden_path.write_text(raw, encoding="utf-8")
            manifest_path = manifest_dir / "001.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["golden_fixture_sha256"] = hashlib.sha256(raw.encode()).hexdigest()
            manifest_path.write_text(_canonical_json(manifest), encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("payload.title has JSON type null" in item for item in violations))

    def test_nonfinite_numbers_are_never_accepted_as_json(self) -> None:
        for token in ("NaN", "Infinity", "-Infinity", "1e9999", "-1e9999"):
            with self.subTest(token=token), self.assertRaisesRegex(
                ValueError, "non-finite JSON number"
            ):
                strict_json_loads(token)

        with self.assertRaises(ValueError):
            canonical_json_bytes({"legacy_insert_default": float("nan")})
        self.assertTrue(
            any(
                "non-finite JSON number" in violation
                for violation in field_value_violations(
                    float("inf"), {"types": ["number"]}, context="task.score"
                )
            )
        )

    def test_nonfinite_number_in_golden_fixture_is_rejected_before_freeze(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            fixture_path = manifest_dir / "fixtures" / "001.golden.json"
            raw = fixture_path.read_text(encoding="utf-8").replace(
                '"title": "golden-title"', '"title": NaN'
            )
            fixture_path.write_text(raw, encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any("non-finite JSON number" in violation for violation in violations)
            )

    def test_exponent_overflow_in_manifest_is_rejected_before_freeze(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            manifest_path = manifest_dir / "001.json"
            raw = manifest_path.read_text(encoding="utf-8").replace(
                '"payload_schema_version": 1', '"payload_schema_version": 1e9999'
            )
            manifest_path.write_text(raw, encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any("non-finite JSON number" in violation for violation in violations)
            )

    def test_exponent_overflow_in_golden_fixture_is_rejected_before_freeze(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: _contract(1)}
            )
            fixture_path = manifest_dir / "fixtures" / "001.golden.json"
            raw = fixture_path.read_text(encoding="utf-8").replace(
                '"payload_schema_version": 1', '"payload_schema_version": 1e9999'
            )
            fixture_path.write_text(raw, encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any("non-finite JSON number" in violation for violation in violations)
            )

    def test_golden_upsert_must_populate_every_optional_field(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            contract = _contract(1)
            contract["entities"]["task"]["fields"]["notes"] = {
                "types": ["null", "string"]
            }
            contract["entities"]["task"]["operations"]["upsert"][
                "optional_keys"
            ] = ["notes"]
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: contract}
            )
            fixture_path = manifest_dir / "fixtures" / "001.golden.json"
            golden = json.loads(fixture_path.read_text(encoding="utf-8"))
            del golden["envelopes"][0]["payload"]["notes"]
            raw = _canonical_json(golden)
            fixture_path.write_text(raw, encoding="utf-8")
            manifest_path = manifest_dir / "001.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["golden_fixture_sha256"] = hashlib.sha256(raw.encode()).hexdigest()
            manifest_path.write_text(_canonical_json(manifest), encoding="utf-8")

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any(
                    "golden upsert must populate every declared field" in item
                    and "notes" in item
                    for item in violations
                )
            )

    def test_malformed_reserved_key_reports_instead_of_crashing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            malformed = _contract(1)
            malformed["shadow_reserved_keys"] = {"task": [{}]}
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: malformed}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any("shadow_reserved_keys.task has an invalid field name" in item for item in violations)
            )

    def test_malformed_reserved_entity_reports_instead_of_crashing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            malformed = _contract(1)
            malformed["entities"]["task"] = []
            malformed["shadow_reserved_keys"] = {"task": ["local_only"]}
            manifest_dir, version_source = _write_fixture(
                Path(directory), 1, {1: malformed}
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(any("entity task must contain exactly" in item for item in violations))
            self.assertTrue(any("references malformed entity 'task'" in item for item in violations))


class MonotonicEvolutionTests(unittest.TestCase):
    def violations(self, before: dict, after: dict) -> list[str]:
        return adjacent_contract_violations(
            before, after, previous_version=1, current_version=2
        )

    def test_allows_new_entity_and_safe_optional_top_level_field(self) -> None:
        before = _contract(1)
        after = _multi_entity_contract(2)
        before["entities"]["list"] = json.loads(
            json.dumps(before["entities"]["task"])
        )
        _add_optional_field(
            after,
            "list",
            "notes",
            {"types": ["null", "string"]},
            introduced_in=2,
            legacy_insert_default=None,
            meaning="Optional user-authored task notes.",
        )
        after["entities"]["list"]["operations"]["delete"]["shapes"][0][
            "optional_keys"
        ].append("notes")
        after["entities"]["list"]["operations"]["delete"]["shapes"][0][
            "optional_keys"
        ].sort()

        self.assertEqual(self.violations(before, after), [])

        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: before, 2: after}
            )
            _, violations = inspect_contracts(manifest_dir, version_source)
            self.assertEqual(violations, [])

    def test_rejects_field_evolution_on_cross_id_collision_aggregate(self) -> None:
        expected = {
            "calendar_event",
            "habit",
            "habit_reminder_policy",
            "memory",
            "tag",
            "task",
        }
        self.assertEqual(CROSS_ID_COLLISION_ENTITIES, expected)
        for entity_name in sorted(expected):
            with self.subTest(entity_name=entity_name), tempfile.TemporaryDirectory() as directory:
                before = _contract(1)
                after = _contract(2)
                if entity_name != "task":
                    before["entities"][entity_name] = before["entities"].pop("task")
                    after["entities"][entity_name] = after["entities"].pop("task")
                _add_optional_field(
                    after,
                    entity_name,
                    "notes",
                    {"types": ["null", "string"]},
                    introduced_in=2,
                    legacy_insert_default=None,
                    meaning="Optional evolved field used by the contract probe.",
                )
                manifest_dir, version_source = _write_fixture(
                    Path(directory), 2, {1: before, 2: after}
                )
                _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any(
                    f"{entity_name}.notes is unsafe on a cross-id collision aggregate" in item
                    for item in violations
                )
            )

    def test_rejects_added_field_without_legacy_absence_metadata(self) -> None:
        before = _contract(1)
        after = _contract(2)
        after["entities"]["task"]["fields"]["notes"] = {
            "types": ["null", "string"]
        }
        after["entities"]["task"]["operations"]["upsert"]["optional_keys"] = [
            "notes"
        ]

        violations = self.violations(before, after)

        self.assertTrue(
            any("missing=['task.notes']" in item for item in violations)
        )

    def test_rejects_legacy_insert_default_with_wrong_wire_type(self) -> None:
        before = _contract(1)
        after = _contract(2)
        _add_optional_task_field(
            after,
            "estimate",
            {"minimum": 0, "types": ["integer"], "unit": "minutes"},
            introduced_in=2,
            legacy_insert_default="unknown",
            meaning="Estimated task duration in minutes.",
        )

        with tempfile.TemporaryDirectory() as directory:
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: before, 2: after}
            )
            _, violations = inspect_contracts(manifest_dir, version_source)

        self.assertTrue(
            any(
                "task.estimate.legacy_insert_default has JSON type string" in item
                for item in violations
            )
        )

    def test_rejects_nonfinite_legacy_insert_default_in_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            before = _contract(1)
            after = _contract(2)
            _add_optional_task_field(
                after,
                "score",
                {"types": ["number"]},
                introduced_in=2,
                legacy_insert_default=0.5,
                meaning="Task score used by the test contract.",
            )
            manifest_dir, version_source = _write_fixture(
                Path(directory), 2, {1: before, 2: after}
            )
            manifest_path = manifest_dir / "002.json"
            manifest_path.write_text(
                manifest_path.read_text(encoding="utf-8").replace(
                    '"legacy_insert_default": 0.5', '"legacy_insert_default": Infinity'
                ),
                encoding="utf-8",
            )

            _, violations = inspect_contracts(manifest_dir, version_source)

            self.assertTrue(
                any("non-finite JSON number" in violation for violation in violations)
            )

    def test_rejects_mutating_or_removing_historical_metadata(self) -> None:
        for mutation in ("remove", "change"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                version_1 = _multi_entity_contract(1)
                version_2 = _multi_entity_contract(2)
                _add_optional_field(
                    version_2,
                    "list",
                    "notes",
                    {"types": ["null", "string"]},
                    introduced_in=2,
                    legacy_insert_default=None,
                    meaning="Optional user-authored task notes.",
                )
                version_3 = _multi_entity_contract(3)
                _add_optional_field(
                    version_3,
                    "list",
                    "notes",
                    {"types": ["null", "string"]},
                    introduced_in=2,
                    legacy_insert_default=None,
                    meaning="Optional user-authored task notes.",
                )
                if mutation == "remove":
                    del version_3["field_evolution"]["list.notes"]
                else:
                    version_3["field_evolution"]["list.notes"]["meaning"] = (
                        "Changed historical meaning."
                    )
                manifest_dir, version_source = _write_fixture(
                    Path(directory),
                    3,
                    {1: version_1, 2: version_2, 3: version_3},
                )

                _, violations = inspect_contracts(manifest_dir, version_source)

                expected = "removed historical" if mutation == "remove" else "mutated historical"
                self.assertTrue(any(expected in item for item in violations))

    def test_rejects_entity_and_field_removal(self) -> None:
        before = _multi_entity_contract(1)
        after = _multi_entity_contract(2)
        del after["entities"]["ai_changelog"]
        del after["entities"]["task"]["fields"]["title"]
        after["entities"]["task"]["operations"]["upsert"]["required_keys"].remove(
            "title"
        )
        after["entities"]["task"]["operations"]["delete"]["shapes"][0][
            "optional_keys"
        ].remove("title")

        violations = self.violations(before, after)
        self.assertTrue(any("removed existing entities" in item for item in violations))
        self.assertTrue(any("removed existing fields" in item for item in violations))

    def test_rejects_recursive_type_nullability_enum_and_nested_changes(self) -> None:
        mutations = [
            {"types": ["integer"]},
            {"types": ["null", "string"]},
            {"enum": ["new", "old"], "types": ["string"]},
            {
                "additional_properties": False,
                "properties": {"child": {"types": ["string"]}},
                "required_properties": [],
                "types": ["object"],
            },
        ]
        for replacement in mutations:
            with self.subTest(replacement=replacement):
                before = _contract(1)
                after = _contract(2)
                after["entities"]["task"]["fields"]["title"] = replacement
                self.assertTrue(
                    any(
                        "changed recursive wire spec" in item
                        for item in self.violations(before, after)
                    )
                )

    def test_rejects_presence_reclassification_and_required_new_field(self) -> None:
        before = _contract(1)
        after = _contract(2)
        after["entities"]["task"]["fields"]["notes"] = {"types": ["string"]}
        after["entities"]["task"]["operations"]["upsert"]["required_keys"].append(
            "notes"
        )
        after["entities"]["task"]["operations"]["upsert"]["required_keys"].sort()

        violations = self.violations(before, after)
        self.assertTrue(any("required-key presence" in item for item in violations))
        self.assertTrue(any("new_fields_not_optional" in item for item in violations))

    def test_rejects_delete_shape_and_marker_semantic_changes(self) -> None:
        before = _contract(1)
        after = _contract(2)
        after["entities"]["task"]["operations"]["delete"]["shapes"].append(
            {
                "marker_key": "hard_delete",
                "name": "hard_delete",
                "optional_keys": [],
                "required_keys": ["hard_delete", "version"],
            }
        )
        after["entities"]["task"]["fields"]["hard_delete"] = {
            "types": ["boolean"]
        }
        after["entities"]["task"]["operations"]["upsert"]["optional_keys"] = [
            "hard_delete"
        ]

        self.assertTrue(
            any("changed delete-shape inventory" in item for item in self.violations(before, after))
        )

    def test_rejects_reusing_an_older_shadow_reserved_spelling(self) -> None:
        before = _contract(1)
        before["shadow_reserved_keys"] = {"task": ["lookup_key"]}
        after = _contract(2)
        after["shadow_reserved_keys"] = {"task": ["lookup_key"]}
        after["entities"]["task"]["fields"]["lookup_key"] = {"types": ["string"]}
        after["entities"]["task"]["operations"]["upsert"]["optional_keys"] = [
            "lookup_key"
        ]

        self.assertTrue(
            any("new_wire_collisions" in item for item in self.violations(before, after))
        )


class TypedValueValidationTests(unittest.TestCase):
    block_spec = {
        "additional_properties": False,
        "properties": {
            "block_type": {"enum": ["buffer", "task"], "types": ["string"]},
            "start_time": {"maximum": 1440, "minimum": 0, "types": ["integer"]},
        },
        "required_properties": ["block_type", "start_time"],
        "types": ["object"],
    }

    def test_enum_and_numeric_unit_range_are_enforced(self) -> None:
        violations = field_value_violations(
            {"block_type": "meeting", "start_time": 1_700},
            self.block_spec,
            context="blocks[0]",
        )
        self.assertTrue(any("outside enum" in item for item in violations))
        self.assertTrue(any("exceeds maximum 1440" in item for item in violations))

    def test_nested_object_shape_is_closed(self) -> None:
        violations = field_value_violations(
            {"block_type": "task", "start_time": 540, "seconds": 32_400},
            self.block_spec,
            context="blocks[0]",
        )
        self.assertTrue(any("unexpected properties ['seconds']" in item for item in violations))

    def test_array_item_shape_is_recursive(self) -> None:
        array_spec = {"items": self.block_spec, "types": ["array"]}
        violations = field_value_violations(
            [{"block_type": "task", "start_time": "09:00"}],
            array_spec,
            context="blocks",
        )
        self.assertTrue(any("start_time has JSON type string" in item for item in violations))

    def test_object_type_requires_an_explicit_open_or_closed_policy(self) -> None:
        implicit = _validate_field_spec(
            {"types": ["object"]}, path=Path("001.json"), context="attendees.items"
        )
        self.assertTrue(any("intentionally open object" in item for item in implicit))

        explicit_open = _validate_field_spec(
            {
                "additional_properties": True,
                "properties": {},
                "required_properties": [],
                "types": ["object"],
            },
            path=Path("001.json"),
            context="attendees.items",
        )
        self.assertEqual(explicit_open, [])

    def test_numeric_units_are_controlled_and_require_numeric_types(self) -> None:
        valid = _validate_field_spec(
            {
                "maximum": 1440,
                "minimum": 0,
                "types": ["integer"],
                "unit": "minute-of-day",
            },
            path=Path("001.json"),
            context="blocks.items.start_time",
        )
        self.assertEqual(valid, [])
        nonnumeric = _validate_field_spec(
            {"types": ["string"], "unit": "minutes"},
            path=Path("001.json"),
            context="task.title",
        )
        self.assertTrue(any("unit requires a numeric type" in item for item in nonnumeric))

    def test_uuid_or_inbox_accepts_only_the_canonical_sentinel_or_uuid(self) -> None:
        spec = {"format": "uuid-or-inbox", "types": ["string"]}
        self.assertEqual(field_value_violations("inbox", spec, context="list.id"), [])
        self.assertEqual(
            field_value_violations(
                "00000001-0000-7000-8000-000000000000", spec, context="list.id"
            ),
            [],
        )
        self.assertTrue(
            field_value_violations("default", spec, context="list.id")
        )

    def test_rfc3339_utc_requires_exact_canonical_milliseconds(self) -> None:
        spec = {"format": "rfc3339-utc", "types": ["string"]}
        self.assertEqual(
            field_value_violations(
                "2026-07-15T12:34:56.000Z", spec, context="created_at"
            ),
            [],
        )
        self.assertTrue(
            field_value_violations("2026-07-15T12:34:56Z", spec, context="created_at")
        )
        self.assertTrue(
            field_value_violations(
                "2026-07-15T12:34:56.000+00:00", spec, context="created_at"
            )
        )

    def test_calendar_url_requires_a_complete_canonical_prefix(self) -> None:
        spec = {"format": "calendar-url", "types": ["string"]}
        self.assertEqual(
            field_value_violations("https://lorvex.app/event", spec, context="url"), []
        )
        self.assertTrue(field_value_violations("https:", spec, context="url"))
        self.assertTrue(
            field_value_violations("https://lorvex.app/white space", spec, context="url")
        )
        self.assertTrue(
            field_value_violations("https://lorvex.app/new\nline", spec, context="url")
        )


class FrozenContractTests(unittest.TestCase):
    def test_dormant_policy_does_not_freeze_prelaunch_contracts(self) -> None:
        policy = {
            "launched": False,
            "frozen_baseline": {"sync_payload_contracts": {"001": SHA_A}},
        }
        self.assertEqual(frozen_contract_violations(policy, {"001": SHA_B}), [])

    def test_armed_policy_rejects_mutated_released_contract(self) -> None:
        policy = {
            "launched": True,
            "frozen_baseline": {"sync_payload_contracts": {"001": SHA_A}},
        }

        violations = frozen_contract_violations(policy, {"001": SHA_B})

        self.assertEqual(len(violations), 1)
        self.assertIn("001", violations[0])
        self.assertIn("changed", violations[0])

    def test_armed_policy_rejects_removed_released_contract(self) -> None:
        policy = {
            "launched": True,
            "frozen_baseline": {"sync_payload_contracts": {"001": SHA_A}},
        }

        violations = frozen_contract_violations(policy, {})

        self.assertEqual(len(violations), 1)
        self.assertIn("001", violations[0])
        self.assertIn("removed", violations[0])

    def test_armed_policy_allows_new_unreleased_contract(self) -> None:
        policy = {
            "launched": True,
            "frozen_baseline": {"sync_payload_contracts": {"001": SHA_A}},
        }
        self.assertEqual(
            frozen_contract_violations(policy, {"001": SHA_A, "002": SHA_B}), []
        )

    def test_armed_policy_requires_a_frozen_contract_baseline(self) -> None:
        policy = {
            "launched": True,
            "frozen_baseline": {"sync_payload_contracts": None},
        }

        violations = frozen_contract_violations(policy, {"001": SHA_A})

        self.assertEqual(len(violations), 1)
        self.assertIn("--arm", violations[0])


class EmbeddedManifestTests(unittest.TestCase):
    def test_accepts_byte_identical_numbered_manifests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            authority = root / "authority"
            embedded = root / "embedded"
            authority.mkdir()
            embedded.mkdir()
            raw = b'{"payload_schema_version":1}\n'
            (authority / "001.json").write_bytes(raw)
            (embedded / "001.json").write_bytes(raw)

            self.assertEqual(embedded_manifest_violations(authority, embedded), [])

    def test_rejects_missing_extra_and_byte_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            authority = root / "authority"
            embedded = root / "embedded"
            authority.mkdir()
            embedded.mkdir()
            (authority / "001.json").write_bytes(b"authority\n")
            (authority / "002.json").write_bytes(b"two\n")
            (embedded / "001.json").write_bytes(b"drift\n")
            (embedded / "003.json").write_bytes(b"extra\n")

            failures = embedded_manifest_violations(authority, embedded)

            self.assertTrue(any("differs byte-for-byte" in item for item in failures))
            self.assertTrue(any("missing authority manifest 002.json" in item for item in failures))
            self.assertTrue(any("003.json has no authority" in item for item in failures))

    def test_rejects_missing_embedded_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            authority = root / "authority"
            authority.mkdir()

            self.assertEqual(
                embedded_manifest_violations(authority, root / "missing"),
                [f"missing bundled payload contract directory: {root / 'missing'}"],
            )


if __name__ == "__main__":
    unittest.main()
