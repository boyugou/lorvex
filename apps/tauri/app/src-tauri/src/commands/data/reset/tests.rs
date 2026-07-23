use super::{
    executor::{finalize_reset_transaction, reset_all_data_db},
    manifest::{
        CONTENT_TABLES, RUNTIME_ONLY_TABLES, SYNCABLE_AGGREGATE_TABLES,
        SYNCABLE_INDEPENDENT_CHILD_TABLES, SYNCABLE_RESET_SPECIAL_ENTITY_TYPES,
        SYNC_INFRASTRUCTURE_PRESERVED,
    },
    preferences::reset_preferences_with_conn,
};
use rusqlite::params;
use std::collections::HashSet;

/// every per-preference DELETE
/// envelope ships the pre-delete snapshot
/// (`value` + `version` + `updated_at`), not the legacy `{key}`
/// shape that defeated peer LWW. Local-only preference keys
/// (filesystem bridge root, per-device sync backend choice) must
/// still be skipped — the H13 fix preserves that gate via
/// `enqueue_preference_delete::is_local_only_preference`.
#[test]
fn reset_preferences_per_key_delete_envelope_carries_value_version_and_updated_at() {
    crate::hlc::ensure_hlc_for_test();
    let conn = crate::test_support::test_conn();
    // Seed a single syncable preference (`theme`). The schema also
    // seeds a default `default_list_id` row at migration time, so
    // `reset_preferences_with_conn` will wipe both — the assertion
    // below targets the `theme` envelope specifically.
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('theme', '\"dark\"', '0000000000000_0000_seedprefseedpref',
                 '2026-04-26T08:00:00Z')",
        [],
    )
    .expect("seed preference");

    let result = reset_preferences_with_conn(&conn).expect("reset_preferences");
    assert!(
        result.deleted >= 1,
        "reset must delete at least the seeded `theme` row (got {})",
        result.deleted
    );

    let payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'preference' AND entity_id = 'theme' AND operation = 'delete' \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("load preference delete envelope payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_raw).expect("parse preference payload");
    assert!(
        payload.get("version").and_then(|v| v.as_str()).is_some(),
        "preference delete payload must carry pre-delete `version` (got {payload})"
    );
    assert!(
        payload.get("updated_at").and_then(|v| v.as_str()).is_some(),
        "preference delete payload must carry pre-delete `updated_at` (got {payload})"
    );
    assert_eq!(
        payload.get("key").and_then(|v| v.as_str()),
        Some("theme"),
        "preference delete payload must carry the key"
    );
    assert_eq!(
        payload.get("value").and_then(|v| v.as_str()),
        Some("\"dark\""),
        "preference delete payload must carry the value the user just discarded"
    );

    // After the reset, no preference rows remain locally.
    let remaining: i64 = conn
        .query_row("SELECT COUNT(*) FROM preferences", [], |row| row.get(0))
        .expect("count remaining preferences");
    assert_eq!(remaining, 0);
}

#[test]
fn reset_all_data_db_emits_preference_delete_envelopes() {
    use lorvex_domain::naming::{ENTITY_PREFERENCE, OP_DELETE};

    crate::hlc::ensure_hlc_for_test();
    let conn = crate::test_support::test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES ('theme', '\"dark\"', '0000000000000_0000_seedprefseedpref',
                 '2026-04-26T08:00:00Z')",
        [],
    )
    .expect("seed preference");

    reset_all_data_db(&conn).expect("reset_all_data_db");

    let payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = 'theme' AND operation = ?2
             ORDER BY id DESC LIMIT 1",
            params![ENTITY_PREFERENCE, OP_DELETE],
            |row| row.get(0),
        )
        .expect("load preference delete payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_raw).expect("parse preference payload");
    assert_eq!(payload["key"], "theme");
    assert_eq!(payload["value"], "\"dark\"");
    assert_eq!(payload["version"], "0000000000000_0000_seedprefseedpref");
    assert_eq!(payload["updated_at"], "2026-04-26T08:00:00Z");
}

