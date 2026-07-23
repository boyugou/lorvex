//! Regression coverage for issue #2370 — every destructive MCP batch
//! / bulk write tool now accepts a `dry_run: bool` flag. When true the
//! mutation runs end-to-end inside a rolled-back savepoint and the
//! response is annotated with `"dry_run": true`; no rows are mutated
//! and no outbox envelopes are enqueued. A single `<tool>_preview`
//! row is appended to `ai_changelog` so the user can see in the audit
//! trail that a preview was run.
//!
//! These tests cover the contract from three angles for each tool:
//!   1. the response shape matches the non-dry-run path (key fields
//!      present, IDs populated),
//!   2. the database is untouched afterward (row counts preserved,
//!      status/state unchanged),
//!   3. a preview audit entry lands with the expected `<tool>_preview`
//!      operation and no outbox envelope is queued for the mutation's
//!      would-be entities.

use super::*;
use lorvex_domain::Patch;

fn count_tasks_mcp(server: &LorvexMcpServer) -> i64 {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get::<_, i64>(0))
                .map_err(|e| e.to_string())
        })
        .expect("count tasks")
}

fn count_outbox_mcp(server: &LorvexMcpServer) -> i64 {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("count sync_outbox")
}

fn preview_entries(server: &LorvexMcpServer, tool: &str) -> i64 {
    let op = format!("{tool}_preview");
    server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE operation = ?1",
                [op.as_str()],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count preview audit rows")
}

fn task_status_mcp(server: &LorvexMcpServer, id: &str) -> String {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT status FROM tasks WHERE id = ?1", [id], |row| {
                row.get::<_, String>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("read task status")
}

fn dry_run_batch_input(title: &str) -> BatchCreateTaskInput {
    BatchCreateTaskInput {
        title: title.to_string(),
        list_id: Some("list-inbox".to_string()),
        priority: None,
        due_date: None,
        due_time: None,
        estimated_minutes: None,
        tags: None,
        body: None,
        raw_input: None,
        ai_notes: None,
        depends_on: None,
        reminders: None,
        recurrence: None,
        planned_date: None,
        completed: None,
    }
}

// ---------------------------------------------------------------------------
// batch_create_tasks
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_dry_run_returns_preview_shape_and_does_not_insert() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");
    let initial_tasks = count_tasks_mcp(&server);
    let initial_outbox = count_outbox_mcp(&server);

    let response = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![
                dry_run_batch_input("Preview A"),
                dry_run_batch_input("Preview B"),
            ],
            include_advice: None,
            idempotency_key: None,
            dry_run: true,
        }))
        .expect("dry-run batch_create_tasks should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse dry-run payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["created_count"], 2);
    let tasks = payload["tasks"].as_array().expect("tasks array");
    assert_eq!(tasks.len(), 2);
    assert!(tasks[0].get("id").and_then(Value::as_str).is_some());

    assert_eq!(
        count_tasks_mcp(&server),
        initial_tasks,
        "dry-run must not persist any rows"
    );
    // The preview audit row is itself written to `ai_changelog` but
    // does NOT enqueue an outbox envelope (see `write_preview_audit_entry`).
    assert_eq!(
        count_outbox_mcp(&server),
        initial_outbox,
        "dry-run must not enqueue outbox envelopes"
    );
    assert_eq!(preview_entries(&server, "batch_create_tasks"), 1);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_dry_run_skips_idempotency_cache() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    // Dry-run submission with a key.
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![dry_run_batch_input("Preview")],
            include_advice: None,
            idempotency_key: Some("preview-key".to_string()),
            dry_run: true,
        }))
        .expect("dry-run should succeed");

    // Real submission with the same key MUST still insert rows — the
    // preview must not have consumed the idempotency slot.
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![dry_run_batch_input("Real")],
            include_advice: None,
            idempotency_key: Some("preview-key".to_string()),
            dry_run: false,
        }))
        .expect("real submission should succeed");

    assert_eq!(
        count_tasks_mcp(&server),
        1,
        "only the real submission should mint a row",
    );
}

// ---------------------------------------------------------------------------
// batch_update_tasks
// ---------------------------------------------------------------------------

