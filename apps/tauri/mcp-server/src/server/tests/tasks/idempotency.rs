//! Regression coverage for issue #2238: `create_task` /
//! `batch_create_tasks` now short-circuit on a repeated
//! `idempotency_key` instead of silently minting duplicate rows when a
//! client retries after a transient transport failure.

use super::*;

fn base_create_args(title: &str, key: Option<&str>) -> CreateTaskArgs {
    CreateTaskArgs {
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
        include_advice: None,
        idempotency_key: key.map(str::to_string),
    }
}

fn count_tasks(server: &LorvexMcpServer) -> i64 {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get::<_, i64>(0))
                .map_err(|e| e.to_string())
        })
        .expect("count tasks")
}

fn base_batch_input(title: &str) -> BatchCreateTaskInput {
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

fn count_changelog_for_tool(server: &LorvexMcpServer, tool: &str) -> i64 {
    server
        .with_read_conn(|conn| {
            conn.query_row(
                "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = ?1",
                [tool],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())
        })
        .expect("count changelog rows")
}

fn count_sync_outbox(server: &LorvexMcpServer) -> i64 {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| e.to_string())
        })
        .expect("count sync_outbox rows")
}

fn archive_task_for_idempotency_test(server: &LorvexMcpServer, id: &str) {
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET archived_at = '2026-04-02T00:00:00Z' WHERE id = ?1",
                [id],
            )
            .map_err(|e| e.to_string())?;
            Ok(())
        })
        .expect("archive task for idempotency test");
}

