use super::super::cursor::load_filesystem_bridge_pull_cursor;
use super::*;

fn open_runtime_file_db(root: &std::path::Path) -> (std::path::PathBuf, rusqlite::Connection) {
    crate::hlc::ensure_hlc_for_test();
    fs::create_dir_all(root).expect("create db root");
    let db_path = root.join("lorvex.sqlite");
    let conn = lorvex_store::open_db_at_path(&db_path).expect("open file-backed runtime db");
    (db_path, conn)
}

fn seed_sync_device_id(conn: &rusqlite::Connection, device_id: &str) {
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![device_id],
    )
    .expect("seed device_id checkpoint");
}

fn seed_roundtrip_fixture(conn: &rusqlite::Connection) {
    const LIST_ID: &str = "01972bb0-0000-7000-8000-000000000001";
    const PARENT_TASK_ID: &str = "01972bb0-0000-7000-8000-000000000002";
    const CHILD_TASK_ID: &str = "01972bb0-0000-7000-8000-000000000003";
    const EVENT_ID: &str = "01972bb0-0000-7000-8000-000000000004";

    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, version, created_at, updated_at)
         VALUES (?1, 'Roundtrip', '#335577', 'tray', 'filesystem bridge fixture', 'fixture scope', ?2, '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')",
        params![LIST_ID, "0000000000000_0000_a0a0a0a0a0a0a0a0"],
    )
    .expect("insert list fixture");
    // lift to canonical TaskBuilder.
    use lorvex_store::test_support::fixtures::TaskBuilder;
    TaskBuilder::new(PARENT_TASK_ID)
        .title("Parent task")
        .body(Some("depends-on root"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-19T08:05:00Z")
        .list_id(Some(LIST_ID))
        .priority(Some(1))
        .due_date(Some("2026-04-22"))
        .planned_date(Some("2026-04-20"))
        .insert(conn);
    TaskBuilder::new(CHILD_TASK_ID)
        .title("Child task")
        .body(Some("depends on parent"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-19T08:06:00Z")
        .list_id(Some(LIST_ID))
        .priority(Some(2))
        .due_date(Some("2026-04-23"))
        .planned_date(Some("2026-04-21"))
        .insert(conn);
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, ?3, '2026-04-19T08:07:00Z')",
        params![
            CHILD_TASK_ID,
            PARENT_TASK_ID,
            "0000000000000_0000_a0a0a0a0a0a0a0a0"
        ],
    )
    .expect("insert dependency edge");
    conn.execute(
        "INSERT INTO calendar_events (
            id, title, description, start_date, start_time, end_date, end_time, all_day,
            location, timezone, version, created_at, updated_at
         ) VALUES (
            ?1, 'Roundtrip sync', 'Shared folder event', '2026-04-25', '09:00',
            '2026-04-25', '10:00', 0, 'Desk', 'America/Los_Angeles', ?2,
            '2026-04-19T08:10:00Z', '2026-04-19T08:10:00Z'
         )",
        params![EVENT_ID, "0000000000000_0000_a0a0a0a0a0a0a0a0"],
    )
    .expect("insert calendar event");
    conn.execute(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, '2026-04-19T08:11:00Z', '2026-04-19T08:11:00Z')",
        params![
            CHILD_TASK_ID,
            EVENT_ID,
            "0000000000000_0000_a0a0a0a0a0a0a0a0"
        ],
    )
    .expect("insert task-event link");
}

type RoundtripListRow = (
    String,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
    String,
    String,
);

type RoundtripTaskRow = (
    String,
    String,
    Option<String>,
    String,
    String,
    Option<i64>,
    Option<String>,
    Option<String>,
    String,
    String,
);

type RoundtripCalendarEventRow = (
    String,
    String,
    Option<String>,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    i64,
    Option<String>,
    Option<String>,
    String,
    String,
);

#[derive(Debug, Clone, PartialEq, Eq)]
struct FilesystemBridgeRoundtripSnapshot {
    lists: Vec<RoundtripListRow>,
    tasks: Vec<RoundtripTaskRow>,
    task_dependencies: Vec<(String, String, String)>,
    calendar_events: Vec<RoundtripCalendarEventRow>,
    task_calendar_event_links: Vec<(String, String, String, String)>,
}

