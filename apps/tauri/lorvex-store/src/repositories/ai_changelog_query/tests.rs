use std::num::NonZeroU32;

use rusqlite::{params, Connection};

use super::{list_ai_changelog, AiChangelogQuery};
use crate::open_db_in_memory;

#[derive(Clone, Copy)]
struct TestEntry<'a> {
    id: &'a str,
    timestamp: &'a str,
    operation: &'a str,
    entity_type: &'a str,
    entity_id: Option<&'a str>,
    entity_ids: Option<&'a str>,
    initiated_by: &'a str,
}

fn insert_entry(conn: &Connection, entry: TestEntry<'_>) {
    conn.execute(
        "INSERT INTO ai_changelog (
            id, timestamp, operation, entity_type, entity_id,
            summary, initiated_by, mcp_tool
         ) VALUES (?1, ?2, ?3, ?4, ?5, 'summary', ?6, 'test_tool')",
        params![
            entry.id,
            entry.timestamp,
            entry.operation,
            entry.entity_type,
            entry.entity_id,
            entry.initiated_by
        ],
    )
    .expect("insert changelog entry");
    // Populate the `ai_changelog_entities` registry from the
    // wire-form JSON the test fixture supplies. The runtime writer
    // (`write_changelog_row`) routes through `replace_changelog_entities`;
    // this manual fixture mirrors that contract.
    let ids = crate::changelog::entities::parse_entity_ids_json(entry.entity_ids)
        .expect("entity_ids JSON parse");
    crate::changelog::replace_changelog_entities(conn, entry.id, &ids)
        .expect("populate ai_changelog_entities");
}

/// Convenience for the AI-attributed `update` shape used by most tests.
fn ai_update<'a>(
    id: &'a str,
    timestamp: &'a str,
    entity_type: &'a str,
    entity_id: &'a str,
    operation: &'a str,
) -> TestEntry<'a> {
    TestEntry {
        id,
        timestamp,
        operation,
        entity_type,
        entity_id: Some(entity_id),
        entity_ids: None,
        initiated_by: "ai",
    }
}

fn limit(n: u32) -> NonZeroU32 {
    NonZeroU32::new(n).expect("non-zero")
}

#[test]
fn list_ai_changelog_excludes_manual_rows_and_orders_desc() {
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update(
            "older",
            "2026-01-01T00:00:00.000000Z",
            "task",
            "task-1",
            "create",
        ),
    );
    insert_entry(
        &conn,
        ai_update(
            "newer",
            "2026-01-02T00:00:00.000000Z",
            "task",
            "task-1",
            "update",
        ),
    );
    insert_entry(
        &conn,
        TestEntry {
            id: "manual",
            timestamp: "2026-01-03T00:00:00.000000Z",
            operation: "update",
            entity_type: "task",
            entity_id: Some("task-1"),
            entity_ids: None,
            initiated_by: "manual",
        },
    );

    let entries = list_ai_changelog(&conn, &AiChangelogQuery::new(limit(10))).expect("list");
    assert_eq!(
        entries.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
        vec!["newer", "older"]
    );
}

#[test]
fn list_ai_changelog_filters_by_exact_entity_id_array_member() {
    // Entity-id filter must match exact array members, NOT a
    // substring. `task-1` should match `["task-1","task-2"]` but
    // NOT `["task-10"]` (which would happen if the filter used
    // `LIKE '%task-1%'` instead of JSON-array membership).
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        TestEntry {
            id: "match-array",
            timestamp: "2026-01-01T00:00:00.000000Z",
            operation: "batch_update",
            entity_type: "task",
            entity_id: None,
            entity_ids: Some(r#"["task-1","task-2"]"#),
            initiated_by: "ai",
        },
    );
    insert_entry(
        &conn,
        TestEntry {
            id: "no-substring-match",
            timestamp: "2026-01-02T00:00:00.000000Z",
            operation: "batch_update",
            entity_type: "task",
            entity_id: None,
            entity_ids: Some(r#"["task-10"]"#),
            initiated_by: "ai",
        },
    );

    let entries = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_entity_id("task-1"),
    )
    .expect("list");
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].id, "match-array");
}

#[test]
fn list_ai_changelog_filters_by_entity_type() {
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update("t1", "2026-01-01T00:00:00.000000Z", "task", "t-1", "create"),
    );
    insert_entry(
        &conn,
        ai_update("l1", "2026-01-02T00:00:00.000000Z", "list", "l-1", "create"),
    );
    insert_entry(
        &conn,
        ai_update("t2", "2026-01-03T00:00:00.000000Z", "task", "t-2", "create"),
    );

    let only_tasks = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_entity_type(lorvex_domain::naming::EntityKind::Task),
    )
    .expect("list");
    let ids: Vec<&str> = only_tasks.iter().map(|e| e.id.as_str()).collect();
    // DESC by timestamp, so t2 first.
    assert_eq!(ids, vec!["t2", "t1"]);
}