#[test]
fn reset_all_data_db_emits_ai_changelog_reset_delete_envelopes() {
    use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, ENTITY_TASK, OP_DELETE};

    crate::hlc::ensure_hlc_for_test();
    let conn = crate::test_support::test_conn();
    const CHANGELOG_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000004331";
    conn.execute(
        "INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, entity_id, summary, initiated_by,
             undo_token, is_preview)
         VALUES
            (?1, '2026-04-26T08:00:00Z', 'update', ?2, NULL, 'Reset probe', 'ai',
             NULL, 0)",
        params![CHANGELOG_ID, ENTITY_TASK],
    )
    .expect("seed changelog");

    reset_all_data_db(&conn).expect("reset_all_data_db");

    let payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3
             ORDER BY id DESC LIMIT 1",
            params![ENTITY_AI_CHANGELOG, CHANGELOG_ID, OP_DELETE],
            |row| row.get(0),
        )
        .expect("load ai_changelog delete payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_raw).expect("parse ai_changelog payload");
    assert_eq!(payload["id"], CHANGELOG_ID);
    assert_eq!(payload["reset_all_data"], true);
}

/// Drift guard: every user-data table introduced in `001_schema.sql`
/// must be classified as either content (cleared on reset) or
/// runtime-only (preserved). A new table that lands without an
/// explicit entry in one of those lists silently becomes a
/// "ghost" — the user's "delete all data" leaves it intact and
/// any sync state inside it can resurrect entities the user
/// thinks they've wiped.
#[test]
fn content_tables_covers_every_user_data_table_in_schema() {
    let conn = crate::test_support::test_conn();

    // Discover the FTS5 virtual tables declared in the schema, and
    // build a prefix set so this drift guard skips both the virtual
    // table names AND every shadow table SQLite creates for them
    // (`<name>_data`, `<name>_idx`, `<name>_content`,
    // `<name>_docsize`, `<name>_config`). We can't hard-code the
    // names here because the schema grew a third FTS table
    // (`tasks_fts_trigram`) and adding a fourth shouldn't require
    // touching this test.
    let fts_virtual_tables: HashSet<String> = conn
        .prepare(
            "SELECT name FROM sqlite_master \
             WHERE type='table' AND sql LIKE '%USING fts5%'",
        )
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();

    let is_fts_shadow = |name: &str| {
        fts_virtual_tables
            .iter()
            .any(|fts| name == fts || name.starts_with(&format!("{fts}_")))
    };

    let actual_tables: HashSet<String> = conn
        .prepare(
            "SELECT name FROM sqlite_master \
             WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<HashSet<String>, _>>()
        .unwrap()
        .into_iter()
        .filter(|name| !is_fts_shadow(name))
        .collect();

    let classified: HashSet<String> = CONTENT_TABLES
        .iter()
        .chain(RUNTIME_ONLY_TABLES.iter())
        .chain(SYNC_INFRASTRUCTURE_PRESERVED.iter())
        .map(|s| (*s).to_string())
        .collect();

    let unclassified: Vec<&String> = actual_tables.difference(&classified).collect();
    let phantom: Vec<&String> = classified.difference(&actual_tables).collect();

    assert!(
        unclassified.is_empty(),
        "Schema has tables not classified for reset_all_data — add each to \
         CONTENT_TABLES (clear on reset), RUNTIME_ONLY_TABLES (local-only \
         identity preserved), or SYNC_INFRASTRUCTURE_PRESERVED (sync \
         outbox / tombstones preserved across reset): {unclassified:?}"
    );
    assert!(
        phantom.is_empty(),
        "CONTENT_TABLES / RUNTIME_ONLY_TABLES / SYNC_INFRASTRUCTURE_PRESERVED \
         reference tables that are not in the live schema — typo or stale \
         entry: {phantom:?}"
    );

    let content_set: HashSet<&&str> = CONTENT_TABLES.iter().collect();
    assert_eq!(
        content_set.len(),
        CONTENT_TABLES.len(),
        "CONTENT_TABLES must not list the same table twice"
    );

    // The three classification lists must be pairwise disjoint —
    // an "rm + preserve + preserve" classification is meaningless
    // and would mask real drift.
    let preserved_set: HashSet<&&str> = SYNC_INFRASTRUCTURE_PRESERVED.iter().collect();
    let runtime_set: HashSet<&&str> = RUNTIME_ONLY_TABLES.iter().collect();
    for table in CONTENT_TABLES {
        assert!(
            !preserved_set.contains(table),
            "{table} appears in both CONTENT_TABLES and SYNC_INFRASTRUCTURE_PRESERVED"
        );
        assert!(
            !runtime_set.contains(table),
            "{table} appears in both CONTENT_TABLES and RUNTIME_ONLY_TABLES"
        );
    }
    for table in SYNC_INFRASTRUCTURE_PRESERVED {
        assert!(
            !runtime_set.contains(table),
            "{table} appears in both SYNC_INFRASTRUCTURE_PRESERVED and RUNTIME_ONLY_TABLES"
        );
    }
}

/// drift guard for the per-list table-to-list
/// correctness invariant. The schema-coverage test above only
/// checks that every table appears in *some* list. This guard
/// adds a stricter check: every table that lands in
/// `SYNCABLE_AGGREGATE_TABLES` must have a corresponding entry
/// in `naming::ALL_SYNCABLE_TYPES` with the matching entity_type
/// — and conversely, every aggregate-shaped entity type in
/// `ALL_SYNCABLE_TYPES` (excluding the independent-child types
/// owned by the second-pass walk) must be referenced here.
/// Without this guard, a future schema addition like
/// `daily_review_summaries` could land in `CONTENT_TABLES`
/// (passing the schema-coverage test) but be silently absent
/// from `SYNCABLE_AGGREGATE_TABLES`, replicating the original
/// #2944-H4 bug for the new entity.
#[test]
fn syncable_aggregate_tables_match_naming_ground_truth() {
    use lorvex_domain::naming;

    // Every entity_type referenced by SYNCABLE_AGGREGATE_TABLES
    // must be in ALL_SYNCABLE_TYPES — otherwise the dispatcher
    // can't apply the tombstones we're emitting on peers.
    for (table, _, entity_type) in SYNCABLE_AGGREGATE_TABLES {
        assert!(
            naming::ALL_SYNCABLE_TYPES.contains(entity_type),
            "SYNCABLE_AGGREGATE_TABLES references {entity_type} \
             (table {table}) but it is not in naming::ALL_SYNCABLE_TYPES \
             — peers would refuse the tombstone envelope"
        );
    }

    // The aggregate-root subset of ALL_SYNCABLE_TYPES that we
    // expect to walk on reset. Edges (task_tag, task_dependency,
    // task_calendar_event_link, habit_completion) cascade-tombstone
    // from their parent so they never need a direct entry here.
    // Independent children (task_reminder, task_checklist_item,
    // habit_reminder_policy, memory_revision) are handled by the SECOND pass via
    // SYNCABLE_INDEPENDENT_CHILD_TABLES.
    // preference and ai_changelog are handled by the
    // reset-special pass because their delete payload/apply semantics
    // differ from aggregate roots.
    let edge_types = &[
        naming::EDGE_TASK_TAG,
        naming::EDGE_TASK_DEPENDENCY,
        naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        naming::EDGE_HABIT_COMPLETION,
        naming::EDGE_TASK_PROVIDER_EVENT_LINK,
    ];
    let independent_child_types = &[
        naming::ENTITY_TASK_REMINDER,
        naming::ENTITY_TASK_CHECKLIST_ITEM,
        naming::ENTITY_HABIT_REMINDER_POLICY,
        naming::ENTITY_MEMORY_REVISION,
    ];
    let exempt = &[naming::ENTITY_AI_CHANGELOG, naming::ENTITY_PREFERENCE];
    let aggregate_root_types: HashSet<&str> = SYNCABLE_AGGREGATE_TABLES
        .iter()
        .map(|(_, _, et)| *et)
        .collect();
    let independent_child_types_in_second_pass: HashSet<&str> = SYNCABLE_INDEPENDENT_CHILD_TABLES
        .iter()
        .map(|(_, _, _, et, _)| *et)
        .collect();
    for entity_type in naming::ALL_SYNCABLE_TYPES {
        if edge_types.contains(entity_type)
            || exempt.contains(entity_type)
            || independent_child_types.contains(entity_type)
        {
            continue;
        }
        assert!(
            aggregate_root_types.contains(entity_type),
            "{entity_type} is in naming::ALL_SYNCABLE_TYPES but not in \
             SYNCABLE_AGGREGATE_TABLES — reset_all_data will not emit a \
             tombstone for it, leaving peers' rows alive after a wipe. \
             Add it to the SYNCABLE_AGGREGATE_TABLES tuple list (table, \
             pk_column, entity_type)."
        );
    }
    for entity_type in exempt {
        assert!(
            SYNCABLE_RESET_SPECIAL_ENTITY_TYPES.contains(entity_type),
            "{entity_type} is exempt from SYNCABLE_AGGREGATE_TABLES but \
             missing from SYNCABLE_RESET_SPECIAL_ENTITY_TYPES"
        );
    }
    // The independent-child second pass must cover every entity
    // type in our `independent_child_types` checklist above —
    // catches the case where a new sync child is added without
    // wiring a second-pass walk.
    for entity_type in independent_child_types {
        assert!(
            independent_child_types_in_second_pass.contains(entity_type),
            "{entity_type} is documented as an independent-child \
             sync entity but is missing from \
             SYNCABLE_INDEPENDENT_CHILD_TABLES — the second-pass \
             walk will not emit per-row tombstones for it"
        );
    }
}

#[test]
fn finalize_reset_transaction_surfaces_commit_failures() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");

    let error = finalize_reset_transaction::<i32>(&conn, &Ok(1))
        .expect_err("commit without active transaction should fail");
    assert!(
        error.contains("commit") || error.contains("COMMIT") || error.contains("transaction"),
        "unexpected error: {error}"
    );
}

