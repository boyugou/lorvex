use super::*;
use crate::contract::{FocusScheduleBlockInput, SaveFocusScheduleArgs, ScheduleBlockType};
use crate::db::open_database_for_path;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};
use rusqlite::Connection;
use serde_json::Value;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

/// production routes every MCP write tool through
/// `Server::with_conn`, which wraps the closure in a `mcp_tool`
/// SAVEPOINT before invoking the handler so any error inside the
/// handler rolls back atomically. Tests in this file call
/// `save_focus_schedule` directly on a raw `Connection`, bypassing
/// that wrapper. Mirror the production transaction shape here so
/// the rollback regression tests still observe atomic rollback
/// semantics now that the handler no longer opens its own inner
/// savepoint.
fn save_focus_schedule_in_savepoint(
    conn: &Connection,
    args: SaveFocusScheduleArgs,
) -> Result<String, crate::error::McpError> {
    lorvex_store::with_savepoint_mapped(
        conn,
        "test_mcp_tool",
        crate::error::McpError::Internal,
        |conn| save_focus_schedule(conn, args),
    )
}

/// Seed an open task at a fixed timestamp via the canonical
/// [`lorvex_store::test_support::fixtures::TaskBuilder`]. Mirrors the
/// previous hand-rolled INSERT shape (`status=open`, baseline HLC,
/// `created_at == updated_at == now`).
fn seed_open_task(conn: &Connection, id: &str, title: &str, now: &str) {
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .created_at(now)
        .insert(conn);
}