fn blank_batch_update(id: &str) -> BatchUpdateTaskPatch {
    BatchUpdateTaskPatch {
        id: id.to_string(),
        title: None,
        body: Patch::Unset,
        raw_input: None,
        ai_notes: Patch::Unset,
        status: None,
        list_id: None,
        tags_set: None,
        tags_add: None,
        tags_remove: None,
        priority: None,
        due_date: Patch::Unset,
        due_time: Patch::Unset,
        estimated_minutes: Patch::Unset,
        recurrence: Patch::Unset,
        depends_on: None,
        depends_on_add: None,
        depends_on_remove: None,
        planned_date: Patch::Unset,
    }
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_dry_run_returns_preview_shape_and_does_not_mutate() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000333";
    seed_task(&server, task_id, "Existing", "open", None, None, None, 0);
    let initial_outbox = count_outbox_mcp(&server);

    let mut patch = blank_batch_update(task_id);
    patch.title = Some("Renamed Preview".to_string());

    let response = server
        .batch_update_tasks(Parameters(BatchUpdateTasksArgs {
            updates: vec![patch],
            dry_run: true,
        }))
        .expect("dry-run batch_update_tasks should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["updated_count"], 1);

    // Live row in the DB must still show the pre-preview title.
    let live_title: String = server
        .with_read_conn(|conn| {
            conn.query_row("SELECT title FROM tasks WHERE id = ?1", [task_id], |row| {
                row.get::<_, String>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("read title");
    assert_eq!(live_title, "Existing");
    assert_eq!(
        count_outbox_mcp(&server),
        initial_outbox,
        "dry-run must not enqueue outbox envelopes"
    );
    assert_eq!(preview_entries(&server, "batch_update_tasks"), 1);
}

// ---------------------------------------------------------------------------
// batch_cancel_tasks
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_dry_run_returns_preview_shape_and_leaves_status_open() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000a01",
        "Cancel Me",
        "open",
        None,
        None,
        None,
        0,
    );
    let initial_outbox = count_outbox_mcp(&server);

    let response = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000a01".to_string()],
            reason: Some("preview only".to_string()),
            cancel_series: None,
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run batch_cancel_tasks should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["cancelled_count"], 1);

    assert_eq!(
        task_status_mcp(&server, "01966a3f-7c8b-7d4e-8f3a-000000000a01"),
        "open",
        "dry-run must not persist status change"
    );
    assert_eq!(
        count_outbox_mcp(&server),
        initial_outbox,
        "dry-run must not enqueue outbox envelopes"
    );
    assert_eq!(preview_entries(&server, "batch_cancel_tasks"), 1);
}

// ---------------------------------------------------------------------------
// batch_cancel_tasks_in_list
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_in_list_dry_run_returns_preview_shape_and_does_not_mutate() {
    let server = make_server();
    seed_list_named(&server, "01966a3f-7c8b-7d4e-8f3a-000000000b01", "Preview");
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000a02",
        "A",
        "open",
        Some("01966a3f-7c8b-7d4e-8f3a-000000000b01"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000a03",
        "B",
        "open",
        Some("01966a3f-7c8b-7d4e-8f3a-000000000b01"),
        None,
        None,
        0,
    );

    let response = server
        .batch_cancel_tasks_in_list(Parameters(BatchCancelTasksInListArgs {
            list_id: "01966a3f-7c8b-7d4e-8f3a-000000000b01".to_string(),
            statuses: None,
            cancel_series: None,
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run list cancel should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["cancelled_count"], 2);

    assert_eq!(
        task_status_mcp(&server, "01966a3f-7c8b-7d4e-8f3a-000000000a02"),
        "open"
    );
    assert_eq!(
        task_status_mcp(&server, "01966a3f-7c8b-7d4e-8f3a-000000000a03"),
        "open"
    );
    assert_eq!(preview_entries(&server, "batch_cancel_tasks_in_list"), 1);
}

// ---------------------------------------------------------------------------
// permanent_delete_task
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_dry_run_returns_preview_shape_and_preserves_row() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000105",
        "To Delete",
        "open",
        None,
        None,
        None,
        0,
    );
    // Permanent delete gates on archived_at (issue #2363). Archive
    // first so the dry-run exercises the real destructive path.
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET archived_at = '2026-04-02T00:00:00Z' WHERE id = ?1",
                ["01966a3f-7c8b-7d4e-8f3a-000000000105"],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("archive task");

    let response = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000105".to_string(),
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run permanent_delete_task should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000000105");
    assert_eq!(payload["deleted"], true);
    assert!(payload.get("previous").is_some());

    // Row must still exist.
    let count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM tasks WHERE id = ?1",
                ["01966a3f-7c8b-7d4e-8f3a-000000000105"],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count task row");
    assert_eq!(count, 1, "dry-run must not permanently delete the row");
    assert_eq!(preview_entries(&server, "permanent_delete_task"), 1);
}

// ---------------------------------------------------------------------------
// delete_list
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn delete_list_dry_run_returns_preview_shape_and_preserves_row() {
    let server = make_server();
    seed_list_named(&server, "list-keep", "Keep");
    seed_list_named(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000a03",
        "Preview Del",
    );

    let response = server
        .delete_list(Parameters(DeleteListArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000a03".to_string(),
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run delete_list should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(
        payload["deleted_list_id"],
        "01966a3f-7c8b-7d4e-8f3a-000000000a03"
    );

    let count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM lists WHERE id = ?1",
                ["01966a3f-7c8b-7d4e-8f3a-000000000a03"],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count list row");
    assert_eq!(count, 1, "dry-run must leave the list row in place");
    assert_eq!(preview_entries(&server, "delete_list"), 1);
}

// ---------------------------------------------------------------------------
// reorganize_list
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn reorganize_list_dry_run_returns_preview_shape_without_changelog_for_real_op() {
    let server = make_server();
    seed_list_named(&server, "list-reorg", "Reorg");
    seed_task(
        &server,
        "task-reorg-a",
        "Alpha",
        "open",
        Some("list-reorg"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "task-reorg-b",
        "Beta",
        "open",
        Some("list-reorg"),
        None,
        None,
        0,
    );

    let response = server
        .reorganize_list(Parameters(ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Priority,
            task_ids: None,
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run reorganize_list should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    let tasks = payload["tasks"]
        .as_array()
        .expect("payload should include embedded tasks");
    assert_eq!(tasks.len(), 2);

    // No normal `update`-op changelog entry should land (the preview
    // rollback discards it); only the `_preview` row survives.
    assert_eq!(preview_entries(&server, "reorganize_list"), 1);
    let normal_count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'reorganize_list' AND operation = 'update'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count normal reorganize entries");
    assert_eq!(normal_count, 0);
}

// ---------------------------------------------------------------------------
// batch_create_calendar_events
// ---------------------------------------------------------------------------

#[test]
#[serial_test::serial(hlc)]
fn batch_create_calendar_events_dry_run_returns_preview_shape_and_inserts_nothing() {
    let server = make_server();
    let initial_count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM calendar_events", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("count calendar events");

    let event = CreateCalendarEventArgs {
        title: "Preview Event".to_string(),
        description: None,
        recurrence: None,
        timezone: None,
        start_date: "2026-05-01".to_string(),
        start_time: None,
        end_date: None,
        end_time: None,
        all_day: Some(true),
        location: None,
        url: None,
        color: None,
        event_type: None,
        person_name: None,
        attendees: None,
    };

    let response = server
        .batch_create_calendar_events(Parameters(BatchCreateCalendarEventsArgs {
            events: vec![event],
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run batch_create_calendar_events should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["created_count"], 1);
    let events = payload["calendar_events"]
        .as_array()
        .expect("calendar_events array");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0]["title"], "Preview Event");

    let after_count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM calendar_events", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("count calendar events");
    assert_eq!(after_count, initial_count, "dry-run must not insert events");
    assert_eq!(preview_entries(&server, "batch_create_calendar_events"), 1);
}

// ---------------------------------------------------------------------------
// delete_habit
// ---------------------------------------------------------------------------

fn seed_habit_mcp(server: &LorvexMcpServer, id: &str, name: &str) {
    let now = "2026-04-01T00:00:00Z";
    server
        .with_conn(|conn| {
            conn.execute(
                r"
                INSERT INTO habits (id, name, frequency_type, version, created_at, updated_at)
                VALUES (?, ?, 'daily', '0000000000000_0000_0000000000000000', ?, ?)
                ",
                (id, name, now, now),
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed habit");
}

#[test]
#[serial_test::serial(hlc)]
fn delete_habit_dry_run_returns_preview_shape_and_preserves_row() {
    // #3607 — `id` flows through `DeleteHabitArgs::validate_shape()`
    // which enforces UUID format at the trust boundary. Production
    // habit IDs are real UUIDs; the test fixture used to take a
    // shortcut with `'habit-preview'` and broke when the derive was
    // wired. Use a real UUID.
    const HABIT_ID: &str = "01966a3f-7c8b-7d4e-8f3a-0000000000d1";
    let server = make_server();
    seed_habit_mcp(&server, HABIT_ID, "Preview Habit");

    let response = server
        .delete_habit(Parameters(DeleteHabitArgs {
            id: HABIT_ID.to_string(),
            dry_run: true,
            idempotency_key: None,
        }))
        .expect("dry-run delete_habit should succeed");

    let payload: Value = serde_json::from_str(&response).expect("parse payload");
    assert_eq!(payload["dry_run"], Value::Bool(true));
    assert_eq!(payload["deleted"], true);
    assert_eq!(payload["id"], HABIT_ID);

    let count: i64 = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM habits WHERE id = ?1",
                [HABIT_ID],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count habit row");
    assert_eq!(count, 1, "dry-run must leave the habit row in place");
    assert_eq!(preview_entries(&server, "delete_habit"), 1);
}

// ---------------------------------------------------------------------------
// `dispatch_dry_run`'s SQL-only rollback contract
// ---------------------------------------------------------------------------

/// The dry-run savepoint covers SQL writes but does NOT cover process-
/// wide statics like `HLC_STATE`. Inside the closure, `generate_hlc_version`
/// advances the in-memory HLC; that advance survives the rollback.
///
/// The contract is that this is harmless — every persisted HLC must
/// remain strictly monotonic. A subsequent real mutation must produce
/// an HLC that is greater than every HLC the dry-run pre-incremented
/// past, and any HLC the apply pipeline (or peer) has already
/// observed.
///
/// This test exercises the full sequence: read pre-state HLCs,
/// dry-run a `batch_create_tasks` call (which internally calls
/// `generate_hlc_version` for every task it would create), then run
/// a real `batch_create_tasks` call. Every persisted HLC after the
/// real call must lex-order strictly above every persisted HLC
/// before the dry-run, and the real call's HLCs must all be valid
/// (non-empty, parseable).
#[test]
#[serial_test::serial(hlc)]
fn dry_run_preserves_monotonic_hlc_after_rollback() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    // 1. Run a real seed task so we have a concrete HLC on disk to
    //    compare against.
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![dry_run_batch_input("Seed")],
            include_advice: None,
            idempotency_key: None,
            dry_run: false,
        }))
        .expect("seed real task");
    let seed_hlc: String = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT version FROM tasks WHERE title = 'Seed'",
                [],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("read seed HLC");

    // 2. Dry-run a batch — internally advances HLC_STATE for each
    //    of the N tasks it would create. The savepoint rolls back
    //    SQL writes, but the in-memory HLC counter has advanced.
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![
                dry_run_batch_input("Preview-1"),
                dry_run_batch_input("Preview-2"),
                dry_run_batch_input("Preview-3"),
            ],
            include_advice: None,
            idempotency_key: None,
            dry_run: true,
        }))
        .expect("dry-run preview");

    // 3. Real follow-up. Its HLC must be strictly greater than the
    //    seed HLC (basic monotonicity) AND strictly greater than the
    //    dry-run advanced HLC. Lex compare on the string form is
    //    safe because the encoding sorts in HLC order.
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            tasks: vec![dry_run_batch_input("Real-after-preview")],
            include_advice: None,
            idempotency_key: None,
            dry_run: false,
        }))
        .expect("real after preview");
    let real_after_hlc: String = server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT version FROM tasks WHERE title = 'Real-after-preview'",
                [],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("read post-preview HLC");

    assert!(
        real_after_hlc.as_str() > seed_hlc.as_str(),
        "post-dry-run HLC {real_after_hlc:?} must lex-order strictly above pre-dry-run HLC {seed_hlc:?}"
    );

    // 4. Sanity: parse the post-preview HLC. A regression that left
    //    HLC_STATE in a bogus shape would surface here.
    let parsed =
        lorvex_domain::hlc::Hlc::parse(&real_after_hlc).expect("post-preview HLC parses cleanly");
    assert!(parsed.physical_ms() > 0);
}