#[test]
fn list_ai_changelog_filters_by_operation() {
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update("c1", "2026-01-01T00:00:00.000000Z", "task", "t-1", "create"),
    );
    insert_entry(
        &conn,
        ai_update("u1", "2026-01-02T00:00:00.000000Z", "task", "t-1", "update"),
    );
    insert_entry(
        &conn,
        ai_update("u2", "2026-01-03T00:00:00.000000Z", "task", "t-2", "update"),
    );
    insert_entry(
        &conn,
        ai_update("d1", "2026-01-04T00:00:00.000000Z", "task", "t-2", "delete"),
    );

    let only_updates = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_operation("update"),
    )
    .expect("list");
    let ids: Vec<&str> = only_updates.iter().map(|e| e.id.as_str()).collect();
    assert_eq!(ids, vec!["u2", "u1"]);
}

#[test]
fn list_ai_changelog_since_filter_is_strictly_after() {
    // The `since` filter is `timestamp > ?` (strict, not `>=`). Pin
    // the boundary so a future refactor can't quietly flip it to
    // inclusive — polling consumers that pass "the last observed
    // timestamp" rely on `>` to avoid re-emitting the boundary row.
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update("a", "2026-01-01T00:00:00.000000Z", "task", "t-1", "create"),
    );
    insert_entry(
        &conn,
        ai_update("b", "2026-01-02T00:00:00.000000Z", "task", "t-1", "update"),
    );
    insert_entry(
        &conn,
        ai_update("c", "2026-01-03T00:00:00.000000Z", "task", "t-1", "update"),
    );

    let entries = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_since("2026-01-02T00:00:00.000000Z"),
    )
    .expect("list");
    let ids: Vec<&str> = entries.iter().map(|e| e.id.as_str()).collect();
    // Boundary row "b" excluded; only strictly-newer "c" returned.
    assert_eq!(ids, vec!["c"]);
}

#[test]
fn list_ai_changelog_combines_multiple_filters() {
    // entity_type=task AND operation=update AND since=2026-01-02
    // → only matching task-update rows on/after that date.
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update(
            "t-create-old",
            "2026-01-01T00:00:00.000000Z",
            "task",
            "t-1",
            "create",
        ),
    );
    insert_entry(
        &conn,
        ai_update(
            "t-update-new",
            "2026-01-03T00:00:00.000000Z",
            "task",
            "t-1",
            "update",
        ),
    );
    insert_entry(
        &conn,
        ai_update(
            "l-update-new",
            "2026-01-04T00:00:00.000000Z",
            "list",
            "l-1",
            "update",
        ),
    );
    insert_entry(
        &conn,
        ai_update(
            "t-update-old",
            "2026-01-01T12:00:00.000000Z",
            "task",
            "t-2",
            "update",
        ),
    );

    let entries = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10))
            .with_entity_type(lorvex_domain::naming::EntityKind::Task)
            .with_operation("update")
            .with_since("2026-01-02T00:00:00.000000Z"),
    )
    .expect("list");
    let ids: Vec<&str> = entries.iter().map(|e| e.id.as_str()).collect();
    assert_eq!(ids, vec!["t-update-new"]);
}

#[test]
fn list_ai_changelog_respects_limit() {
    let conn = open_db_in_memory().expect("open db");
    for i in 0..5 {
        insert_entry(
            &conn,
            ai_update(
                &format!("e-{i}"),
                &format!("2026-01-0{i}T00:00:00.000000Z", i = i + 1),
                "task",
                "t-1",
                "update",
            ),
        );
    }
    let entries = list_ai_changelog(&conn, &AiChangelogQuery::new(limit(2))).expect("list");
    assert_eq!(entries.len(), 2);
    // The two newest.
    let ids: Vec<&str> = entries.iter().map(|e| e.id.as_str()).collect();
    assert_eq!(ids, vec!["e-4", "e-3"]);
}

#[test]
fn list_ai_changelog_returns_empty_when_no_match() {
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update("t1", "2026-01-01T00:00:00.000000Z", "task", "t-1", "create"),
    );

    let entries = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_entity_id("nonexistent"),
    )
    .expect("list");
    assert!(entries.is_empty());
}

#[test]
fn list_ai_changelog_entity_id_matches_scalar_entity_id_field() {
    // The entity_id filter has TWO match paths: equality against the
    // scalar `entity_id` column AND membership-in-array against the
    // `entity_ids` JSON column. Pin both.
    let conn = open_db_in_memory().expect("open db");
    insert_entry(
        &conn,
        ai_update(
            "scalar-hit",
            "2026-01-01T00:00:00.000000Z",
            "task",
            "t-1",
            "create",
        ),
    );
    insert_entry(
        &conn,
        TestEntry {
            id: "array-hit",
            timestamp: "2026-01-02T00:00:00.000000Z",
            operation: "batch_update",
            entity_type: "task",
            entity_id: None,
            entity_ids: Some(r#"["t-1","t-2"]"#),
            initiated_by: "ai",
        },
    );
    insert_entry(
        &conn,
        TestEntry {
            id: "miss",
            timestamp: "2026-01-03T00:00:00.000000Z",
            operation: "batch_update",
            entity_type: "task",
            entity_id: None,
            entity_ids: Some(r#"["t-3"]"#),
            initiated_by: "ai",
        },
    );

    let entries = list_ai_changelog(
        &conn,
        &AiChangelogQuery::new(limit(10)).with_entity_id("t-1"),
    )
    .expect("list");
    let ids: Vec<&str> = entries.iter().map(|e| e.id.as_str()).collect();
    // DESC: array-hit (Jan 2) before scalar-hit (Jan 1).
    assert_eq!(ids, vec!["array-hit", "scalar-hit"]);
}