fn seed_timezone_preference(conn: &Connection, timezone: &str) {
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', ?1, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
        [serde_json::to_string(timezone).expect("serialize timezone")],
    )
    .expect("insert timezone preference");
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_response_parses_blocks_array() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    // task blocks now validate against the tasks table
    // at the trust boundary, so seed a real task with a UUID id.
    let now = "2026-03-01T00:00:00Z";
    let task_id = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_id, "Task 1", now);

    let response = save_focus_schedule(
        &conn,
        crate::contract::SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: crate::contract::ScheduleBlockType::Task,
                    task_id: Some(task_id),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: crate::contract::ScheduleBlockType::Buffer,
                    task_id: None,
                    start_time: "09:30".to_string(),
                    end_time: "09:40".to_string(),
                },
            ],
            rationale: Some("Morning sprint".to_string()),
            idempotency_key: None,
        },
    )
    .expect("save focus schedule response");

    let payload: Value =
        serde_json::from_str(&response).expect("parse save focus schedule response");
    let blocks = payload
        .get("blocks")
        .and_then(Value::as_array)
        .expect("blocks array");
    assert_eq!(blocks.len(), 2);
    assert_eq!(
        blocks[0].get("block_type").and_then(Value::as_str),
        Some("task")
    );
    assert_eq!(
        blocks[1].get("block_type").and_then(Value::as_str),
        Some("buffer")
    );
    assert_eq!(
        payload.get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );
    assert!(blocks[1].get("task_id").is_some_and(Value::is_null));
    // Verify created_at is present in the saved payload
    assert!(payload.get("created_at").and_then(Value::as_str).is_some());

    // Verify blocks are stored in the sub-table, not the main table
    let block_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = ?1",
            [payload.get("date").and_then(Value::as_str).unwrap()],
            |row| row.get(0),
        )
        .expect("count blocks");
    assert_eq!(block_count, 2);
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_applies_task_blocks_to_current_focus() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    // trust-boundary validation requires UUID-shaped
    // task ids that resolve to real `tasks` rows.
    let task_a = uuid::Uuid::now_v7().to_string();
    let task_b = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_a, "Task 1", now);
    seed_open_task(&conn, &task_b, "Task 2", now);

    let save_response = save_focus_schedule(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_a.clone()),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Buffer,
                    task_id: None,
                    start_time: "09:30".to_string(),
                    end_time: "09:45".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_b.clone()),
                    start_time: "10:00".to_string(),
                    end_time: "10:30".to_string(),
                },
            ],
            rationale: Some("Focused morning".to_string()),
            idempotency_key: None,
        },
    )
    .expect("save focus schedule");
    let payload: Value = serde_json::from_str(&save_response).expect("parse save response");

    // Verify task_ids were applied to current_focus
    assert_eq!(
        payload.get("task_ids_applied"),
        Some(&serde_json::json!([task_a, task_b])),
    );

    // Verify current_focus_items were created
    let item_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count current_focus_items");
    assert_eq!(item_count, 2);
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_creates_dashboard_layout_with_schedule_when_missing() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let task_id = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_id, "Task 1", now);

    save_focus_schedule(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![FocusScheduleBlockInput {
                block_type: ScheduleBlockType::Task,
                task_id: Some(task_id),
                start_time: "09:00".to_string(),
                end_time: "09:30".to_string(),
            }],
            rationale: Some("Focused morning".to_string()),
            idempotency_key: None,
        },
    )
    .expect("save focus schedule");

    let layout_raw: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'dashboard_layout'",
            [],
            |row| row.get(0),
        )
        .expect("dashboard layout preference");
    let layout: Value = serde_json::from_str(&layout_raw).expect("parse dashboard layout");
    let sections = layout["sections"].as_array().expect("sections array");
    let focus_index = sections
        .iter()
        .position(|section| section.get("type").and_then(Value::as_str) == Some("focus"))
        .expect("focus section");
    let schedule_index = sections
        .iter()
        .position(|section| section.get("type").and_then(Value::as_str) == Some("schedule"))
        .expect("schedule section");
    assert_eq!(schedule_index, focus_index + 1);
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_rolls_back_when_dashboard_layout_write_fails() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let task_id = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_id, "Task 1", now);
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Insert {
            table_name: "preferences",
        } => Authorization::Deny,
        AuthAction::Update {
            table_name,
            column_name,
        } if table_name == "preferences" && column_name == "value" => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let error = save_focus_schedule_in_savepoint(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![FocusScheduleBlockInput {
                block_type: ScheduleBlockType::Task,
                task_id: Some(task_id),
                start_time: "09:00".to_string(),
                end_time: "09:30".to_string(),
            }],
            rationale: Some("Focused morning".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("dashboard layout write failure should surface")
    .to_string();
    assert!(
        error.contains("internal error")
            || error.contains("access to preferences")
            || error.contains("database error"),
        "unexpected error: {error}"
    );

    let schedule_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM focus_schedule", [], |row| row.get(0))
        .expect("count focus schedules");
    assert_eq!(schedule_count, 0, "focus schedule write should roll back");

    let current_focus_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM current_focus", [], |row| row.get(0))
        .expect("count current focus rows");
    assert_eq!(
        current_focus_count, 0,
        "current focus write should roll back"
    );
}

/// Regression test for #2751 + #2966-H3: save_focus_schedule validates
/// task blocks against the `tasks` table at the trust boundary. Pre
/// #2966-H3 the helper silently filtered phantom task ids via the
/// post-write `WHERE id IN (...)` filter; the assistant got a success
/// response that quietly dropped bogus blocks. Now a phantom id MUST
/// fail with a clean Validation error before any write happens, and
/// the happy path preserves block order over the surviving rows.
#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_validates_task_ids_via_single_in_query() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let task_ids: Vec<String> = (0..3).map(|_| uuid::Uuid::now_v7().to_string()).collect();
    for (i, id) in task_ids.iter().enumerate() {
        seed_open_task(&conn, id, &format!("Task {}", i + 1), now);
    }

    // Happy path: every task id exists. The applied list preserves
    // block order even when blocks reference tasks out of insertion
    // order.
    let response = save_focus_schedule(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_ids[2].clone()),
                    start_time: "08:00".to_string(),
                    end_time: "08:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_ids[0].clone()),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_ids[1].clone()),
                    start_time: "09:30".to_string(),
                    end_time: "10:00".to_string(),
                },
            ],
            rationale: None,
            idempotency_key: None,
        },
    )
    .expect("save focus schedule");

    let payload: Value = serde_json::from_str(&response).expect("parse save response");
    assert_eq!(
        payload.get("task_ids_applied"),
        Some(&serde_json::json!([task_ids[2], task_ids[0], task_ids[1]])),
        "applied list should preserve block order across surviving ids"
    );
}

