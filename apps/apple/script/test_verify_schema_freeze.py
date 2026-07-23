#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

from verify_migration_ladder import sha256_migration_hex
from verify_schema_freeze import (
    SchemaFreezeArmError,
    _contiguous_new_entries,
    arm,
    embed_parity_violations,
    freeze_violations,
    load_lock_entries,
    main,
    release_coverage_violations,
)

SHA_A = "a" * 64
SHA_B = "b" * 64
SHA_C = "c" * 64

BASELINE_SQL = "CREATE TABLE tasks (id TEXT PRIMARY KEY) STRICT;"
MIGRATION_002_SQL = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
SHA_BASELINE = sha256_migration_hex(BASELINE_SQL)
SHA_MIGRATION_002 = sha256_migration_hex(MIGRATION_002_SQL)


def _canonical_json(value: dict) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _payload_fixture(version: int, fields: list[str]) -> dict:
    wire_version = "1760000000000_0001_0123456789abcdef"
    payload = {
        field: (
            "00000001-0000-7000-8000-000000000000"
            if field == "id"
            else wire_version
            if field == "version"
            else f"golden-{field}"
        )
        for field in fields
    }
    return {
        "envelopes": [
            {
                "device_id": "contract-test-device",
                "entity_id": "00000001-0000-7000-8000-000000000000",
                "entity_type": "list",
                "operation": "upsert",
                "payload": payload,
                "version": wire_version,
            }
        ],
        "payload_schema_version": version,
    }


def _payload_contract(version: int, fields: list[str]) -> dict:
    fields = sorted(set(fields))
    baseline_fields = {"id", "title", "version"}
    added_fields = sorted(set(fields) - baseline_fields) if version > 1 else []
    fixture_text = _canonical_json(_payload_fixture(version, fields))
    return {
        "contract_format": 3,
        "entities": {
            "list": {
                "fields": {
                    field: (
                        {"format": "uuid", "types": ["string"]}
                        if field == "id"
                        else {"format": "hlc", "types": ["string"]}
                        if field == "version"
                        else {"types": ["string"]}
                    )
                    for field in fields
                },
                "operations": {
                    "delete": {
                        "shapes": [
                            {
                                "name": "tombstone",
                                "optional_keys": sorted(set(fields) - {"version"}),
                                "required_keys": ["version"],
                            }
                        ]
                    },
                    "upsert": {
                        "optional_keys": added_fields,
                        "required_keys": sorted(set(fields) - set(added_fields)),
                    },
                },
                "synthetic_keys": [],
            }
        },
        "field_evolution": {
            f"list.{field}": {
                "introduced_in": version,
                "legacy_insert_default": "",
                "legacy_update": "preserve",
                "meaning": f"Test-only additive field {field}.",
            }
            for field in added_fields
        },
        "golden_fixture": f"fixtures/{version:03d}.golden.json",
        "golden_fixture_sha256": hashlib.sha256(fixture_text.encode("utf-8")).hexdigest(),
        "payload_schema_version": version,
        "shadow_reserved_keys": {},
    }


PAYLOAD_FIELDS = ["id", "title", "version"]
PAYLOAD_CONTRACT = _canonical_json(_payload_contract(1, PAYLOAD_FIELDS))
SHA_PAYLOAD_CONTRACT = hashlib.sha256(PAYLOAD_CONTRACT.encode("utf-8")).hexdigest()


def _write_payload_contract(root: Path, version: int, fields: list[str]) -> str:
    payload_contracts = root / "sync_payload"
    payload_contracts.mkdir(exist_ok=True)
    fixtures = payload_contracts / "fixtures"
    fixtures.mkdir(exist_ok=True)
    fixture_text = _canonical_json(_payload_fixture(version, sorted(set(fields))))
    (fixtures / f"{version:03d}.golden.json").write_text(fixture_text, encoding="utf-8")
    contract_text = _canonical_json(_payload_contract(version, fields))
    (payload_contracts / f"{version:03d}.json").write_text(contract_text, encoding="utf-8")
    return contract_text


def _lock_entries(shas: dict[str, str]) -> dict[str, dict[str, str]]:
    return {
        version: {
            "name": "001_schema.sql" if version == "001" else f"{version}_widgets.sql",
            "sha256": sha,
        }
        for version, sha in shas.items()
    }