fn load_roundtrip_snapshot(conn: &rusqlite::Connection) -> FilesystemBridgeRoundtripSnapshot {
    let lists = {
        let mut stmt = conn
            .prepare(
                "SELECT id, name, color, icon, description, ai_notes, created_at, updated_at
                 FROM lists ORDER BY id",
            )
            .expect("prepare lists snapshot");
        stmt.query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
            ))
        })
        .expect("query lists snapshot")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect lists snapshot")
    };
    let tasks = {
        let mut stmt = conn
            .prepare(
                "SELECT id, title, body, status, list_id, priority, due_date, planned_date,
                        created_at, updated_at
                 FROM tasks ORDER BY id",
            )
            .expect("prepare tasks snapshot");
        stmt.query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
                row.get(9)?,
            ))
        })
        .expect("query tasks snapshot")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect tasks snapshot")
    };
    let task_dependencies = {
        let mut stmt = conn
            .prepare(
                "SELECT task_id, depends_on_task_id, created_at
                 FROM task_dependencies ORDER BY task_id, depends_on_task_id",
            )
            .expect("prepare dependency snapshot");
        stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
            .expect("query dependency snapshot")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect dependency snapshot")
    };
    let calendar_events = {
        let mut stmt = conn
            .prepare(
                "SELECT id, title, description, start_date, start_time, end_date, end_time,
                        all_day, location, timezone, created_at, updated_at
                 FROM calendar_events ORDER BY id",
            )
            .expect("prepare event snapshot");
        stmt.query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get(6)?,
                row.get(7)?,
                row.get(8)?,
                row.get(9)?,
                row.get(10)?,
                row.get(11)?,
            ))
        })
        .expect("query event snapshot")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect event snapshot")
    };
    let task_calendar_event_links = {
        let mut stmt = conn
            .prepare(
                "SELECT task_id, calendar_event_id, created_at, updated_at
                 FROM task_calendar_event_links ORDER BY task_id, calendar_event_id",
            )
            .expect("prepare task-event link snapshot");
        stmt.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query task-event link snapshot")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect task-event link snapshot")
    };

    FilesystemBridgeRoundtripSnapshot {
        lists,
        tasks,
        task_dependencies,
        calendar_events,
        task_calendar_event_links,
    }
}

fn run_filesystem_bridge_sync_with_conn(
    conn: &rusqlite::Connection,
    db_path: &std::path::Path,
    sync_dir: &std::path::Path,
    cap: i64,
) -> FilesystemBridgeSyncResult {
    let sync_dir_display = sync_dir.to_string_lossy().to_string();
    let now = sync_timestamp_now();

    let read_state = match phase_read_outbox_and_pull_state(conn, sync_dir, &sync_dir_display, cap)
        .expect("phase_read_outbox_and_pull_state succeeds")
    {
        Ok(data) => data,
        Err(result) => return result,
    };
    let pending = refresh_dispatchable_pending_outbox(conn, read_state.pending.clone())
        .expect("retain still dispatchable");

    let mut result: Option<FilesystemBridgeSyncResult> = None;
    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        let push_outcome =
            phase_push_to_filesystem(pending, sync_dir).expect("phase_push_to_filesystem");
        let pushed = usize_to_i64("pushed outbox count", push_outcome.pushed_ids.len())
            .expect("convert pushed count");
        let push_write_errors = push_outcome.push_write_errors;
        let attempted_push = push_outcome.attempted_push;

        phase_record_push_results(conn, &push_outcome, &now).expect("phase_record_push_results");

        let pull_cap = usize::try_from(cap.saturating_mul(5))
            .unwrap_or(1_000)
            .max(1);
        let collected_remote = collect_remote_filesystem_bridge_envelopes(
            sync_dir,
            &read_state.local_device_id,
            pull_cap,
            read_state.last_pull_cursor.as_ref(),
            Some(&read_state.known_lookback_event_ids),
        )
        .expect("collect remote envelopes");
        let pull_parse_errors = collected_remote.pull_parse_errors;
        let cursor_blocking_parse_errors = collected_remote.cursor_blocking_parse_errors;
        let (
            apply_result,
            pulled_files,
            pulled_remote_events,
            lookback_known_id_skipped,
            pull_limit_hit,
        ) = phase_apply_and_finalize(
            conn,
            sync_dir,
            &read_state.local_device_id,
            collected_remote,
            push_write_errors,
            &now,
        )
        .expect("phase_apply_and_finalize");
        ensure_filesystem_bridge_full_sync_seeded_after_pull(conn, &sync_dir_display)
            .expect("ensure filesystem bridge full-sync seed after pull");
        record_filesystem_bridge_completion_status(
            conn,
            push_write_errors,
            pull_parse_errors,
            cursor_blocking_parse_errors,
        )
        .expect("record filesystem bridge completion status");

        result = Some(build_filesystem_bridge_sync_result(
            sync_dir_display.clone(),
            FilesystemBridgeSyncCounts {
                attempted_push,
                pushed,
                push_write_errors,
                pulled_files,
                pulled_remote_events,
                pull_parse_errors,
                lookback_known_id_skipped,
                pull_limit_hit,
            },
            apply_result,
            false,
        ));
    });
    result.expect("filesystem bridge sync result populated")
}