/// Regression for #2966-H3: a phantom task_id in any task block must
/// fail validation BEFORE the schedule (or any current_focus state) is
/// written. The previous behavior silently dropped the phantom id.
#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_rejects_phantom_task_id_at_trust_boundary() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let real_task = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &real_task, "Real task", now);

    let phantom = uuid::Uuid::now_v7().to_string();
    let error = save_focus_schedule_in_savepoint(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(real_task),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(phantom),
                    start_time: "09:30".to_string(),
                    end_time: "10:00".to_string(),
                },
            ],
            rationale: None,
            idempotency_key: None,
        },
    )
    .expect_err("phantom task_id must fail validation");
    let message = error.to_string().to_lowercase();
    assert!(
        message.contains("blocks") || message.contains("non-existent task"),
        "expected blocks[].task_id validation error, got: {message}",
    );

    // No partial writes should leak through.
    let schedule_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM focus_schedule", [], |row| row.get(0))
        .expect("count schedules");
    assert_eq!(schedule_count, 0, "schedule must not be persisted");
    let item_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM current_focus_items", [], |row| {
            row.get(0)
        })
        .expect("count current focus items");
    assert_eq!(item_count, 0, "current_focus_items must not be touched");
}

/// `FocusScheduleBlockInput.task_id` is now
/// `Option<String>` so buffer blocks can legitimately omit the
/// field at the wire boundary instead of fabricating a placeholder
/// id ("buffer-1", "break-buffer", …) that the downstream
/// `materialize_blocks` helper would silently discard anyway.
/// Pin both the deserialize shape and the persisted-row outcome:
///   - JSON without `task_id` on a buffer block must round-trip.
///   - The persisted block stores `task_id = NULL` and the
///     reloaded payload exposes `task_id: null`.
///   - A task block that omits `task_id` (deserializes to None)
///     surfaces the canonical "task block missing task_id"
///     validation error rather than silently writing a phantom
///     row.
#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_buffer_block_accepts_omitted_task_id() {
    // Deserialize-side: omitting `task_id` on a buffer block must
    // not error.
    let payload = serde_json::json!({
        "blocks": [
            {
                "block_type": "task",
                "task_id": "task-1",
                "start_time": "09:00",
                "end_time": "09:30",
            },
            {
                "block_type": "buffer",
                "start_time": "09:30",
                "end_time": "09:45",
            }
        ]
    });
    let parsed: SaveFocusScheduleArgs =
        serde_json::from_value(payload).expect("buffer block without task_id must deserialize");
    assert_eq!(parsed.blocks.len(), 2);
    assert_eq!(parsed.blocks[0].task_id.as_deref(), Some("task-1"));
    assert!(
        parsed.blocks[1].task_id.is_none(),
        "buffer block must deserialize task_id as None"
    );

    // Persistence-side: a saved schedule with an Option::None
    // buffer block stores NULL and reads back as null.
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let task_id = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_id, "Real task", now);

    let response = save_focus_schedule(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(task_id),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Buffer,
                    task_id: None,
                    start_time: "09:30".to_string(),
                    end_time: "09:45".to_string(),
                },
            ],
            rationale: None,
            idempotency_key: None,
        },
    )
    .expect("save with None task_id on buffer block");
    let payload: Value = serde_json::from_str(&response).expect("parse save response");
    let blocks = payload
        .get("blocks")
        .and_then(Value::as_array)
        .expect("blocks array");
    assert_eq!(blocks.len(), 2);
    assert!(
        blocks[1].get("task_id").is_some_and(Value::is_null),
        "persisted buffer block must store task_id as null: {blocks:?}",
    );

    // Stored row also carries NULL — defense in depth against a
    // future regression where the helper writes the placeholder
    // string straight through.
    let stored: Option<Option<String>> = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = ?1 AND block_type = 'buffer'",
            ["2026-03-02"],
            |row| row.get::<_, Option<String>>(0).map(Some),
        )
        .expect("read buffer row");
    assert_eq!(
        stored,
        Some(None),
        "buffer block row must persist task_id as NULL"
    );
}

