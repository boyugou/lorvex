use super::*;

use crate::test_support::test_conn;
use rusqlite::params;

#[test]
fn normalize_schedule_block_entries_rejects_invalid_start_time() {
    let blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "25:61".to_string(),
        end_time: "10:00".to_string(),
        task_id: Some("task-1".to_string()),
        event_id: None,
        title: Some("Impossible block".to_string()),
    }];

    let error = normalize_schedule_block_entries(&blocks)
        .expect_err("invalid start_time should be rejected");

    match error {
        AppError::Validation(message) => assert!(message.contains("25:61")),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn materialize_schedule_blocks_persists_valid_hhmm_times() {
    let conn = test_conn();
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
         VALUES ('2026-03-29', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("insert focus schedule header");

    let blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "09:15".to_string(),
        end_time: "10:45".to_string(),
        task_id: Some("task-1".to_string()),
        event_id: None,
        title: Some("Deep work".to_string()),
    }];
    let entries = normalize_schedule_block_entries(&blocks).expect("normalize valid block");

    lorvex_store::focus_schedule_blocks::materialize_schedule_blocks(&conn, "2026-03-29", &entries)
        .expect("materialize valid blocks");

    let persisted: (i64, i64) = conn
        .query_row(
            "SELECT start_time, end_time FROM focus_schedule_blocks WHERE schedule_date = '2026-03-29'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read persisted block");
    assert_eq!(persisted, (555, 645));
}

#[test]
fn normalize_schedule_block_entries_rejects_non_positive_duration() {
    let blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "10:00".to_string(),
        end_time: "10:00".to_string(),
        task_id: Some("task-1".to_string()),
        event_id: None,
        title: Some("Zero length".to_string()),
    }];

    let error = normalize_schedule_block_entries(&blocks)
        .expect_err("zero-length block should be rejected");

    match error {
        AppError::Validation(message) => assert!(message.contains("10:00")),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn update_focus_schedule_blocks_with_conn_rolls_back_when_sync_enqueue_fails() {
    let conn = test_conn();
    let today = "2026-03-29";
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Task 1")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    // seed `current_focus` parent row so the
    // `materialize_focus_items_with_header_bump` path inside the
    // writer can re-stamp it. Pre-fix the test only seeded
    // `focus_schedule`, which was correct for the original writer
    // shape but became stale once the header bump was lifted onto
    // a sibling parent (see comment at the top of this writer).
    // Without this seed the writer surfaces `StaleVersion` on the
    // missing-row branch instead of the expected `database
    // error / no such table` from the dropped `sync_outbox`.
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed current_focus header");
    conn.execute(
        "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES (?1, 0, 'task', 540, 600, 'task-1')",
        params![today],
    )
    .expect("seed focus schedule block");
    conn.execute("DROP TABLE sync_outbox", [])
        .expect("drop sync_outbox to force enqueue failure");

    let error = update_focus_schedule_blocks_with_conn(
        &conn,
        today,
        vec![ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: Some("task-1".to_string()),
            event_id: None,
            title: Some("Retimed block".to_string()),
        }],
        "2026-03-29T09:00:00Z",
    )
    .expect_err("enqueue failure should roll back schedule mutation");

    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("no such table"),
        "unexpected error: {message}"
    );

    let persisted: (i64, i64) = conn
        .query_row(
            "SELECT start_time, end_time FROM focus_schedule_blocks WHERE schedule_date = ?1",
            params![today],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read rolled-back persisted block");
    assert_eq!(persisted, (540, 600));
}

#[test]
fn update_focus_schedule_blocks_with_conn_enqueues_current_focus_aggregate() {
    let conn = test_conn();
    let today = "2026-03-29";
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Task 1")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed current_focus header");

    update_focus_schedule_blocks_with_conn(
        &conn,
        today,
        vec![ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: Some("task-1".to_string()),
            event_id: None,
            title: Some("Focused task".to_string()),
        }],
        "2026-03-29T09:00:00Z",
    )
    .expect("focus schedule update should succeed");

    let current_focus_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'current_focus' AND entity_id = ?1
               AND operation = 'upsert'",
            params![today],
            |row| row.get(0),
        )
        .expect("count current_focus sync rows");
    assert_eq!(
        current_focus_rows, 1,
        "schedule edits that rebuild current_focus_items must sync the current_focus aggregate"
    );
}

