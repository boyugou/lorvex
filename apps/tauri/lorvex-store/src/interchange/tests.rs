#![allow(clippy::unwrap_used)]

use super::*;
use crate::connection::open_db_in_memory;
use crate::migration::apply_migrations;
use crate::schema::all_migrations;

fn seed(conn: &Connection) {
    conn.execute_batch(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, created_at, updated_at, version)
         VALUES ('list-1', 'Work', '#FF0000', 'briefcase', 'Work tasks', 'AI notes',
                 '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0000_a1b2c3d4a1b2c3d4');
         INSERT INTO tasks (id, title, body, status, list_id, priority, due_date, estimated_minutes,
                  created_at, updated_at, version)
         VALUES ('task-1', 'Do stuff', 'Body', 'open', 'list-1', 2, '2026-03-25', 60,
                 '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_a1b2c3d4a1b2c3d4');
         INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
         VALUES ('tag-1', 'Urgent', 'urgent', '#FF0000',
                 '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0003_a1b2c3d4a1b2c3d4');
         INSERT INTO task_tags (task_id, tag_id, created_at, version)
         VALUES ('task-1', 'tag-1', '2026-01-01T00:00:00Z', '1711234567890_0005_a1b2c3d4a1b2c3d4');",
    )
    .unwrap();
}

#[test]
fn included_tables_exclude_sync_runtime_and_history() {
    let conn = open_db_in_memory().unwrap();
    let tables = included_tables(&conn).unwrap();
    for present in [
        "tasks",
        "lists",
        "tags",
        "task_tags",
        "habits",
        "habit_completions",
    ] {
        assert!(tables.contains(&present.to_string()), "missing {present}");
    }
    for absent in [
        "ai_changelog",
        "sync_outbox",
        "sync_tombstones",
        "schema_migrations",
        "memory_revisions",
        "device_state",
        "tasks_fts",
    ] {
        assert!(
            !tables.contains(&absent.to_string()),
            "{absent} must not export"
        );
    }
}

#[test]
fn rows_round_trip_through_export_and_import() {
    let source = open_db_in_memory().unwrap();
    seed(&source);
    let data = export_data_jsonl(&source).unwrap();
    assert!(!data.is_empty());

    let target = open_db_in_memory().unwrap();
    let tx = target.unchecked_transaction().unwrap();
    let counts = import_data_jsonl(&tx, &data).unwrap();
    tx.commit().unwrap();
    assert_eq!(counts.get("tasks"), Some(&1));
    assert_eq!(counts.get("task_tags"), Some(&1));

    let title: String = target
        .query_row("SELECT title FROM tasks WHERE id='task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(title, "Do stuff");
    let linked: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id='task-1' AND tag_id='tag-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(linked, 1);
    // FTS rebuilt by the schema's own triggers on insert.
    let fts: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM tasks_fts WHERE tasks_fts MATCH 'stuff'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(fts, 1);
}

#[test]
fn partial_export_pulls_owned_descendants_and_references_but_not_siblings() {
    let conn = open_db_in_memory().unwrap();
    conn.execute_batch(
        "INSERT INTO lists (id, name, created_at, updated_at, version) VALUES
           ('list-1','L1','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0001_a1b2c3d4a1b2c3d4'),
           ('list-2','L2','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0002_a1b2c3d4a1b2c3d4');
         INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version) VALUES
           ('task-1','T1','open','list-1','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0003_a1b2c3d4a1b2c3d4'),
           ('task-2','T2','open','list-1','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0004_a1b2c3d4a1b2c3d4'),
           ('task-3','T3','open','list-2','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0005_a1b2c3d4a1b2c3d4');
         INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version) VALUES
           ('tag-1','Tag','tag','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','1711234567890_0006_a1b2c3d4a1b2c3d4');
         INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES
           ('task-1','tag-1','2026-01-01T00:00:00Z','1711234567890_0007_a1b2c3d4a1b2c3d4');",
    )
    .unwrap();

    let data = export_data_jsonl_partial(
        &conn,
        &[Seed {
            table: "lists".into(),
            id: "list-1".into(),
        }],
    )
    .unwrap();

    // Collect (type, id) from each line.
    let mut ids: std::collections::BTreeMap<String, std::collections::BTreeSet<String>> =
        Default::default();
    let mut task_tag_count = 0;
    for line in data.split(|b| *b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value = serde_json::from_slice(line).unwrap();
        let ty = v["type"].as_str().unwrap().to_string();
        if ty == "task_tags" {
            task_tag_count += 1;
        }
        if let Some(id) = v["row"]["id"].as_str() {
            ids.entry(ty).or_default().insert(id.to_string());
        }
    }
    assert_eq!(ids["lists"], ["list-1".to_string()].into_iter().collect());
    assert_eq!(
        ids["tasks"],
        ["task-1".to_string(), "task-2".to_string()]
            .into_iter()
            .collect()
    );
    assert_eq!(ids["tags"], ["tag-1".to_string()].into_iter().collect());
    assert_eq!(task_tag_count, 1);

    // The slice imports cleanly into a fresh DB.
    let target = open_db_in_memory().unwrap();
    let tx = target.unchecked_transaction().unwrap();
    import_data_jsonl(&tx, &data).unwrap();
    tx.commit().unwrap();
    let task_count: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |r| r.get(0))
        .unwrap();
    assert_eq!(task_count, 2);
}