#[test]
fn filesystem_bridge_after_pull_seed_failure_does_not_mark_success() {
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-after-pull-seed-failure-{}",
        uuid::Uuid::now_v7()
    ));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let db_root = temp.join("device-b");
    let (db_path, conn) = open_runtime_file_db(&db_root);
    seed_sync_device_id(&conn, "device-b-00000001");
    conn.execute(
        "INSERT INTO preferences (key, value, updated_at, version)
         VALUES ('theme', '{not-valid-json', '2026-03-29T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        [],
    )
    .expect("insert malformed preference");

    let valid_payload = serde_json::json!({
        "title": "Remote record before failed seed",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-04-22T18:10:00.000Z",
        "updated_at": "2026-04-22T18:10:00.000Z",
    });
    let valid_record = serde_json::json!({
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000b302",
        "operation": "upsert",
        "version": "0001776000001000_0000_a0a0a0a0a0a0a0a1",
        "payload_schema_version": lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
        "payload": valid_payload.to_string(),
        "device_id": "device-a-00000000",
    });
    fs::write(
        sync_dir.join("device-a_0001776000001000_valid.json"),
        valid_record.to_string(),
    )
    .expect("write valid remote envelope");

    let sync_dir_display = sync_dir.to_string_lossy().to_string();
    let read_state = phase_read_outbox_and_pull_state(&conn, &sync_dir, &sync_dir_display, 200)
        .expect("phase_read_outbox_and_pull_state should succeed")
        .expect("remote envelopes should defer seed until after pull");
    assert!(
        read_state.pending.is_empty(),
        "fresh joiner should not push before pulling existing remote state"
    );

    crate::db::with_db_path_env_for_test(&db_path.to_string_lossy(), || {
        let collected_remote = collect_remote_filesystem_bridge_envelopes(
            &sync_dir,
            &read_state.local_device_id,
            1_000,
            read_state.last_pull_cursor.as_ref(),
            Some(&read_state.known_lookback_event_ids),
        )
        .expect("collect remote envelopes");
        assert_eq!(collected_remote.pull_parse_errors, 0);

        phase_apply_and_finalize(
            &conn,
            &sync_dir,
            &read_state.local_device_id,
            collected_remote,
            0,
            "2026-03-29T15:00:00Z",
        )
        .expect("remote apply/finalize succeeds before after-pull seed");

        let error = ensure_filesystem_bridge_full_sync_seeded_after_pull(&conn, &sync_dir_display)
            .expect_err("malformed local preference should fail after-pull seed");
        assert!(
            error.to_string().contains("full-sync seed failed"),
            "unexpected error: {error}"
        );
    });

    let success_checkpoint_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_checkpoints WHERE key = ?1",
            params![lorvex_runtime::KEY_LAST_SUCCESS_AT],
            |row| row.get(0),
        )
        .expect("count success checkpoint rows");
    assert_eq!(
        success_checkpoint_count, 0,
        "after-pull seed failure must not leave the sync status marked successful"
    );

    let last_error: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = ?1",
            params![lorvex_runtime::KEY_LAST_ERROR],
            |row| row.get(0),
        )
        .expect("read last_error checkpoint");
    assert!(
        last_error.contains("Filesystem bridge full-sync seed failed"),
        "unexpected last_error: {last_error}"
    );
}