#[test]
fn update_focus_schedule_blocks_with_conn_rolls_back_when_current_focus_enqueue_fails() {
    let conn = test_conn();
    let today = "2026-03-29";
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Task 1")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed current_focus header");
    conn.execute(
        "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES (?1, 0, 'task', 540, 600, 'task-1')",
        params![today],
    )
    .expect("seed focus schedule block");
    conn.execute(
        "CREATE TEMP TRIGGER fail_current_focus_outbox
         BEFORE INSERT ON sync_outbox
         WHEN NEW.entity_type = 'current_focus'
         BEGIN
           SELECT RAISE(FAIL, 'forced current focus sync failure');
         END",
        [],
    )
    .expect("install current_focus outbox failure trigger");

    let error = update_focus_schedule_blocks_with_conn(
        &conn,
        today,
        vec![ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: Some("task-1".to_string()),
            event_id: None,
            title: Some("Retimed block".to_string()),
        }],
        "2026-03-29T09:00:00Z",
    )
    .expect_err("current_focus aggregate enqueue failure should roll back schedule mutation");

    assert!(
        error
            .to_string()
            .contains("forced current focus sync failure"),
        "unexpected error: {error}"
    );
    let persisted: (i64, i64) = conn
        .query_row(
            "SELECT start_time, end_time FROM focus_schedule_blocks WHERE schedule_date = ?1",
            params![today],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read rolled-back persisted block");
    assert_eq!(persisted, (540, 600));
    let current_focus_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("count current_focus_items after rollback");
    assert_eq!(
        current_focus_items, 0,
        "rebuilt current_focus_items must roll back with the failed aggregate enqueue"
    );
}

#[test]
fn update_focus_schedule_blocks_with_conn_rejects_archived_task_without_partial_writes() {
    let conn = test_conn();
    let today = "2026-03-29";
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-archived")
        .title("Archived task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .archived_at(Some("2026-03-29T08:30:00.000000Z"))
        .insert(&conn);
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed current_focus header");

    let error = update_focus_schedule_blocks_with_conn(
        &conn,
        today,
        vec![ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: Some("task-archived".to_string()),
            event_id: None,
            title: Some("Archived task".to_string()),
        }],
        "2026-03-29T09:00:00Z",
    )
    .expect_err("archived task block should be rejected");

    assert!(
        error.to_string().contains("archived"),
        "unexpected error: {error}"
    );
    assert_invalid_block_update_left_no_writes(&conn, today);
}

#[test]
fn update_focus_schedule_blocks_with_conn_rejects_missing_task_without_partial_writes() {
    let conn = test_conn();
    let today = "2026-03-29";
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    conn.execute(
        "INSERT INTO current_focus (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed current_focus header");

    let error = update_focus_schedule_blocks_with_conn(
        &conn,
        today,
        vec![ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: Some("missing-task".to_string()),
            event_id: None,
            title: Some("Missing task".to_string()),
        }],
        "2026-03-29T09:00:00Z",
    )
    .expect_err("missing task block should be rejected");

    assert!(
        error.to_string().contains("missing") || error.to_string().contains("non-existent"),
        "unexpected error: {error}"
    );
    assert_invalid_block_update_left_no_writes(&conn, today);
}

fn assert_invalid_block_update_left_no_writes(conn: &rusqlite::Connection, today: &str) {
    let schedule_blocks: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("count focus schedule blocks");
    assert_eq!(schedule_blocks, 0);

    let current_focus_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("count current focus items");
    assert_eq!(current_focus_items, 0);

    let outbox_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count sync outbox");
    assert_eq!(outbox_rows, 0);

    let changelog_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog");
    assert_eq!(changelog_rows, 0);
}

#[test]
fn get_focus_schedule_with_conn_rejects_missing_task_reference() {
    let conn = test_conn();
    let today = "2026-03-29";
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        params![today],
    )
    .expect("seed focus schedule header");
    conn.execute(
        "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES (?1, 0, 'task', 540, 600, 'missing-task')",
        params![today],
    )
    .expect("seed dangling focus schedule block");

    let error = get_focus_schedule_with_conn(&conn, today)
        .expect_err("dangling focus schedule task should be rejected");

    match error {
        AppError::Internal(message) => assert!(message.contains("missing-task")),
        other => panic!("expected internal consistency error, got {other:?}"),
    }
}

#[test]
fn normalize_schedule_block_entries_rejects_task_blocks_without_task_id() {
    let blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "09:00".to_string(),
        end_time: "10:00".to_string(),
        task_id: None,
        event_id: None,
        title: Some("Missing task".to_string()),
    }];

    let error = normalize_schedule_block_entries(&blocks)
        .expect_err("task blocks without task_id should be rejected");

    match error {
        AppError::Validation(message) => assert!(message.contains("task_id")),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn normalize_schedule_block_entries_clears_non_task_task_ids() {
    let blocks = vec![ScheduleBlock {
        block_type: "buffer".to_string(),
        start_time: "09:00".to_string(),
        end_time: "09:15".to_string(),
        task_id: Some("stale-task-id".to_string()),
        event_id: None,
        title: None,
    }];

    let entries =
        normalize_schedule_block_entries(&blocks).expect("non-task blocks should normalize");

    assert_eq!(entries[0].task_id, None);
}

/// `update_focus_schedule_blocks` used
/// to forward every caller-supplied id straight into the writer
/// transaction. A malformed `task_id` or `event_id` would only
/// surface as an opaque sync-apply mismatch on a peer device. This
/// test asserts the IPC-boundary validator rejects malformed UUIDs
/// before any DB work runs.
#[test]
fn validate_schedule_block_ids_rejects_non_uuid_task_id() {
    let mut blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "09:00".to_string(),
        end_time: "10:00".to_string(),
        task_id: Some("not-a-uuid".to_string()),
        event_id: None,
        title: Some("Bad task id".to_string()),
    }];
    let error =
        validate_schedule_block_ids(&mut blocks).expect_err("malformed task_id must be rejected");
    assert!(error.contains("task_id"), "unexpected error: {error}");
}