/// Self-consistency of the v1 container contract: a freshly exported archive
/// holds exactly `manifest.json` + `data.jsonl` (no `blobs/` area), the
/// manifest carries no `blob_count`, and importing applies exactly the row
/// counts the manifest declares.
#[test]
fn exported_archive_matches_the_v1_container_inventory_contract() {
    let source = open_db_in_memory().unwrap();
    seed(&source);
    let (archive, _manifest) = export_archive(&source, "test", &[]).unwrap();

    let mut zip = zip::ZipArchive::new(Cursor::new(&archive[..])).unwrap();
    let mut names = Vec::new();
    for i in 0..zip.len() {
        names.push(zip.by_index(i).unwrap().name().to_string());
    }
    names.sort();
    assert_eq!(
        names,
        vec!["data.jsonl".to_string(), "manifest.json".to_string()],
        "a v1 interchange archive contains exactly manifest.json + data.jsonl"
    );

    let mut manifest_bytes = Vec::new();
    zip.by_name("manifest.json")
        .unwrap()
        .read_to_end(&mut manifest_bytes)
        .unwrap();
    let manifest: Json = serde_json::from_slice(&manifest_bytes).unwrap();
    assert!(
        manifest.get("blob_count").is_none(),
        "the v1 manifest has no blob_count field"
    );

    let expected: BTreeMap<String, u64> =
        serde_json::from_value(manifest["row_counts"].clone()).unwrap();
    assert!(!expected.is_empty());
    let conn = open_db_in_memory().unwrap();
    let summary = import_archive(&conn, &archive).unwrap();
    assert_eq!(
        summary.row_counts, expected,
        "imported row counts must match manifest.row_counts"
    );
}

/// Importing into a NON-empty store merges non-destructively: a colliding
/// parent row is updated in place (never delete-then-reinserted), so
/// `ON DELETE CASCADE` never fires and local-only child rows the archive
/// omits survive the import.
#[test]
fn import_into_a_populated_store_preserves_local_only_children() {
    let source = open_db_in_memory().unwrap();
    seed(&source);
    let (archive, _manifest) = export_archive(&source, "test", &[]).unwrap();

    // The target already holds the same task plus a local-only checklist item
    // the archive does not carry.
    let target = open_db_in_memory().unwrap();
    seed(&target);
    target
        .execute_batch(
            "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at)
             VALUES ('check-1', 'task-1', 1, 'Local-only step',
                     '1711234567891_0000_a1b2c3d4a1b2c3d4',
                     '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z');",
        )
        .unwrap();

    let summary = import_archive(&target, &archive).unwrap();
    assert_eq!(summary.row_counts.get("tasks"), Some(&1));

    let surviving: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM task_checklist_items WHERE task_id='task-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        surviving, 1,
        "local-only child rows must survive a merge import"
    );
    // The colliding task row took the archive's values in place.
    let title: String = target
        .query_row("SELECT title FROM tasks WHERE id='task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(title, "Do stuff");
    // FTS stayed consistent through the merge (rebuilt from backing tables).
    let fts: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM tasks_fts WHERE tasks_fts MATCH 'stuff'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(fts, 1);
}