#[test]
fn filesystem_bridge_unknown_operation_file_blocks_pull_cursor_advancement() {
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-unknown-operation-cursor-{}",
        uuid::Uuid::now_v7()
    ));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let db_root = temp.join("device-b");
    let (db_path, conn) = open_runtime_file_db(&db_root);
    seed_sync_device_id(&conn, "device-b-00000001");
    lorvex_runtime::sync_checkpoint_set(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
        .expect("mark full sync seeded");

    let unknown_operation = serde_json::json!({
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000a301",
        "operation": "merge",
        "version": "0001776000000000_0000_a0a0a0a0a0a0a0a0",
        "payload_schema_version": lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
        "payload": "{}",
        "device_id": "device-a-00000000",
    });
    fs::write(
        sync_dir.join("device-a_0001776000000000_unknown.json"),
        unknown_operation.to_string(),
    )
    .expect("write unknown operation envelope");

    let valid_payload = serde_json::json!({
        "title": "Valid record after unknown op",
        "status": "open",
        "defer_count": 0,
        "created_at": "2026-04-22T18:10:00.000Z",
        "updated_at": "2026-04-22T18:10:00.000Z",
    });
    let valid_record = serde_json::json!({
        "entity_type": "task",
        "entity_id": "01966a3f-7c8b-7d4e-8f3a-00000000a302",
        "operation": "upsert",
        "version": "0001776000001000_0000_a0a0a0a0a0a0a0a1",
        "payload_schema_version": lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
        "payload": valid_payload.to_string(),
        "device_id": "device-a-00000000",
    });
    fs::write(
        sync_dir.join("device-a_0001776000001000_valid.json"),
        valid_record.to_string(),
    )
    .expect("write valid envelope after unknown operation");

    let result = run_filesystem_bridge_sync_with_conn(&conn, &db_path, &sync_dir, 200);

    assert_eq!(
        result.pull_parse_errors, 1,
        "unknown operation file must surface as a parse error"
    );
    assert_eq!(
        result.apply_result.applied, 1,
        "valid later records should still apply in the same pass"
    );

    let persisted = load_filesystem_bridge_pull_cursor(&conn)
        .expect("load filesystem bridge cursor after unknown operation");
    assert!(
        persisted.is_none(),
        "cursor must not advance past an unknown operation file"
    );

    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000a302'",
            [],
            |row| row.get(0),
        )
        .expect("count applied valid task");
    assert_eq!(task_count, 1);
}

#[test]
fn filesystem_bridge_roundtrip_replays_tasks_edges_and_events_to_fresh_db() {
    let temp = std::env::temp_dir().join(format!("lorvex-fs-roundtrip-{}", uuid::Uuid::now_v7()));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let a_root = temp.join("device-a");
    let b_root = temp.join("device-b");
    let (db_a_path, conn_a) = open_runtime_file_db(&a_root);
    let (db_b_path, conn_b) = open_runtime_file_db(&b_root);

    seed_sync_device_id(&conn_a, "test-device-00000000");
    seed_sync_device_id(&conn_b, "device-b-00000001");
    seed_roundtrip_fixture(&conn_a);

    crate::commands::sync::runtime::seed_full_sync_internal(&conn_a)
        .expect("seed full sync from device A");

    let result_a = run_filesystem_bridge_sync_with_conn(&conn_a, &db_a_path, &sync_dir, 200);
    assert_eq!(result_a.apply_result.applied, 0);
    assert_eq!(result_a.push_write_errors, 0);
    assert!(
        result_a.pushed >= 6,
        "expected seeded device A to push fixture entities, got {result_a:?}"
    );

    let expected_snapshot = load_roundtrip_snapshot(&conn_a);
    let result_b_first = run_filesystem_bridge_sync_with_conn(&conn_b, &db_b_path, &sync_dir, 200);
    assert_eq!(result_b_first.push_write_errors, 0);
    assert!(
        result_b_first.apply_result.applied >= 6,
        "expected fresh device B to apply exported fixture entities, got {result_b_first:?}"
    );

    let actual_snapshot = load_roundtrip_snapshot(&conn_b);
    assert_eq!(
        actual_snapshot, expected_snapshot,
        "fresh device B must materialize the same canonical payloads exported by device A"
    );

    let pending_inbox_count: i64 = conn_b
        .query_row("SELECT COUNT(*) FROM sync_pending_inbox", [], |row| {
            row.get(0)
        })
        .expect("count sync_pending_inbox");
    assert_eq!(
        pending_inbox_count, 0,
        "roundtrip fixture should drain all deferred child/edge envelopes"
    );

    let snapshot_before_second_sync = load_roundtrip_snapshot(&conn_b);
    let result_b_second = run_filesystem_bridge_sync_with_conn(&conn_b, &db_b_path, &sync_dir, 200);
    assert_eq!(
        result_b_second.apply_result.applied, 0,
        "idempotent re-sync on device B must not reapply already-consumed files"
    );
    assert_eq!(
        load_roundtrip_snapshot(&conn_b),
        snapshot_before_second_sync,
        "second sync pass must be a no-op for canonical state"
    );
}