fn task_exists_for_idempotency_test(server: &LorvexMcpServer, id: &str) -> bool {
    server
        .with_read_conn(|conn| {
            conn.query_row("SELECT COUNT(*) FROM tasks WHERE id = ?1", [id], |row| {
                row.get::<_, i64>(0)
            })
            .map(|count| count > 0)
            .map_err(|e| e.to_string())
        })
        .expect("count task by id")
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_without_idempotency_key_creates_fresh_every_call() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    server
        .create_task(Parameters(base_create_args("One", None)))
        .expect("first create");
    server
        .create_task(Parameters(base_create_args("Two", None)))
        .expect("second create");

    assert_eq!(
        count_tasks(&server),
        2,
        "omitting the key must produce two distinct rows"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_with_idempotency_key_returns_cached_on_retry() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    // the retry must use bytewise-identical args.
    // Pre-fix this test exploited the lack of a payload checksum by
    // sending different titles under the same key and asserting the
    // cache replayed the first response — that scenario is now
    // classified as cache poisoning and rejected. The collision
    // path is exercised by
    // `create_task_idempotency_rejects_payload_drift_under_same_key`.
    let first = server
        .create_task(Parameters(base_create_args(
            "Retry-safe task",
            Some("retry-1"),
        )))
        .expect("first create");
    let second = server
        .create_task(Parameters(base_create_args(
            "Retry-safe task",
            Some("retry-1"),
        )))
        .expect("retry should short-circuit");

    assert_eq!(
        first, second,
        "the retry must replay the original response payload byte-for-byte"
    );
    assert_eq!(
        count_tasks(&server),
        1,
        "the retry must not insert a second task"
    );
}

/// payload-checksum gate at the create_task entry
/// point. See sibling batch test for rationale.
#[test]
#[serial_test::serial(hlc)]
fn create_task_idempotency_rejects_payload_drift_under_same_key() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    server
        .create_task(Parameters(base_create_args(
            "Retry-safe task",
            Some("collision-create"),
        )))
        .expect("first create");

    let err = server
        .create_task(Parameters(base_create_args(
            "Different title under the same key",
            Some("collision-create"),
        )))
        .expect_err("checksum mismatch must be rejected");
    assert!(
        err.contains("idempotency_key 'collision-create'"),
        "diagnostic should name the colliding key, got: {err}"
    );
    assert!(
        err.contains("different request payload"),
        "diagnostic should explain the collision, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_with_different_idempotency_keys_creates_distinct_tasks() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let first = server
        .create_task(Parameters(base_create_args("Alpha", Some("key-alpha"))))
        .expect("alpha create");
    let second = server
        .create_task(Parameters(base_create_args("Beta", Some("key-beta"))))
        .expect("beta create");

    assert_ne!(first, second, "distinct keys must produce distinct tasks");
    assert_eq!(
        count_tasks(&server),
        2,
        "distinct keys must each insert a row"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn create_task_idempotency_respects_expiry() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let first = server
        .create_task(Parameters(base_create_args("Ephemeral", Some("expiring"))))
        .expect("first create");
    assert_eq!(count_tasks(&server), 1);

    // Backdate the stored row so `lookup` treats it as expired.
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE mcp_idempotency SET expires_at = ?1 WHERE key = ?2",
                rusqlite::params!["2000-01-01T00:00:00.000Z", "expiring"],
            )
            .map_err(|e| e.to_string())?;
            Ok(())
        })
        .expect("backdate expiry");

    let second = server
        .create_task(Parameters(base_create_args(
            "Ephemeral (post-expiry)",
            Some("expiring"),
        )))
        .expect("second create after expiry");

    assert_ne!(
        first, second,
        "once the cache entry has expired the server must create a fresh task"
    );
    assert_eq!(
        count_tasks(&server),
        2,
        "expired entries must not block a fresh insert"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_without_idempotency_key_creates_fresh_every_call() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            tasks: vec![base_batch_input("Alpha"), base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("first batch create");
    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: None,
            tasks: vec![base_batch_input("Alpha"), base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("second batch create");

    assert_eq!(
        count_tasks(&server),
        4,
        "omitting the key must let both batches insert fresh rows"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_with_idempotency_key_returns_cached_on_retry() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let first = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-retry".to_string()),
            tasks: vec![base_batch_input("Alpha"), base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("first batch create");

    // a bytewise-identical retry must replay the
    // cached payload. The previous shape of this test deliberately
    // mutated the args to assert "same key wins"; under the new
    // checksum gate that scenario is now classified as cache
    // poisoning and rejected — see
    // `batch_create_tasks_idempotency_rejects_payload_drift_under_same_key`
    // for that path.
    let second = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-retry".to_string()),
            tasks: vec![base_batch_input("Alpha"), base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("batch retry should short-circuit");

    assert_eq!(
        first, second,
        "the retry must replay the original response payload byte-for-byte"
    );
    assert_eq!(
        count_tasks(&server),
        2,
        "the retry must not insert additional tasks"
    );
}

/// if the same idempotency_key is reused for a
/// semantically different request, the server must reject the call
/// with a Validation error instead of silently replaying the prior
/// (now stale) response. This guards against cache poisoning when
/// the assistant accidentally reuses a token across two different
/// intents (e.g. after a list got deleted between retries).
#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_idempotency_rejects_payload_drift_under_same_key() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("collision-key".to_string()),
            tasks: vec![base_batch_input("Alpha")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("first batch create");

    let err = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("collision-key".to_string()),
            // Different payload — the current cache must NOT replay
            // the prior response under the same key.
            tasks: vec![base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect_err("checksum mismatch must be rejected");
    assert!(
        err.contains("idempotency_key 'collision-key'"),
        "diagnostic should name the colliding key, got: {err}"
    );
    assert!(
        err.contains("different request payload"),
        "diagnostic should explain the collision, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_with_different_idempotency_keys_creates_distinct_tasks() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let first = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-alpha".to_string()),
            tasks: vec![base_batch_input("Alpha")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("alpha batch");
    let second = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-beta".to_string()),
            tasks: vec![base_batch_input("Beta")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("beta batch");

    assert_ne!(first, second, "distinct keys must produce distinct batches");
    assert_eq!(
        count_tasks(&server),
        2,
        "distinct keys must each insert their rows"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_idempotency_respects_expiry() {
    let server = make_server();
    seed_list_named(&server, "list-inbox", "Inbox");

    let first = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-expiring".to_string()),
            tasks: vec![base_batch_input("Ephemeral")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("first batch");
    assert_eq!(count_tasks(&server), 1);

    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE mcp_idempotency SET expires_at = ?1 WHERE key = ?2",
                rusqlite::params!["2000-01-01T00:00:00.000Z", "batch-expiring"],
            )
            .map_err(|e| e.to_string())?;
            Ok(())
        })
        .expect("backdate expiry");

    let second = server
        .batch_create_tasks(Parameters(BatchCreateTasksArgs {
            idempotency_key: Some("batch-expiring".to_string()),
            tasks: vec![base_batch_input("Ephemeral (post-expiry)")],
            include_advice: None,
            dry_run: false,
        }))
        .expect("second batch after expiry");

    assert_ne!(
        first, second,
        "once the cache entry has expired a fresh batch must be recorded"
    );
    assert_eq!(
        count_tasks(&server),
        2,
        "expired entries must not block a fresh insert"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_with_idempotency_key_returns_cached_on_retry() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000b01",
        "Cancel retry A",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000b02",
        "Cancel retry B",
        "open",
        None,
        None,
        None,
        0,
    );

    let first = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec![
                "01966a3f-7c8b-7d4e-8f3a-000000000b01".to_string(),
                "01966a3f-7c8b-7d4e-8f3a-000000000b02".to_string(),
            ],
            reason: Some("retry-safe cancel".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: Some("batch-cancel-retry".to_string()),
        }))
        .expect("first batch cancel");

    let second = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec![
                "01966a3f-7c8b-7d4e-8f3a-000000000b01".to_string(),
                "01966a3f-7c8b-7d4e-8f3a-000000000b02".to_string(),
            ],
            reason: Some("retry-safe cancel".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: Some("batch-cancel-retry".to_string()),
        }))
        .expect("retry should replay cached batch cancel response");

    assert_eq!(
        first, second,
        "the retry must replay the original batch cancel response byte-for-byte"
    );
    assert_eq!(
        count_changelog_for_tool(&server, "batch_cancel_tasks"),
        1,
        "the retry must not run the mutation or changelog a second time"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_idempotency_rejects_payload_drift_under_same_key() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000b02",
        "Cancel collision",
        "open",
        None,
        None,
        None,
        0,
    );

    server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000b02".to_string()],
            reason: Some("first reason".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: Some("01966a3f-7c8b-7d4e-8f3a-000000000b02-key".to_string()),
        }))
        .expect("first batch cancel");

    let err = server
        .batch_cancel_tasks(Parameters(BatchCancelTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000b02".to_string()],
            reason: Some("different reason".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: Some("01966a3f-7c8b-7d4e-8f3a-000000000b02-key".to_string()),
        }))
        .expect_err("checksum mismatch must be rejected before terminal-state validation");

    assert!(
        err.contains("idempotency_key '01966a3f-7c8b-7d4e-8f3a-000000000b02-key'"),
        "diagnostic should name the colliding key, got: {err}"
    );
    assert!(
        err.contains("different request payload"),
        "diagnostic should explain the collision, got: {err}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn same_key_and_id_do_not_replay_response_across_delete_tools() {
    let server = make_server();
    let shared_id = "01966a3f-7c8b-7d4e-8f3a-000000000b03";
    let shared_key = "cross-tool-delete-key";
    seed_list_named(&server, shared_id, "Cross Tool List");
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO calendar_events (
                    id, title, start_date, all_day, version, created_at, updated_at
                 ) VALUES (?1, 'Cross Tool Event', '2026-04-12', 1,
                           '0000000000000_0000_0000000000000000',
                           '2026-04-01T08:00:00Z',
                           '2026-04-01T08:00:00Z')",
                [shared_id],
            )
            .map_err(|error| error.to_string())?;
            Ok(())
        })
        .expect("seed same-id calendar event");

    let list_response = server
        .delete_list(Parameters(DeleteListArgs {
            id: shared_id.to_string(),
            dry_run: false,
            idempotency_key: Some(shared_key.to_string()),
        }))
        .expect("delete_list should succeed");
    let list_payload: Value = serde_json::from_str(&list_response).expect("parse list response");
    assert_eq!(list_payload["deleted_list_id"], shared_id);

    let event_response = server
        .delete_calendar_event(Parameters(DeleteCalendarEventArgs {
            id: shared_id.to_string(),
            dry_run: false,
            idempotency_key: Some(shared_key.to_string()),
        }))
        .expect("delete_calendar_event should not replay delete_list response");
    let event_payload: Value = serde_json::from_str(&event_response).expect("parse event response");
    assert_eq!(event_payload["id"], shared_id);
    assert_eq!(event_payload["deleted"], true);
    assert!(
        event_payload.get("deleted_list_id").is_none(),
        "calendar delete must return its own payload, not delete_list's cached response"
    );

    let (event_rows, cache_rows, calendar_delete_audits): (i64, i64, i64) = server
        .with_read_conn(|conn| {
            let event_rows = conn
                .query_row(
                    "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
                    [shared_id],
                    |row| row.get::<_, i64>(0),
                )
                .map_err(|error| error.to_string())?;
            let cache_rows = conn
                .query_row(
                    "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
                    [shared_key],
                    |row| row.get::<_, i64>(0),
                )
                .map_err(|error| error.to_string())?;
            let calendar_delete_audits = conn
                .query_row(
                    "SELECT COUNT(*) FROM ai_changelog WHERE mcp_tool = 'delete_calendar_event'",
                    [],
                    |row| row.get::<_, i64>(0),
                )
                .map_err(|error| error.to_string())?;
            Ok((event_rows, cache_rows, calendar_delete_audits))
        })
        .expect("read post-delete state");
    assert_eq!(event_rows, 0, "calendar event must actually be deleted");
    assert_eq!(
        cache_rows, 2,
        "same idempotency key must create one cache row per tool"
    );
    assert_eq!(
        calendar_delete_audits, 1,
        "calendar delete mutation must run instead of replaying delete_list"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_with_idempotency_key_returns_cached_on_retry() {
    let server = make_server();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000130";
    seed_list_named(
        &server,
        "list-permanent-delete-retry",
        "Permanent Delete Retry",
    );
    seed_task(
        &server,
        task_id,
        "Permanent Delete Retry",
        "open",
        Some("list-permanent-delete-retry"),
        None,
        None,
        0,
    );
    archive_task_for_idempotency_test(&server, task_id);

    let first = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: task_id.to_string(),
            dry_run: false,
            idempotency_key: Some("permanent-delete-retry-key".to_string()),
        }))
        .expect("first permanent delete should succeed");
    let first_payload: Value = serde_json::from_str(&first).expect("parse first delete response");
    assert_eq!(first_payload["id"], task_id);
    assert_eq!(first_payload["deleted"], true);
    assert_eq!(first_payload["previous"]["title"], "Permanent Delete Retry");
    assert!(!task_exists_for_idempotency_test(&server, task_id));

    let changelog_after_first = count_changelog_for_tool(&server, "permanent_delete_task");
    let outbox_after_first = count_sync_outbox(&server);

    let second = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: task_id.to_string(),
            dry_run: false,
            idempotency_key: Some("permanent-delete-retry-key".to_string()),
        }))
        .expect("retry permanent delete should replay cached response");

    assert_eq!(
        second, first,
        "retry must replay the original hard-delete response, not rerun or surface not-found"
    );
    assert_eq!(
        count_changelog_for_tool(&server, "permanent_delete_task"),
        changelog_after_first
    );
    assert_eq!(count_sync_outbox(&server), outbox_after_first);
}