#[test]
fn archive_round_trips_and_rejects_a_tampered_digest() {
    let source = open_db_in_memory().unwrap();
    seed(&source);
    let (archive, _manifest) = export_archive(&source, "test", &[]).unwrap();

    let target = open_db_in_memory().unwrap();
    let summary = import_archive(&target, &archive).unwrap();
    assert_eq!(summary.row_counts.get("tasks"), Some(&1));
    let title: String = target
        .query_row("SELECT title FROM tasks WHERE id='task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(title, "Do stuff");

    // A tampered manifest digest is rejected.
    let manifest = InterchangeManifest {
        format: FORMAT.to_string(),
        version: VERSION,
        created_at: "2026-01-01T00:00:00.000Z".to_string(),
        source_app: "lorvex-tauri".to_string(),
        source_app_version: "x".to_string(),
        row_counts: BTreeMap::new(),
        data_sha256: "deadbeef".to_string(),
    };
    let mut buf = Vec::new();
    {
        let mut zip = ZipWriter::new(Cursor::new(&mut buf));
        let opt = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
        zip.start_file("manifest.json", opt).unwrap();
        zip.write_all(&serde_json::to_vec(&manifest).unwrap())
            .unwrap();
        zip.start_file("data.jsonl", opt).unwrap();
        zip.write_all(b"{\"type\":\"lists\",\"row\":{}}\n").unwrap();
        zip.finish().unwrap();
    }
    let bad = open_db_in_memory().unwrap();
    assert!(import_archive(&bad, &buf).is_err());
}

// ---------------------------------------------------------------------------
// H9 — the import allowlist gate.
// ---------------------------------------------------------------------------

#[test]
fn is_importable_table_matches_the_denylist_and_internal_filters() {
    assert!(is_importable_table("tasks"));
    assert!(is_importable_table("lists"));
    for denied in DENYLIST {
        assert!(
            !is_importable_table(denied),
            "{denied} must not be importable"
        );
    }
    assert!(!is_importable_table("tasks_fts"));
    assert!(!is_importable_table("calendar_events_fts"));
    assert!(!is_importable_table("sqlite_sequence"));
}

/// H9 regression: a crafted archive carrying a row for EVERY denylisted
/// internal table (sync/runtime/device/diagnostic internals, the
/// migration-bookkeeping row, superseded history — derived from the same
/// `DENYLIST` the export path uses) must write NONE of them.
/// `import_data_jsonl` must reject a denied table's row via
/// `is_importable_table` BEFORE any schema introspection or upsert, so an
/// otherwise-malformed row (missing NOT NULL columns, wrong column types
/// under a `STRICT` table) never even reaches SQLite — it is silently
/// dropped, not an error.
#[test]
fn import_rejects_every_denylisted_table_row() {
    let conn = open_db_in_memory().unwrap();
    let mut crafted = String::new();
    for table in DENYLIST {
        crafted.push_str(&format!(
            "{{\"type\":\"{table}\",\"row\":{{\"id\":\"evil\",\"version\":\"9999999999999_9999_ffffffffffffffff\"}}}}\n"
        ));
    }

    let tx = conn.unchecked_transaction().unwrap();
    let counts = import_data_jsonl(&tx, crafted.as_bytes()).unwrap();
    tx.commit().unwrap();
    assert!(
        counts.is_empty(),
        "every denylisted table row must be dropped, got {counts:?}"
    );

    // The store still opens: nothing corrupted `schema_migrations` or any
    // other internal table the crafted rows targeted.
    apply_migrations(&conn, &all_migrations()).expect("store must still open");
}

/// A row typed with a table name absent from the live schema (an archive
/// authored against an older schema, or a hand-crafted name) is silently
/// dropped through the unknown-table lane: `exportable_columns` finds no
/// columns via `pragma_table_xinfo`, so no INSERT is attempted and the
/// import continues (unknown columns and unknown tables are ignored).
#[test]
fn import_skips_rows_for_tables_absent_from_the_live_schema() {
    let conn = open_db_in_memory().unwrap();
    let crafted = "{\"type\":\"table_that_never_existed\",\"row\":{\"id\":\"x\"}}\n\
                   {\"type\":\"sync_outbox_undo_group_tokens\",\"row\":{\"outbox_id\":1,\"token\":\"t\"}}\n";

    let tx = conn.unchecked_transaction().unwrap();
    let counts = import_data_jsonl(&tx, crafted.as_bytes()).unwrap();
    tx.commit().unwrap();
    assert!(
        counts.is_empty(),
        "unknown-table rows must be dropped without error, got {counts:?}"
    );
}

/// H9 regression, the exact scenario the audit probed: a crafted archive
/// row for `schema_migrations` must not overwrite an already-applied
/// migration's checksum. Pre-fix, `import_data_jsonl` upserted into ANY
/// table present in the schema, so this row flipped migration 1's checksum
/// to a bogus value; the very next `apply_migrations` call (the next store
/// open) then fails with `MigrationError::ChecksumMismatch`, bricking the
/// store.
#[test]
fn import_rejects_a_schema_migrations_checksum_tamper_and_the_store_still_opens() {
    let conn = open_db_in_memory().unwrap();
    let original_checksum: String = conn
        .query_row(
            "SELECT checksum FROM schema_migrations WHERE version = 1",
            [],
            |r| r.get(0),
        )
        .unwrap();

    let crafted = b"{\"type\":\"schema_migrations\",\"row\":{\"version\":1,\"name\":\"tampered\",\"checksum\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"}}\n";
    let tx = conn.unchecked_transaction().unwrap();
    let counts = import_data_jsonl(&tx, crafted).unwrap();
    tx.commit().unwrap();
    assert!(
        counts.is_empty(),
        "the schema_migrations tamper must be dropped, got {counts:?}"
    );

    let checksum_after: String = conn
        .query_row(
            "SELECT checksum FROM schema_migrations WHERE version = 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        checksum_after, original_checksum,
        "migration 1's checksum must be unchanged"
    );

    // The store still opens: re-running the migration pipeline re-verifies
    // every already-applied checksum and must not fail.
    apply_migrations(&conn, &all_migrations())
        .expect("store must still open after the rejected tamper");
}

