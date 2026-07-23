#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest

from verify_migration_ladder import (
    LOCK_PATH,
    SCHEMA_SQL_PATH,
    build_lock,
    closure_violations,
    ladder_violations,
    load_lock,
    normalize_migration_sql,
    sha256_migration_hex,
)

WIDGETS_SQL = "CREATE TABLE widgets (id TEXT PRIMARY KEY) STRICT;"
GADGETS_SQL = "CREATE TABLE gadgets (id TEXT PRIMARY KEY) STRICT;"
BASELINE_SQL = "CREATE TABLE tasks (id TEXT PRIMARY KEY) STRICT;"


def _lock(entries: dict[str, tuple[str, str]]) -> dict:
    return {key: {"name": name, "sha256": sha} for key, (name, sha) in entries.items()}


def _baseline_lock() -> dict:
    return _lock({"001": ("001_schema.sql", sha256_migration_hex(BASELINE_SQL))})


PRE_LAUNCH = {"launched": False}


def _post_launch(frozen: dict[str, str]) -> dict:
    names = {
        "001": "001_schema.sql",
        "002": "002_add_widgets.sql",
        "003": "003_add_gadgets.sql",
    }
    entries = {
        version: {"name": names[version], "sha256": sha}
        for version, sha in frozen.items()
    }
    return {"launched": True, "frozen_baseline": {"checksums_lock": entries}}


def _post_launch_entries(frozen: dict[str, dict[str, str]]) -> dict:
    return {"launched": True, "frozen_baseline": {"checksums_lock": frozen}}


class NormalizationTests(unittest.TestCase):
    """The Python digest must agree with the Swift runtime authority.

    The repo-pin test is the load-bearing one: hashing the real schema.sql must
    reproduce the canonical lock's 001 entry — the value the Swift
    ``MigrationSqlChecksum`` verifies at boot — so this seeder/verifier and the
    runtime agree on the only production input. The Tauri Rust/Node digest uses
    the same normalization convention but is a separate, directionally-aligned
    implementation, not a byte-locked contract this test pins against.
    """

    def test_real_schema_sql_matches_canonical_lock(self) -> None:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        schema_sql = SCHEMA_SQL_PATH.read_text(encoding="utf-8")
        self.assertEqual(sha256_migration_hex(schema_sql), lock["001"]["sha256"])

    def test_comment_only_edits_do_not_change_the_digest(self) -> None:
        base = "CREATE TABLE t (id TEXT);\nCREATE INDEX i ON t(id);"
        reflowed = (
            "-- a five-line\n-- comment block\nCREATE TABLE t (id TEXT);\n"
            "/* a block\n   comment spanning\n   lines */\n"
            "CREATE INDEX i ON t(id);  -- trailing inline comment\n"
        )
        self.assertEqual(sha256_migration_hex(base), sha256_migration_hex(reflowed))

    def test_semantic_edits_change_the_digest(self) -> None:
        self.assertNotEqual(
            sha256_migration_hex("CREATE TABLE t (id TEXT);"),
            sha256_migration_hex("CREATE TABLE t (id INTEGER);"),
        )
        # Interior whitespace inside non-comment SQL is significant.
        self.assertNotEqual(
            sha256_migration_hex("CREATE TABLE t (id TEXT);"),
            sha256_migration_hex("CREATE  TABLE t (id TEXT);"),
        )

    def test_bom_and_crlf_are_normalized_away(self) -> None:
        unix = "CREATE TABLE t (id TEXT);\nCREATE INDEX i ON t(id);\n"
        windows = "﻿CREATE TABLE t (id TEXT);\r\nCREATE INDEX i ON t(id);\r\n"
        self.assertEqual(sha256_migration_hex(unix), sha256_migration_hex(windows))

    def test_comment_markers_inside_literals_are_preserved(self) -> None:
        self.assertEqual(
            normalize_migration_sql("INSERT INTO t VALUES ('a -- not a comment');"),
            "INSERT INTO t VALUES ('a -- not a comment');",
        )
        self.assertEqual(
            normalize_migration_sql('SELECT "quoted /* ident */" FROM t;'),
            'SELECT "quoted /* ident */" FROM t;',
        )
        # Escaped quotes keep the literal run open across an embedded marker.
        self.assertEqual(
            normalize_migration_sql("INSERT INTO t VALUES ('it''s -- literal');"),
            "INSERT INTO t VALUES ('it''s -- literal');",
        )

    def test_unterminated_block_comment_runs_to_end(self) -> None:
        self.assertEqual(
            normalize_migration_sql("CREATE TABLE t (id TEXT); /* open"),
            "CREATE TABLE t (id TEXT);",
        )