#[test]
#[serial_test::serial(hlc)]
fn recurring_batch_cancel_retry_replays_successor_response() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000b04",
        "Recurring cancel retry",
        "open",
        None,
        Some("2026-04-01"),
        None,
        0,
    );
    server
        .with_conn(|conn| {
            conn.execute(
                "UPDATE tasks SET recurrence = ?1,
                    recurrence_group_id = '01966a3f-7c8b-7d4e-8f3a-000000000b04-group',
                    canonical_occurrence_date = '2026-04-01'
                 WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000b04'",
                [r#"{"FREQ":"DAILY","INTERVAL":1}"#],
            )
            .map_err(crate::system::handler_support::to_error_message)?;
            Ok(())
        })
        .expect("seed recurrence");

    let args = || BatchCancelTasksArgs {
        task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000b04".to_string()],
        reason: Some("skip this occurrence".to_string()),
        cancel_series: Some(false),
        dry_run: false,
        idempotency_key: Some("01966a3f-7c8b-7d4e-8f3a-000000000b04-retry".to_string()),
    };

    let first = server
        .batch_cancel_tasks(Parameters(args()))
        .expect("first recurring batch cancel");
    let first_payload: Value =
        serde_json::from_str(&first).expect("parse first recurring batch cancel response");
    assert_eq!(first_payload["cancelled_count"].as_u64(), Some(1));
    assert_eq!(
        first_payload["next_occurrences"].as_array().map(Vec::len),
        Some(1),
        "first recurring cancel should report the spawned successor"
    );
    let changelog_after_first = count_changelog_for_tool(&server, "batch_cancel_tasks");

    let second = server
        .batch_cancel_tasks(Parameters(args()))
        .expect("retry should not validate against the already-cancelled row");

    assert_eq!(
        first, second,
        "the retry must replay the original successor-bearing response"
    );
    assert_eq!(
        count_changelog_for_tool(&server, "batch_cancel_tasks"),
        changelog_after_first,
        "the retry must not run the recurring cancel cascade twice"
    );
}