/// H9 regression: a crafted archive can also target `sync_outbox` (a sync
/// internal) and an FTS shadow (`tasks_fts`) directly — neither may be
/// written.
#[test]
fn import_rejects_sync_internal_and_fts_shadow_rows() {
    let conn = open_db_in_memory().unwrap();
    let crafted = b"{\"type\":\"sync_outbox\",\"row\":{\"id\":\"evil-1\"}}\n\
                    {\"type\":\"tasks_fts\",\"row\":{\"rowid\":1,\"title\":\"x\"}}\n";
    let tx = conn.unchecked_transaction().unwrap();
    let counts = import_data_jsonl(&tx, crafted).unwrap();
    tx.commit().unwrap();
    assert!(
        counts.is_empty(),
        "denied tables must be skipped, got {counts:?}"
    );

    let outbox_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |r| r.get(0))
        .unwrap();
    assert_eq!(outbox_count, 0);
}

// ---------------------------------------------------------------------------
// M13 — sync-critical column validation at the import boundary.
// ---------------------------------------------------------------------------

/// M13 regression: a `version` that is not a canonical HLC must be rejected
/// at the import boundary rather than bound verbatim — binding it would
/// taint LWW comparison and the outbound version stamp this store restamps
/// onto the row when it enqueues it for sync.
#[test]
fn import_rejects_a_tainted_version() {
    let target = open_db_in_memory().unwrap();
    let crafted = b"{\"type\":\"lists\",\"row\":{\"id\":\"list-9\",\"name\":\"Bad\",\
                    \"created_at\":\"2026-01-01T00:00:00.000Z\",\
                    \"updated_at\":\"2026-01-01T00:00:00.000Z\",\
                    \"version\":\"not-an-hlc\"}}\n";
    {
        let tx = target.unchecked_transaction().unwrap();
        let err = import_data_jsonl(&tx, crafted).unwrap_err();
        match err {
            InterchangeError::InvalidValue {
                table,
                column,
                value,
            } => {
                assert_eq!(table, "lists");
                assert_eq!(column, "version");
                assert_eq!(value, "not-an-hlc");
            }
            other => panic!("expected InvalidValue, got {other:?}"),
        }
        // `tx` drops here without a commit, rolling back.
    }

    let count: i64 = target
        .query_row("SELECT COUNT(*) FROM lists WHERE id = 'list-9'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(count, 0, "the tainted row must not be bound");
}

/// M13 regression: `Hlc::parse` alone is not a strict-enough gate — it
/// parses the numeric segments via `str::parse`, which accepts a leading
/// `+`. A `+`-prefixed physical-ms segment must still be rejected: it would
/// byte-sort BELOW every digit-only peer value and break the lexicographic
/// version ordering LWW and SQL range queries rely on.
#[test]
fn import_rejects_a_version_with_a_leading_plus_sign() {
    let target = open_db_in_memory().unwrap();
    let crafted = b"{\"type\":\"lists\",\"row\":{\"id\":\"list-9\",\"name\":\"Bad\",\
                    \"created_at\":\"2026-01-01T00:00:00.000Z\",\
                    \"updated_at\":\"2026-01-01T00:00:00.000Z\",\
                    \"version\":\"+711234567890_0001_a1b2c3d4a1b2c3d4\"}}\n";
    let tx = target.unchecked_transaction().unwrap();
    let err = import_data_jsonl(&tx, crafted).unwrap_err();
    assert!(
        matches!(err, InterchangeError::InvalidValue { ref column, .. } if column == "version"),
        "expected a version InvalidValue, got {err:?}"
    );
}

/// M13 regression: an `*_at` column that is not a parseable RFC 3339
/// instant must be rejected rather than bound as a value that sorts wrong
/// in date-range queries.
#[test]
fn import_rejects_an_unparseable_timestamp() {
    let target = open_db_in_memory().unwrap();
    let crafted = b"{\"type\":\"lists\",\"row\":{\"id\":\"list-9\",\"name\":\"Bad\",\
                    \"created_at\":\"nonsense\",\
                    \"updated_at\":\"2026-01-01T00:00:00.000Z\",\
                    \"version\":\"1711234567890_0001_a1b2c3d4a1b2c3d4\"}}\n";
    let tx = target.unchecked_transaction().unwrap();
    let err = import_data_jsonl(&tx, crafted).unwrap_err();
    match err {
        InterchangeError::InvalidValue {
            table,
            column,
            value,
        } => {
            assert_eq!(table, "lists");
            assert_eq!(column, "created_at");
            assert_eq!(value, "nonsense");
        }
        other => panic!("expected InvalidValue, got {other:?}"),
    }
}

/// M13: a parseable but non-canonical timestamp (second precision, or a
/// non-UTC offset) is normalized to the canonical millisecond UTC form so
/// it sorts correctly against this store's own timestamps.
#[test]
fn import_normalizes_a_non_canonical_timestamp_precision() {
    let target = open_db_in_memory().unwrap();
    let crafted = b"{\"type\":\"lists\",\"row\":{\"id\":\"list-9\",\"name\":\"OK\",\
                    \"created_at\":\"2026-03-04T05:06:07Z\",\
                    \"updated_at\":\"2026-03-04T05:06:07+00:00\",\
                    \"version\":\"1711234567890_0001_a1b2c3d4a1b2c3d4\"}}\n";
    let tx = target.unchecked_transaction().unwrap();
    import_data_jsonl(&tx, crafted).unwrap();
    tx.commit().unwrap();

    let created_at: String = target
        .query_row(
            "SELECT created_at FROM lists WHERE id = 'list-9'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        created_at, "2026-03-04T05:06:07.000Z",
        "second-precision Z is normalized to millisecond UTC"
    );
    let updated_at: String = target
        .query_row(
            "SELECT updated_at FROM lists WHERE id = 'list-9'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        updated_at, "2026-03-04T05:06:07.000Z",
        "a +00:00 offset is normalized to millisecond UTC"
    );
}