#[test]
fn validate_schedule_block_ids_rejects_non_uuid_event_id() {
    let mut blocks = vec![ScheduleBlock {
        block_type: "event".to_string(),
        start_time: "09:00".to_string(),
        end_time: "10:00".to_string(),
        task_id: None,
        event_id: Some("not-a-uuid".to_string()),
        title: Some("Bad event id".to_string()),
    }];
    let error =
        validate_schedule_block_ids(&mut blocks).expect_err("malformed event_id must be rejected");
    assert!(error.contains("event_id"), "unexpected error: {error}");
}

#[test]
fn validate_schedule_block_ids_accepts_canonical_uuids() {
    let task_id = uuid::Uuid::now_v7().to_string();
    let event_id = uuid::Uuid::now_v7().to_string();
    let mut blocks = vec![
        ScheduleBlock {
            block_type: "task".to_string(),
            start_time: "09:00".to_string(),
            end_time: "10:00".to_string(),
            task_id: Some(format!("  {task_id}  ")),
            event_id: None,
            title: None,
        },
        ScheduleBlock {
            block_type: "event".to_string(),
            start_time: "10:00".to_string(),
            end_time: "11:00".to_string(),
            task_id: None,
            event_id: Some(event_id.clone()),
            title: None,
        },
    ];
    validate_schedule_block_ids(&mut blocks).expect("canonical UUIDs must validate");
    assert_eq!(blocks[0].task_id.as_deref(), Some(task_id.as_str()));
    assert_eq!(blocks[1].event_id.as_deref(), Some(event_id.as_str()));
}

/// Empty-string task_id on a `task` block must NOT be rejected by
/// the UUID validator (it is rejected later, with a dedicated
/// message, by `normalize_schedule_block_entries`). This test
/// pins that boundary so the validator and the materialize-path
/// rejection messages stay distinct.
#[test]
fn validate_schedule_block_ids_skips_empty_string_ids() {
    let mut blocks = vec![ScheduleBlock {
        block_type: "task".to_string(),
        start_time: "09:00".to_string(),
        end_time: "10:00".to_string(),
        task_id: Some(String::new()),
        event_id: Some(String::new()),
        title: None,
    }];
    validate_schedule_block_ids(&mut blocks)
        .expect("empty-string ids must skip the UUID validator");
    assert_eq!(blocks[0].task_id.as_deref(), Some(""));
    assert_eq!(blocks[0].event_id.as_deref(), Some(""));
}

/// `dismiss_focus_schedule_with_conn`
/// (a) ships a DELETE envelope whose payload is the canonical
/// pre-delete aggregate snapshot — header + blocks + version —
/// rather than the legacy `{date}` shape that defeated peer LWW,
/// and (b) returns the post-delete aggregate state (`None` after
/// a successful clear) instead of `()`.
#[test]
fn dismiss_focus_schedule_with_conn_ships_aggregate_snapshot_payload_and_returns_post_state() {
    let conn = test_conn();
    let today = "2026-04-26";
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
         VALUES (?1, 'UTC', '0000000000000_0000_seedfocusschedule',
                 '2026-04-26T08:00:00Z', '2026-04-26T08:00:00Z')",
        params![today],
    )
    .expect("seed focus_schedule header");

    let post_state =
        dismiss_focus_schedule_with_conn(&conn, today).expect("dismiss should succeed");
    assert!(
        post_state.is_none(),
        "post-delete focus schedule state must be None"
    );

    let payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox \
             WHERE entity_type = 'focus_schedule' AND entity_id = ?1 AND operation = 'delete' \
             ORDER BY id DESC LIMIT 1",
            params![today],
            |row| row.get(0),
        )
        .expect("load focus_schedule delete envelope payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload_raw).expect("parse focus_schedule payload");
    assert!(
        payload.get("version").and_then(|v| v.as_str()).is_some(),
        "focus_schedule delete payload must carry pre-delete `version` (got {payload})"
    );
    assert_eq!(
        payload.get("date").and_then(|v| v.as_str()),
        Some(today),
        "focus_schedule delete payload must carry the date key"
    );
}

// Pre-existing test `query_schedule_blocks_clears_non_task_task_ids`
// was deleted: the schema-level CHECK constraint on
// `focus_schedule_blocks` (\"buffer\" / \"event\" rows must have
// task_id IS NULL) now rejects the insertion at the SQL boundary, so
// a non-task block with a stale task_id is structurally impossible
// to land in the DB. The QUERY-layer defensive clearing the test
// pinned is therefore unreachable. The pre-write input validation is
// still pinned by `normalize_schedule_block_entries_clears_non_task_task_ids`
// above, which is the active layer where the clearing actually
// runs (on caller-supplied entries before they reach the SQL gate).