/// a TASK block that omits `task_id`
/// must fail validation cleanly. Pre-fix the type forced a
/// placeholder; post-fix `task_id: None` on a task block is
/// possible and must be rejected before any write touches the
/// DB.
#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_rejects_task_block_missing_task_id() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");

    let error = save_focus_schedule_in_savepoint(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![FocusScheduleBlockInput {
                block_type: ScheduleBlockType::Task,
                task_id: None,
                start_time: "09:00".to_string(),
                end_time: "09:30".to_string(),
            }],
            rationale: None,
            idempotency_key: None,
        },
    )
    .expect_err("task block without task_id must fail validation");
    let message = error.to_string().to_lowercase();
    assert!(
        message.contains("task_id") || message.contains("task block"),
        "expected task_id validation error, got: {message}",
    );

    let schedule_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM focus_schedule", [], |row| row.get(0))
        .expect("count schedules");
    assert_eq!(
        schedule_count, 0,
        "no schedule must persist on validation failure"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_surfaces_malformed_dashboard_layout() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let task_id = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &task_id, "Task 1", now);
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('dashboard_layout', '{bad json', '0000000000000_0000_0000000000000000', ?1)",
        [now],
    )
    .expect("insert malformed dashboard layout");

    let error = save_focus_schedule(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![FocusScheduleBlockInput {
                block_type: ScheduleBlockType::Task,
                task_id: Some(task_id),
                start_time: "09:00".to_string(),
                end_time: "09:30".to_string(),
            }],
            rationale: Some("Focused morning".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("malformed dashboard layout should surface")
    .to_string();

    assert!(
        error.contains("dashboard_layout") || error.contains("JSON") || error.contains("expected"),
        "unexpected error: {error}"
    );
}

/// `save_focus_schedule` validates task blocks via
/// `validate_task_ids_active`, so an archived (trashed) task pinned
/// into a time block is rejected at the trust boundary just like a
/// phantom id. The focus schedule is a forward-looking plan; every
/// task read path filters `archived_at IS NULL`, so persisting an
/// archived id would render as a ghost block the assistant cannot
/// recover. Mirrors the gate already in place at
/// `set_current_focus` / `add_to_current_focus` (#2888).
#[test]
#[serial_test::serial(hlc)]
fn save_focus_schedule_rejects_archived_task_id_at_trust_boundary() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let now = "2026-03-01T00:00:00Z";
    let live = uuid::Uuid::now_v7().to_string();
    let trashed = uuid::Uuid::now_v7().to_string();
    seed_open_task(&conn, &live, "Live task", now);
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(&trashed)
        .title("Trashed task")
        .created_at(now)
        .archived_at(Some("2026-04-26T00:00:00.000Z"))
        .insert(&conn);

    let error = save_focus_schedule_in_savepoint(
        &conn,
        SaveFocusScheduleArgs {
            date: Some("2026-03-02".to_string()),
            blocks: vec![
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(live),
                    start_time: "09:00".to_string(),
                    end_time: "09:30".to_string(),
                },
                FocusScheduleBlockInput {
                    block_type: ScheduleBlockType::Task,
                    task_id: Some(trashed.clone()),
                    start_time: "09:30".to_string(),
                    end_time: "10:00".to_string(),
                },
            ],
            rationale: None,
            idempotency_key: None,
        },
    )
    .expect_err("archived task_id must be rejected on save_focus_schedule");
    let message = error.to_string();
    assert!(
        message.contains("archived"),
        "expected archived error wording: {message}",
    );
    assert!(
        message.contains(&trashed),
        "expected the trashed id in the error: {message}",
    );

    // No partial writes leaked through — the live block alongside the
    // rejected archived block must roll back together.
    let schedule_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM focus_schedule", [], |row| row.get(0))
        .expect("count schedules");
    assert_eq!(schedule_count, 0, "schedule must not persist");
    let item_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM current_focus_items", [], |row| {
            row.get(0)
        })
        .expect("count items");
    assert_eq!(item_count, 0, "current_focus_items must be untouched");
}