class SeedTests(unittest.TestCase):
    def test_build_lock_reproduces_the_committed_canonical_lock(self) -> None:
        # The Apple-native `--seed` (build_lock) must produce byte-identical output
        # to the committed lock — proving it is a drop-in replacement for the former
        # Tauri Node seeder, so Apple regenerates the lock on its own with no drift.
        self.assertEqual(build_lock(), load_lock())


class LadderViolationsTests(unittest.TestCase):
    def test_empty_pre_launch_ladder_passes(self) -> None:
        self.assertEqual(
            ladder_violations(_baseline_lock(), BASELINE_SQL, {}, PRE_LAUNCH), []
        )

    def test_pre_launch_migration_file_is_rejected(self) -> None:
        lock = _baseline_lock()
        lock["002"] = {"name": "002_add_widgets.sql", "sha256": sha256_migration_hex(WIDGETS_SQL)}
        violations = ladder_violations(
            lock, BASELINE_SQL, {"002_add_widgets.sql": WIDGETS_SQL}, PRE_LAUNCH
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("pre-launch", violations[0])
        self.assertIn("002_add_widgets.sql", violations[0])

    def test_post_launch_ladder_with_migrations_passes(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        lock = _lock(
            {
                "001": ("001_schema.sql", baseline_sha),
                "002": ("002_add_widgets.sql", sha256_migration_hex(WIDGETS_SQL)),
                "003": ("003_add_gadgets.sql", sha256_migration_hex(GADGETS_SQL)),
            }
        )
        files = {"002_add_widgets.sql": WIDGETS_SQL, "003_add_gadgets.sql": GADGETS_SQL}
        self.assertEqual(
            ladder_violations(
                lock, BASELINE_SQL, files, _post_launch({"001": baseline_sha})
            ),
            [],
        )

    def test_post_launch_schema_edit_requires_a_migration(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        violations = ladder_violations(
            _baseline_lock(),
            BASELINE_SQL + "\nCREATE TABLE sneaky (id TEXT);\n",
            {},
            _post_launch({"001": baseline_sha}),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("immutable", violations[0])
        self.assertIn("NNN_<name>.sql migration", violations[0])

    def test_pre_launch_schema_edit_points_at_reseed(self) -> None:
        violations = ladder_violations(
            _baseline_lock(),
            BASELINE_SQL + "\nCREATE TABLE fine_pre_launch (id TEXT);\n",
            {},
            PRE_LAUNCH,
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("--seed", violations[0])

    def test_version_gap_is_rejected(self) -> None:
        lock = _baseline_lock()
        lock["003"] = {"name": "003_add_gadgets.sql", "sha256": sha256_migration_hex(GADGETS_SQL)}
        violations = ladder_violations(
            lock,
            BASELINE_SQL,
            {"003_add_gadgets.sql": GADGETS_SQL},
            _post_launch({"001": sha256_migration_hex(BASELINE_SQL)}),
        )
        self.assertTrue(any("not contiguous" in violation for violation in violations))

    def test_edited_recorded_migration_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        lock = _baseline_lock()
        lock["002"] = {"name": "002_add_widgets.sql", "sha256": sha256_migration_hex(WIDGETS_SQL)}
        violations = ladder_violations(
            lock,
            BASELINE_SQL,
            {"002_add_widgets.sql": WIDGETS_SQL + "\nALTER TABLE widgets ADD extra TEXT;\n"},
            _post_launch({"001": baseline_sha}),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("frozen", violations[0])

    def test_locked_migration_without_file_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        lock = _baseline_lock()
        lock["002"] = {"name": "002_add_widgets.sql", "sha256": sha256_migration_hex(WIDGETS_SQL)}
        violations = ladder_violations(
            lock, BASELINE_SQL, {}, _post_launch({"001": baseline_sha})
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("missing", violations[0])

    def test_unrecorded_migration_file_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        violations = ladder_violations(
            _baseline_lock(),
            BASELINE_SQL,
            {"002_add_widgets.sql": WIDGETS_SQL},
            _post_launch({"001": baseline_sha}),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("no checksums.lock entry", violations[0])

    def test_reserved_and_misnamed_files_are_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        violations = ladder_violations(
            _baseline_lock(),
            BASELINE_SQL,
            {"001_schema.sql": BASELINE_SQL, "002-BadName.sql": WIDGETS_SQL},
            _post_launch({"001": baseline_sha}),
        )
        self.assertEqual(len(violations), 2)
        self.assertTrue(any("reserved version" in violation for violation in violations))
        self.assertTrue(any("naming contract" in violation for violation in violations))

    def test_misnumbered_lock_entry_name_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        lock = _baseline_lock()
        lock["002"] = {"name": "003_add_widgets.sql", "sha256": sha256_migration_hex(WIDGETS_SQL)}
        violations = ladder_violations(
            lock,
            BASELINE_SQL,
            {"003_add_widgets.sql": WIDGETS_SQL},
            _post_launch({"001": baseline_sha}),
        )
        self.assertTrue(any("002" in violation and "003_add_widgets" in violation for violation in violations))

    def test_post_launch_frozen_entry_mutation_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        frozen = {"001": baseline_sha, "002": sha256_migration_hex(WIDGETS_SQL)}
        # The canonical lock re-recorded 002 with different SQL.
        lock = _baseline_lock()
        lock["002"] = {"name": "002_add_widgets.sql", "sha256": sha256_migration_hex(GADGETS_SQL)}
        violations = ladder_violations(
            lock,
            BASELINE_SQL,
            {"002_add_widgets.sql": GADGETS_SQL},
            _post_launch(frozen),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("frozen lock entry 002 changed", violations[0])

    def test_post_launch_frozen_entry_removal_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        frozen = {"001": baseline_sha, "002": sha256_migration_hex(WIDGETS_SQL)}
        violations = ladder_violations(
            _baseline_lock(), BASELINE_SQL, {}, _post_launch(frozen)
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("removed", violations[0])

    def test_post_launch_frozen_entry_rename_is_rejected(self) -> None:
        baseline_sha = sha256_migration_hex(BASELINE_SQL)
        migration_sha = sha256_migration_hex(WIDGETS_SQL)
        lock = _lock(
            {
                "001": ("001_schema.sql", baseline_sha),
                "002": ("002_renamed.sql", migration_sha),
            }
        )
        frozen = _lock(
            {
                "001": ("001_schema.sql", baseline_sha),
                "002": ("002_add_widgets.sql", migration_sha),
            }
        )

        violations = ladder_violations(
            lock,
            BASELINE_SQL,
            {"002_renamed.sql": WIDGETS_SQL},
            _post_launch_entries(frozen),
        )

        self.assertEqual(len(violations), 1)
        self.assertIn("frozen lock entry 002 changed", violations[0])
        self.assertIn("name", violations[0])

    def test_malformed_lock_entries_are_rejected(self) -> None:
        violations = ladder_violations(
            {"1": {"name": "001_schema.sql", "sha256": "ab"}},
            BASELINE_SQL,
            {},
            PRE_LAUNCH,
        )
        self.assertTrue(violations)


# A baseline whose index over a column lets destructive-migration closure be
# exercised: dropping `retry_count` must also drop or rebuild `idx_outbox_retry`.
CLOSURE_BASELINE = (
    "CREATE TABLE outbox (\n"
    "  id INTEGER PRIMARY KEY,\n"
    "  retry_count INTEGER NOT NULL DEFAULT 0,\n"
    "  synced_at TEXT\n"
    ") STRICT;\n"
    "CREATE INDEX idx_outbox_retry ON outbox(id, retry_count) WHERE synced_at IS NULL;\n"
    "CREATE TRIGGER trg_outbox AFTER INSERT ON outbox BEGIN\n"
    "  UPDATE outbox SET synced_at = NULL WHERE id = NEW.id;\n"
    "END;\n"
)


class ClosureViolationsTests(unittest.TestCase):
    """Destructive migrations are permitted, but each must leave the schema
    closed: no surviving index / trigger / foreign key may reference an object
    the ladder dropped. These drive ``closure_violations`` directly."""

    def test_empty_ladder_drops_nothing_and_is_closed(self) -> None:
        self.assertEqual(closure_violations(CLOSURE_BASELINE, []), [])

    def test_real_schema_with_empty_ladder_is_closed(self) -> None:
        # The live guard: the real baseline with no migrations must never flag.
        schema_sql = SCHEMA_SQL_PATH.read_text(encoding="utf-8")
        self.assertEqual(closure_violations(schema_sql, []), [])

    def test_additive_migration_is_closed(self) -> None:
        migration = (
            "ALTER TABLE outbox ADD COLUMN priority INTEGER NOT NULL DEFAULT 0;\n"
            "CREATE INDEX idx_outbox_priority ON outbox(priority);\n"
        )
        self.assertEqual(closure_violations(CLOSURE_BASELINE, [(2, migration)]), [])

    def test_drop_column_leaving_a_dependent_index_is_flagged(self) -> None:
        violations = closure_violations(
            CLOSURE_BASELINE, [(2, "ALTER TABLE outbox DROP COLUMN retry_count;")]
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("idx_outbox_retry", violations[0])
        self.assertIn("outbox.retry_count", violations[0])
        self.assertIn("migration 002", violations[0])

    def test_dropping_the_index_before_the_column_is_permitted(self) -> None:
        migration = (
            "DROP INDEX idx_outbox_retry;\n"
            "ALTER TABLE outbox DROP COLUMN retry_count;\n"
        )
        self.assertEqual(closure_violations(CLOSURE_BASELINE, [(2, migration)]), [])

    def test_dropping_a_table_removes_its_own_indexes_and_triggers(self) -> None:
        # SQLite drops a table's dependent index/trigger with it; closure must
        # not flag them as dangling.
        self.assertEqual(
            closure_violations(CLOSURE_BASELINE, [(2, "DROP TABLE outbox;")]), []
        )

    def test_foreign_key_to_a_dropped_table_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE users (id TEXT PRIMARY KEY) STRICT;\n"
            "CREATE TABLE posts (id TEXT PRIMARY KEY, author TEXT REFERENCES users(id)) STRICT;\n"
        )
        violations = closure_violations(baseline, [(2, "DROP TABLE users;")])
        self.assertEqual(len(violations), 1)
        self.assertIn("foreign key to users", violations[0])
        self.assertIn("posts", violations[0])

    def test_later_migration_referencing_a_dropped_column_is_flagged(self) -> None:
        proper = (
            "DROP INDEX idx_outbox_retry;\n"
            "ALTER TABLE outbox DROP COLUMN retry_count;\n"
        )
        resurrect = "CREATE INDEX idx_outbox_retry_again ON outbox(retry_count);\n"
        violations = closure_violations(CLOSURE_BASELINE, [(2, proper), (3, resurrect)])
        self.assertEqual(len(violations), 1)
        self.assertIn("migration 003", violations[0])
        self.assertIn("idx_outbox_retry_again", violations[0])

    def test_drop_and_recreate_under_the_same_name_is_permitted(self) -> None:
        migration = (
            "DROP INDEX idx_outbox_retry;\n"
            "ALTER TABLE outbox DROP COLUMN retry_count;\n"
            "ALTER TABLE outbox ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;\n"
            "CREATE INDEX idx_outbox_retry ON outbox(id, retry_count) WHERE synced_at IS NULL;\n"
        )
        self.assertEqual(closure_violations(CLOSURE_BASELINE, [(2, migration)]), [])

    def test_a_trigger_created_on_a_dropped_table_is_flagged(self) -> None:
        drop = "DROP TABLE outbox;"
        readd_trigger = (
            "CREATE TRIGGER trg_ghost AFTER INSERT ON outbox BEGIN\n"
            "  SELECT 1;\n"
            "END;\n"
        )
        violations = closure_violations(CLOSURE_BASELINE, [(2, drop), (3, readd_trigger)])
        self.assertEqual(len(violations), 1)
        self.assertIn("trg_ghost", violations[0])
        self.assertIn("migration 003", violations[0])

    def test_trigger_body_targeting_a_dropped_table_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE audit_log (outbox_id INTEGER) STRICT;\n"
            "CREATE TRIGGER trg_outbox_audit AFTER INSERT ON outbox BEGIN\n"
            "  INSERT INTO audit_log(outbox_id) VALUES (NEW.id);\n"
            "END;\n"
        )

        violations = closure_violations(baseline, [(2, "DROP TABLE audit_log;")])

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_audit", violations[0])
        self.assertIn("dropped table audit_log", violations[0])
        self.assertIn("migration 002", violations[0])

    def test_trigger_replace_body_targeting_a_dropped_table_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE audit_log (outbox_id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TRIGGER trg_outbox_replace AFTER INSERT ON outbox BEGIN\n"
            "  REPLACE INTO audit_log(outbox_id) VALUES (NEW.id);\n"
            "END;\n"
        )

        violations = closure_violations(baseline, [(2, "DROP TABLE audit_log;")])

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_replace", violations[0])
        self.assertIn("dropped table audit_log", violations[0])

    def test_trigger_qualified_from_targeting_a_dropped_table_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE audit_log (outbox_id INTEGER) STRICT;\n"
            "CREATE TRIGGER trg_outbox_lookup AFTER INSERT ON outbox BEGIN\n"
            "  SELECT 1 FROM main.audit_log WHERE outbox_id = NEW.id;\n"
            "END;\n"
        )

        violations = closure_violations(baseline, [(2, "DROP TABLE audit_log;")])

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_lookup", violations[0])
        self.assertIn("dropped table audit_log", violations[0])

    def test_trigger_comma_from_targeting_a_dropped_table_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE keep (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE audit_log (outbox_id INTEGER) STRICT;\n"
            "CREATE TRIGGER trg_outbox_lookup AFTER INSERT ON outbox BEGIN\n"
            "  SELECT 1 FROM keep, audit_log WHERE audit_log.outbox_id = NEW.id;\n"
            "END;\n"
        )

        violations = closure_violations(baseline, [(2, "DROP TABLE audit_log;")])

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_lookup", violations[0])
        self.assertIn("dropped table audit_log", violations[0])

    def test_trigger_parenthesized_from_group_targeting_a_dropped_table_is_flagged(
        self,
    ) -> None:
        baseline = (
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE keep (id INTEGER PRIMARY KEY) STRICT;\n"
            "CREATE TABLE audit_log (outbox_id INTEGER) STRICT;\n"
            "CREATE TRIGGER trg_outbox_lookup AFTER INSERT ON outbox BEGIN\n"
            "  SELECT 1 FROM (keep, audit_log) WHERE audit_log.outbox_id = NEW.id;\n"
            "END;\n"
        )

        violations = closure_violations(baseline, [(2, "DROP TABLE audit_log;")])

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_lookup", violations[0])
        self.assertIn("dropped table audit_log", violations[0])

    def test_trigger_old_new_reference_to_a_dropped_column_is_flagged(self) -> None:
        baseline = (
            "CREATE TABLE outbox (\n"
            "  id INTEGER PRIMARY KEY,\n"
            "  retry_count INTEGER NOT NULL DEFAULT 0\n"
            ") STRICT;\n"
            "CREATE TRIGGER trg_outbox_retry AFTER UPDATE ON outbox BEGIN\n"
            "  SELECT OLD.retry_count, NEW.retry_count;\n"
            "END;\n"
        )

        violations = closure_violations(
            baseline, [(2, "ALTER TABLE outbox DROP COLUMN retry_count;")]
        )

        self.assertEqual(len(violations), 1)
        self.assertIn("trg_outbox_retry", violations[0])
        self.assertIn("outbox.retry_count", violations[0])
        self.assertIn("migration 002", violations[0])


class LadderClosureIntegrationTests(unittest.TestCase):
    """Closure runs as part of ``ladder_violations`` once the lock/file checks
    pass, so a well-formed but schema-breaking ladder is still rejected."""

    def _lock_with(self, migration_name: str, migration_sql: str) -> dict:
        lock = _lock({"001": ("001_schema.sql", sha256_migration_hex(CLOSURE_BASELINE))})
        lock["002"] = {"name": migration_name, "sha256": sha256_migration_hex(migration_sql)}
        return lock

    def test_valid_destructive_ladder_passes_end_to_end(self) -> None:
        migration_sql = (
            "DROP INDEX idx_outbox_retry;\n"
            "ALTER TABLE outbox DROP COLUMN retry_count;\n"
        )
        lock = self._lock_with("002_drop_retry.sql", migration_sql)
        self.assertEqual(
            ladder_violations(
                lock,
                CLOSURE_BASELINE,
                {"002_drop_retry.sql": migration_sql},
                _post_launch({"001": sha256_migration_hex(CLOSURE_BASELINE)}),
            ),
            [],
        )

    def test_unclosed_destructive_ladder_is_rejected_end_to_end(self) -> None:
        migration_sql = "ALTER TABLE outbox DROP COLUMN retry_count;\n"
        lock = self._lock_with("002_drop_retry.sql", migration_sql)
        violations = ladder_violations(
            lock,
            CLOSURE_BASELINE,
            {"002_drop_retry.sql": migration_sql},
            _post_launch({"001": sha256_migration_hex(CLOSURE_BASELINE)}),
        )
        self.assertEqual(len(violations), 1)
        self.assertIn("idx_outbox_retry", violations[0])
        self.assertIn("still references dropped column", violations[0])


if __name__ == "__main__":
    unittest.main()