/// `reset_all_data_db` MUST emit an
/// `OP_DELETE` envelope (+ matching tombstone) per syncable
/// aggregate-root row before the bulk wipe. Without these
/// envelopes peers that hadn't received the wipe re-pushed state
/// on the next sync cycle, resurrecting the data the user thought
/// they had erased.
#[test]
fn reset_all_data_db_emits_per_entity_delete_envelopes() {
    use lorvex_domain::naming::{
        ENTITY_CALENDAR_EVENT, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_LIST, ENTITY_TASK, OP_DELETE,
    };

    let conn = crate::test_support::test_conn();
    const LIST_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000004321";
    const TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000004322";
    const EVENT_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000004323";
    const SUBSCRIPTION_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000004319";

    // Seed one row in each of the three core aggregate-root
    // tables called out by the audit: tasks, lists, calendar
    // events. (`reset_preferences` is a separate command and
    // already covered by its own enqueue path.)
    let version = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, 'Reset Probe', ?2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        rusqlite::params![LIST_ID, version],
    )
    .expect("seed list");
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_ID)
        .title("Reset Probe")
        .version(version)
        .created_at("2026-01-01T08:00:00Z")
        .list_id(Some(LIST_ID))
        .insert(&conn);
    conn.execute(
        "INSERT INTO calendar_events
             (id, title, start_date, start_time, end_date, end_time, all_day,
              version, created_at, updated_at)
         VALUES
             (?1, 'Reset Probe', '2026-01-01', '09:00', '2026-01-01', '10:00',
              0, ?2, '2026-01-01T08:00:00Z', '2026-01-01T08:00:00Z')",
        rusqlite::params![EVENT_ID, version],
    )
    .expect("seed calendar event");
    conn.execute(
        "INSERT INTO calendar_subscriptions
            (id, name, url, color, enabled, version, created_at, updated_at)
         VALUES
            (?1, 'Reset ICS',
             'https://example.com/reset.ics', '#abcdef', 1, ?2,
             '2026-01-01T08:00:00Z', '2026-01-01T08:00:00Z')",
        rusqlite::params![SUBSCRIPTION_ID, version],
    )
    .expect("seed calendar subscription");

    let (cleared, entities_tombstoned) =
        reset_all_data_db(&conn).expect("reset_all_data_db should succeed");

    assert!(
        cleared > 0,
        "expected bulk wipe to clear at least one table"
    );
    // Four aggregate-root rows seeded above should each produce a tombstone.
    assert!(
        entities_tombstoned >= 3,
        "expected at least 3 tombstones, got {entities_tombstoned}"
    );

    // The seeded source rows are gone.
    for (table, id) in [
        ("tasks", TASK_ID),
        ("lists", LIST_ID),
        ("calendar_events", EVENT_ID),
        ("calendar_subscriptions", SUBSCRIPTION_ID),
    ] {
        let count: i64 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE id = ?1"),
                [id],
                |row| row.get(0),
            )
            .expect("count source row");
        assert_eq!(count, 0, "{table} row {id} should have been wiped");
    }

    // Each seeded aggregate root has both an outbox envelope AND a
    // tombstone — `enqueue_payload_delete`'s shared core writes
    // them in the same transaction.
    for (entity_type, entity_id) in [
        (ENTITY_TASK, TASK_ID),
        (ENTITY_LIST, LIST_ID),
        (ENTITY_CALENDAR_EVENT, EVENT_ID),
        (ENTITY_CALENDAR_SUBSCRIPTION, SUBSCRIPTION_ID),
    ] {
        let outbox_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox \
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![entity_type, entity_id, OP_DELETE],
                |row| row.get(0),
            )
            .expect("count outbox envelope");
        assert_eq!(
            outbox_count, 1,
            "missing OP_DELETE envelope for {entity_type}/{entity_id}"
        );

        let tombstone_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_tombstones \
                 WHERE entity_type = ?1 AND entity_id = ?2",
                rusqlite::params![entity_type, entity_id],
                |row| row.get(0),
            )
            .expect("count tombstone");
        assert_eq!(
            tombstone_count, 1,
            "missing tombstone for {entity_type}/{entity_id}"
        );
    }

    let subscription_payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_CALENDAR_SUBSCRIPTION, SUBSCRIPTION_ID, OP_DELETE],
            |row| row.get(0),
        )
        .expect("load calendar subscription delete payload");
    let subscription_payload: serde_json::Value =
        serde_json::from_str(&subscription_payload_raw).expect("parse subscription payload");
    assert_eq!(subscription_payload["id"], SUBSCRIPTION_ID);
    assert!(subscription_payload.get("name").is_none());
    assert!(subscription_payload.get("next_retry_at").is_none());
    assert!(subscription_payload.get("consecutive_failures").is_none());
    assert!(subscription_payload.get("last_retry_after_hint").is_none());

    // The just-emitted envelopes survived the bulk wipe.
    let total_outbox: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox");
    assert!(
        total_outbox >= 3,
        "sync_outbox must persist post-reset, got {total_outbox} rows"
    );

    let total_tombstones: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_tombstones", [], |row| row.get(0))
        .expect("count tombstones");
    assert!(
        total_tombstones >= 3,
        "sync_tombstones must persist post-reset, got {total_tombstones} rows"
    );
}

#[test]
fn finalize_reset_transaction_surfaces_rollback_failures() {
    let conn = rusqlite::Connection::open_in_memory().expect("open db");

    let error = finalize_reset_transaction::<()>(&conn, &Err("boom".to_string()))
        .expect_err("rollback without active transaction should fail");
    assert!(
        error.contains("boom"),
        "original reset failure should be preserved: {error}"
    );
    assert!(
        error.contains("rollback") || error.contains("ROLLBACK") || error.contains("transaction"),
        "unexpected error: {error}"
    );
}