def _armed(frozen: dict[str, str] | None) -> dict:
    return {
        "launched": True,
        "frozen_baseline": {
            "checksums_lock": None if frozen is None else _lock_entries(frozen),
            "sync_payload_contracts": {"001": SHA_PAYLOAD_CONTRACT},
        },
    }


def _armed_entries(frozen: dict[str, dict[str, str]]) -> dict:
    return {
        "launched": True,
        "frozen_baseline": {
            "checksums_lock": frozen,
            "sync_payload_contracts": {"001": SHA_PAYLOAD_CONTRACT},
        },
    }


class FreezeViolationsTests(unittest.TestCase):
    def test_dormant_ignores_even_a_mutated_lock(self) -> None:
        policy = {
            "launched": False,
            "frozen_baseline": {"checksums_lock": _lock_entries({"001": SHA_A})},
        }
        # Baseline sha differs, but the sentinel is off: the gate is a no-op and
        # must never fight the pre-launch `--seed` regen workflow.
        self.assertEqual(freeze_violations(policy, _lock_entries({"001": SHA_B})), [])

    def test_armed_baseline_mutated_without_migration_fails(self) -> None:
        violations = freeze_violations(
            _armed({"001": SHA_A}), _lock_entries({"001": SHA_B})
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("001", violations[0])
        self.assertIn("APPENDING", violations[0])

    def test_armed_new_migration_appended_passes(self) -> None:
        # Baseline 001 unchanged, migration 002 appended -> allowed growth.
        self.assertEqual(
            freeze_violations(
                _armed({"001": SHA_A}),
                _lock_entries({"001": SHA_A, "002": SHA_C}),
            ),
            [],
        )

    def test_armed_released_entry_removed_fails(self) -> None:
        violations = freeze_violations(
            _armed({"001": SHA_A, "002": SHA_C}), _lock_entries({"001": SHA_A})
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("002", violations[0])
        self.assertIn("removed", violations[0])

    def test_armed_without_frozen_baseline_fails(self) -> None:
        violations = freeze_violations(_armed(None), _lock_entries({"001": SHA_A}))
        self.assertEqual(len(violations), 1)
        self.assertIn("--arm", violations[0])

    def test_armed_released_entry_rename_fails_even_when_sha_is_unchanged(self) -> None:
        frozen = {
            "002": {"name": "002_add_widgets.sql", "sha256": SHA_A},
        }
        current = {
            "002": {"name": "002_renamed.sql", "sha256": SHA_A},
        }

        violations = freeze_violations(_armed_entries(frozen), current)

        self.assertEqual(len(violations), 1)
        self.assertIn("002", violations[0])
        self.assertIn("name", violations[0])

    def test_release_coverage_rejects_current_migration_not_yet_rearmed(self) -> None:
        policy = _armed({"001": SHA_A})
        current_lock = _lock_entries({"001": SHA_A, "002": SHA_C})

        violations = release_coverage_violations(
            policy, current_lock, {"001": SHA_PAYLOAD_CONTRACT}
        )

        self.assertEqual(len(violations), 1)
        self.assertIn("migration 002", violations[0])
        self.assertIn("--arm", violations[0])

    def test_release_coverage_rejects_payload_contract_not_yet_rearmed(self) -> None:
        policy = _armed({"001": SHA_A})

        violations = release_coverage_violations(
            policy,
            _lock_entries({"001": SHA_A}),
            {"001": SHA_PAYLOAD_CONTRACT, "002": SHA_C},
        )

        self.assertEqual(len(violations), 1)
        self.assertIn("payload contract 002", violations[0])
        self.assertIn("--arm", violations[0])

    def test_release_cli_rejects_append_that_normal_verification_permits(self) -> None:
        policy = _armed({"001": SHA_A})
        current_lock = _lock_entries({"001": SHA_A, "002": SHA_C})
        current_payloads = {"001": SHA_PAYLOAD_CONTRACT}
        with (
            patch("verify_schema_freeze.load_policy", return_value=policy),
            patch("verify_schema_freeze.load_lock_entries", return_value=current_lock),
            patch(
                "verify_schema_freeze.inspect_contracts",
                return_value=(current_payloads, []),
            ),
            redirect_stdout(io.StringIO()),
            redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(main([]), 0)
            self.assertEqual(main(["--release"]), 1)


class LockAndArmTests(unittest.TestCase):
    def test_load_lock_entries_preserves_complete_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "checksums.lock"
            lock.write_text(
                json.dumps({"001": {"name": "001_schema.sql", "sha256": SHA_A}}),
                encoding="utf-8",
            )
            self.assertEqual(
                load_lock_entries(lock),
                {"001": {"name": "001_schema.sql", "sha256": SHA_A}},
            )

    def test_arm_flips_sentinel_and_captures_lock(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            policy_path.write_text(
                json.dumps({"launched": False, "frozen_baseline": {"checksums_lock": None}}),
                encoding="utf-8",
            )
            # A clean, self-consistent canonical ladder + byte-identical Apple
            # embed so the (now unconditional) first-arm validation — freeze,
            # ladder, AND embed parity — checks well-formed inputs hermetically,
            # never the real repo via the default canonical_*/apple_* paths.
            tree = _write_release_tree(root, {})

            arm(policy_path, **tree)

            written = json.loads(policy_path.read_text(encoding="utf-8"))
            self.assertTrue(written["launched"])
            self.assertEqual(
                written["frozen_baseline"]["checksums_lock"],
                _lock_entries({"001": SHA_BASELINE}),
            )
            # An armed policy over the same lock is clean; a re-seed of 001 fails.
            self.assertEqual(
                freeze_violations(written, _lock_entries({"001": SHA_BASELINE})), []
            )
            self.assertEqual(
                len(freeze_violations(written, _lock_entries({"001": SHA_B}))), 1
            )


def _write_release_tree(
    root: Path, migrations: dict[str, tuple[str, str]]
) -> dict[str, Path]:
    """Write a self-consistent canonical ``schema/`` authority AND its
    byte-identical Apple embed, returning the full set of path kwargs ``arm()``
    needs.

    ``migrations`` maps a zero-padded version (``"002"``+) to ``(file_name,
    sql_text)``; version ``001`` is always the baseline (``BASELINE_SQL``, named
    ``001_schema.sql``, living in ``schema.sql`` rather than the migrations
    dir). The canonical ladder is internally consistent (schema / lock /
    migration checksums agree) and the Apple embed is a byte-for-byte copy, so
    ``arm()``'s freeze, ladder, and embed-parity checks all pass by
    construction. A test then mutates a single returned file to drive one
    specific violation, hermetically — never the real repo via the default
    ``canonical_*`` / ``apple_*`` paths.
    """
    canonical_schema = root / "schema.sql"
    canonical_lock = root / "canonical_checksums.lock"
    canonical_migrations = root / "migrations"
    canonical_migrations.mkdir(exist_ok=True)

    canonical_schema.write_text(BASELINE_SQL, encoding="utf-8")
    lock = {"001": {"name": "001_schema.sql", "sha256": SHA_BASELINE}}
    for version, (name, sql_text) in migrations.items():
        lock[version] = {"name": name, "sha256": sha256_migration_hex(sql_text)}
        (canonical_migrations / name).write_text(sql_text, encoding="utf-8")
    canonical_lock.write_text(json.dumps(lock), encoding="utf-8")

    apple_schema = root / "apple_schema.sql"
    apple_lock = root / "apple_checksums.lock"
    apple_migrations = root / "apple_migrations"
    apple_migrations.mkdir(exist_ok=True)
    apple_schema.write_bytes(canonical_schema.read_bytes())
    apple_lock.write_bytes(canonical_lock.read_bytes())
    for canonical_file in canonical_migrations.glob("[0-9][0-9][0-9]_*.sql"):
        (apple_migrations / canonical_file.name).write_bytes(canonical_file.read_bytes())

    _write_payload_contract(root, 1, PAYLOAD_FIELDS)
    payload_contracts = root / "sync_payload"
    payload_version_source = root / "Version.swift"
    payload_version_source.write_text(
        "public enum LorvexVersion {\n"
        "  public static let payloadSchemaVersion: UInt32 = 1\n"
        "}\n",
        encoding="utf-8",
    )

    return {
        "lock_path": apple_lock,
        "canonical_lock_path": canonical_lock,
        "canonical_schema_sql_path": canonical_schema,
        "canonical_migrations_dir": canonical_migrations,
        "apple_schema_sql_path": apple_schema,
        "apple_migrations_dir": apple_migrations,
        "payload_contracts_dir": payload_contracts,
        "payload_version_source_path": payload_version_source,
    }


class RearmValidationTests(unittest.TestCase):
    """``arm()`` re-validates before it re-freezes (M4).

    Blindly replacing ``frozen_baseline`` with whatever ``checksums.lock``
    currently says (the original behavior) lets a mutated, already-released
    checksum entry become the new frozen truth just by running ``--arm``
    again. These tests pin the fix: a mutated frozen entry — whether the
    mutation shows up in the Apple lock or in the canonical migration ladder
    — hard-fails the arm and leaves the policy file untouched, while an
    unmutated re-arm still folds in newly shipped, contiguous entries.
    """

    def test_rearm_folds_in_new_contiguous_entry_when_frozen_entries_are_intact(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(_armed({"001": SHA_BASELINE})), encoding="utf-8")
            # A newly shipped migration 002 present in both the canonical ladder
            # and the byte-identical Apple embed.
            tree = _write_release_tree(root, {"002": ("002_widgets.sql", MIGRATION_002_SQL)})

            policy = arm(policy_path, **tree)

            self.assertTrue(policy["launched"])
            self.assertEqual(
                policy["frozen_baseline"]["checksums_lock"],
                _lock_entries({"001": SHA_BASELINE, "002": SHA_MIGRATION_002}),
            )
            # The write on disk matches the returned policy.
            self.assertEqual(json.loads(policy_path.read_text(encoding="utf-8")), policy)

    def test_rearm_with_mutated_apple_lock_entry_hard_fails_and_leaves_policy_untouched(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            original_policy = _armed({"001": SHA_BASELINE})
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            # The Apple checksums.lock 001 entry was mutated after the prior
            # arm — exactly the violation the freeze tripwire exists to catch.
            tree["lock_path"].write_text(
                json.dumps({"001": {"name": "001_schema.sql", "sha256": SHA_A}}),
                encoding="utf-8",
            )

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(
                any("001" in v and "changed" in v for v in ctx.exception.violations)
            )
            # Re-arming over a mutation never blesses it: the policy file is
            # byte-for-byte what it was before the call.
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_rearm_with_broken_canonical_ladder_hard_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            original_policy = _armed({"001": SHA_BASELINE})
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            # The canonical baseline no longer matches its own lock entry 001:
            # a real regression `--arm` must not paper over.
            tree["canonical_lock_path"].write_text(
                json.dumps({"001": {"name": "001_schema.sql", "sha256": SHA_A}}),
                encoding="utf-8",
            )

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(
                any("does not match" in v for v in ctx.exception.violations)
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_first_arm_validates_current_state_and_freezes_when_clean(self) -> None:
        # M5: a first-ever arm (no prior frozen_baseline) validates the current
        # on-disk state BEFORE freezing — it is not a blind capture. Against a
        # clean canonical ladder + byte-identical embed it still freezes the
        # Apple lock outright; the broken-ladder counterpart below proves the
        # validation has teeth.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            policy_path.write_text(
                json.dumps({"launched": False, "frozen_baseline": {"checksums_lock": None}}),
                encoding="utf-8",
            )
            tree = _write_release_tree(root, {})

            policy = arm(policy_path, **tree)

            self.assertTrue(policy["launched"])
            self.assertEqual(
                policy["frozen_baseline"]["checksums_lock"],
                _lock_entries({"001": SHA_BASELINE}),
            )

    def test_first_arm_replaces_stale_dormant_checksum_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            stale = {
                "launched": False,
                "frozen_baseline": {
                    "checksums_lock": {
                        "001": {"name": "001_wrong.sql", "sha256": SHA_A}
                    }
                },
            }
            policy_path.write_text(json.dumps(stale), encoding="utf-8")
            tree = _write_release_tree(root, {})

            policy = arm(policy_path, **tree)

            self.assertEqual(
                policy["frozen_baseline"]["checksums_lock"],
                _lock_entries({"001": SHA_BASELINE}),
            )

    def test_first_arm_on_broken_ladder_raises_and_leaves_policy_untouched(self) -> None:
        # M5: a first arm must REFUSE a broken canonical ladder rather than
        # freeze a wrong baseline permanently. Here the canonical schema.sql no
        # longer matches its own lock entry 001 — exactly the drift a first arm
        # would otherwise pin into frozen_baseline forever.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            original_policy = {"launched": False, "frozen_baseline": {"checksums_lock": None}}
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            # Break the canonical ladder: lock 001 no longer matches the schema
            # it names (both the canonical and embed locks, so no embed drift
            # masks the ladder failure).
            broken_lock = json.dumps({"001": {"name": "001_schema.sql", "sha256": SHA_A}})
            tree["canonical_lock_path"].write_text(broken_lock, encoding="utf-8")
            tree["lock_path"].write_text(broken_lock, encoding="utf-8")

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(any("does not match" in v for v in ctx.exception.violations))
            # The policy file is byte-for-byte what it was before the refused arm.
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )


class EmbedParityArmTests(unittest.TestCase):
    """``arm()`` refuses when the Apple embed has drifted from canonical (#10).

    ``--arm`` is the operation that freezes the shipped baseline permanently,
    but the release path only requires the freeze to be armed — the byte-parity
    of the Apple embed against the canonical ``schema/`` copies is otherwise
    enforced only by the separate ``verify_schema_embed.sh``. These pin that
    ``arm()`` runs that parity itself: a drifted embed hard-fails the arm and
    leaves ``migration_policy.json`` untouched, while a byte-identical
    embed+canonical (including migrations) still arms.
    """

    def test_arm_succeeds_when_embed_is_byte_identical_including_migrations(self) -> None:
        # A post-launch re-arm (a ladder migration is only legal once launched)
        # with a byte-identical embed folds the new checksum in — the migration
        # embed-parity path runs and passes.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(_armed({"001": SHA_BASELINE})), encoding="utf-8")
            tree = _write_release_tree(root, {"002": ("002_widgets.sql", MIGRATION_002_SQL)})

            policy = arm(policy_path, **tree)

            self.assertTrue(policy["launched"])
            self.assertEqual(
                policy["frozen_baseline"]["checksums_lock"],
                _lock_entries({"001": SHA_BASELINE, "002": SHA_MIGRATION_002}),
            )

    def test_arm_refused_when_apple_schema_embed_drifts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = {"launched": False, "frozen_baseline": {"checksums_lock": None}}
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            # The bundled schema.sql no longer matches the canonical authority.
            tree["apple_schema_sql_path"].write_text(
                BASELINE_SQL + "\n-- drifted embed\n", encoding="utf-8"
            )

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(
                any("embed parity" in v and "schema.sql" in v for v in ctx.exception.violations)
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_arm_refused_when_apple_lock_embed_drifts_even_with_equal_shas(self) -> None:
        # The embed lock parses to the same version->sha map (so freeze and
        # ladder both pass) but its bytes differ from canonical — only the
        # byte-for-byte embed-parity check can catch this.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = {"launched": False, "frozen_baseline": {"checksums_lock": None}}
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            same_map = json.loads(tree["canonical_lock_path"].read_text(encoding="utf-8"))
            tree["lock_path"].write_text(json.dumps(same_map, indent=2), encoding="utf-8")

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(
                any("embed parity" in v and "checksums.lock" in v for v in ctx.exception.violations)
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_arm_refused_when_apple_migration_embed_is_missing(self) -> None:
        # Armed (a ladder migration is legal only post-launch) so the missing
        # embed is the only violation the arm can raise on.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = _armed({"001": SHA_BASELINE})
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {"002": ("002_widgets.sql", MIGRATION_002_SQL)})
            # A canonical migration with no Apple embed.
            (tree["apple_migrations_dir"] / "002_widgets.sql").unlink()

            with self.assertRaises(SchemaFreezeArmError) as ctx:
                arm(policy_path, **tree)

            self.assertTrue(
                any("embed parity" in v and "002_widgets.sql" in v for v in ctx.exception.violations)
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_embed_parity_violations_clean_tree_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tree = _write_release_tree(root, {"002": ("002_widgets.sql", MIGRATION_002_SQL)})
            self.assertEqual(
                embed_parity_violations(
                    tree["canonical_schema_sql_path"],
                    tree["apple_schema_sql_path"],
                    tree["canonical_lock_path"],
                    tree["lock_path"],
                    tree["canonical_migrations_dir"],
                    tree["apple_migrations_dir"],
                ),
                [],
            )


class PayloadContractArmTests(unittest.TestCase):
    def test_first_arm_freezes_payload_contract_with_sqlite_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy_path = root / "migration_policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "launched": False,
                        "frozen_baseline": {
                            "checksums_lock": None,
                            "sync_payload_contracts": None,
                        },
                    }
                ),
                encoding="utf-8",
            )
            tree = _write_release_tree(root, {})

            policy = arm(policy_path, **tree)

            self.assertEqual(
                policy["frozen_baseline"]["sync_payload_contracts"],
                {"001": SHA_PAYLOAD_CONTRACT},
            )

    def test_rearm_refuses_mutated_released_payload_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = _armed({"001": SHA_BASELINE})
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            changed = json.loads(PAYLOAD_CONTRACT)
            # Keep the manifest structurally valid so this specifically proves
            # that a released contract's byte hash is immutable, rather than
            # being rejected earlier as an internally malformed manifest.
            changed["entities"]["list"]["fields"]["title"]["types"] = [
                "null",
                "string",
            ]
            tree["payload_contracts_dir"].joinpath("001.json").write_text(
                json.dumps(changed, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )

            with self.assertRaises(SchemaFreezeArmError) as context:
                arm(policy_path, **tree)

            self.assertTrue(
                any(
                    "sync payload contract 001 changed" in violation
                    for violation in context.exception.violations
                )
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )

    def test_rearm_folds_in_next_contiguous_payload_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = _armed({"001": SHA_BASELINE})
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            second_text = _write_payload_contract(
                root, 2, ["id", "status", "title", "version"]
            )
            tree["payload_version_source_path"].write_text(
                "public enum LorvexVersion {\n"
                "  public static let payloadSchemaVersion: UInt32 = 2\n"
                "}\n",
                encoding="utf-8",
            )

            policy = arm(policy_path, **tree)

            self.assertEqual(
                policy["frozen_baseline"]["sync_payload_contracts"],
                {
                    "001": SHA_PAYLOAD_CONTRACT,
                    "002": hashlib.sha256(second_text.encode("utf-8")).hexdigest(),
                },
            )

    def test_arm_refuses_contract_ahead_of_swift_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_policy = {
                "launched": False,
                "frozen_baseline": {
                    "checksums_lock": None,
                    "sync_payload_contracts": None,
                },
            }
            policy_path = root / "migration_policy.json"
            policy_path.write_text(json.dumps(original_policy), encoding="utf-8")
            tree = _write_release_tree(root, {})
            _write_payload_contract(root, 2, PAYLOAD_FIELDS)

            with self.assertRaises(SchemaFreezeArmError) as context:
                arm(policy_path, **tree)

            self.assertTrue(
                any(
                    "ahead of Swift payloadSchemaVersion" in violation
                    for violation in context.exception.violations
                )
            )
            self.assertEqual(
                json.loads(policy_path.read_text(encoding="utf-8")), original_policy
            )


class ContiguousNewEntriesTests(unittest.TestCase):
    def test_first_arm_returns_the_full_contiguous_lock(self) -> None:
        self.assertEqual(
            _contiguous_new_entries({}, {"001": SHA_A, "002": SHA_B}),
            {"001": SHA_A, "002": SHA_B},
        )

    def test_stops_at_the_first_gap(self) -> None:
        # "003" is not contiguous with frozen "001" (expects "002" next), so
        # it is excluded even though it is present in the current lock.
        self.assertEqual(
            _contiguous_new_entries({"001": SHA_A}, {"001": SHA_A, "003": SHA_C}),
            {},
        )

    def test_folds_in_a_contiguous_run_past_the_frozen_max(self) -> None:
        self.assertEqual(
            _contiguous_new_entries(
                {"001": SHA_A}, {"001": SHA_A, "002": SHA_B, "003": SHA_C}
            ),
            {"002": SHA_B, "003": SHA_C},
        )

    def test_entries_already_frozen_are_not_recomputed(self) -> None:
        # "001" is in current_lock too, but it is already in prior_frozen, so
        # it is excluded from the *new* entries (arm() keeps the prior value).
        self.assertEqual(
            _contiguous_new_entries({"001": SHA_A}, {"001": SHA_B}),
            {},
        )


if __name__ == "__main__":
    unittest.main()
