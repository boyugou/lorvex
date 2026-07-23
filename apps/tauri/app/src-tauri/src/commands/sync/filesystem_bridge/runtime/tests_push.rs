use super::tests_support::*;
use super::*;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

#[test]
fn phase_record_push_results_fails_when_retry_state_write_fails() {
    let conn = setup_runtime_test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004291";
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: task_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1774803600000_0000_6465766963656162")
            .expect("test fixture HLC"),
        payload_schema_version: 1,
        payload: serde_json::json!({
            "id": task_id,
            "title": "Retry Failure",
            "status": "open"
        })
        .to_string(),
        device_id: "device-retry".to_string(),
    };
    lorvex_sync::outbox::enqueue(&conn, &envelope).expect("seed outbox entry");
    let outbox_id: i64 = conn
        .query_row("SELECT id FROM sync_outbox LIMIT 1", [], |row| row.get(0))
        .expect("load outbox id");

    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Update {
            table_name: "sync_outbox",
            ..
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    // Simulate a push outcome where the entry needs a retry recorded.
    let outcome = PushPhaseOutcome {
        pushed_ids: Vec::new(),
        retry_ids: vec![outbox_id],
        push_write_errors: 1,
        attempted_push: 1,
        cancelled: false,
        error_messages: Vec::new(),
    };

    let error = phase_record_push_results(&conn, &outcome, "2026-03-29T17:00:00Z")
        .expect_err("retry state write failure should fail phase_record_push_results");
    assert!(
        error.to_string().contains("not authorized") || error.to_string().contains("sync_outbox"),
        "unexpected error: {error}"
    );
}

#[test]
fn phase_push_returns_partial_outcome_when_cancelled_mid_push() {
    let conn = setup_runtime_test_conn();
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-cancel-mid-push-{}",
        uuid::Uuid::now_v7()
    ));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let task_ids = [
        "01966a3f-7c8b-7d4e-8f3a-000000004292",
        "01966a3f-7c8b-7d4e-8f3a-000000004293",
    ];
    for (idx, task_id) in task_ids.iter().enumerate() {
        let envelope = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::Task,
            entity_id: (*task_id).to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse(&format!(
                "1774810000000_{idx:04}_6465766963656162"
            ))
            .expect("test fixture HLC"),
            payload_schema_version: 1,
            payload: serde_json::json!({
                "id": task_id,
                "title": format!("Cancel Mid Push {idx}"),
                "status": "open"
            })
            .to_string(),
            device_id: "device-cancel-mid-push".to_string(),
        };
        lorvex_sync::outbox::enqueue(&conn, &envelope).expect("seed outbox entry");
    }

    let pending = lorvex_sync::outbox::get_pending(&conn).expect("read outbox");
    let outbox_ids: Vec<i64> = pending.iter().map(|entry| entry.id).collect();
    assert_eq!(outbox_ids.len(), 2, "fixture should seed two outbox rows");

    let mut cancel_probes = 0;
    let outcome = phase_push_to_filesystem_with_cancel_probe(pending, &sync_dir, || {
        cancel_probes += 1;
        cancel_probes > 1
    })
    .expect("mid-push cancellation should return a structured partial outcome");

    assert!(
        outcome.cancelled,
        "outcome must preserve the cancellation state"
    );
    assert_eq!(
        outcome.pushed_ids,
        vec![outbox_ids[0]],
        "the already-written row must be retained for Phase C recording"
    );
    assert_eq!(outcome.push_write_errors, 0);

    let now = sync_timestamp_now();
    phase_record_push_results(&conn, &outcome, &now)
        .expect("recording partial push results should succeed");

    let first_synced_at: Option<String> = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            [outbox_ids[0]],
            |row| row.get(0),
        )
        .expect("load first synced_at");
    let second_synced_at: Option<String> = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            [outbox_ids[1]],
            |row| row.get(0),
        )
        .expect("load second synced_at");

    assert!(
        first_synced_at.is_some(),
        "Phase C must mark the pre-cancel successful push as synced"
    );
    assert!(
        second_synced_at.is_none(),
        "the row skipped because of cancellation must remain pending"
    );
}

#[test]
fn phase_push_retries_when_existing_sync_file_is_malformed() {
    let conn = setup_runtime_test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004294";
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: task_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1774809600000_0000_6465766963656162")
            .expect("test fixture HLC"),
        payload_schema_version: 1,
        payload: serde_json::json!({
            "id": task_id,
            "title": "Malformed Sync File",
            "status": "open"
        })
        .to_string(),
        device_id: "device-malformed-sync-file".to_string(),
    };
    lorvex_sync::outbox::enqueue(&conn, &envelope).expect("seed outbox entry");
    let outbox_id: i64 = conn
        .query_row("SELECT id FROM sync_outbox LIMIT 1", [], |row| row.get(0))
        .expect("load outbox id");

    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-malformed-existing-sync-file-{}",
        uuid::Uuid::now_v7()
    ));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");
    // tests now construct the filesystem-bridge file
    // stem via the runtime helper so they stay aligned with the
    // hashed (device-id-redacted) wire format.
    let existing_path = sync_dir.join(format!(
        "{}.json",
        super::filesystem_bridge_file_stem(&envelope.device_id, outbox_id),
    ));
    fs::write(&existing_path, b"{not-valid-json").expect("seed malformed sync file");

    let pending = lorvex_sync::outbox::get_pending(&conn).expect("read outbox");
    let now = sync_timestamp_now();

    let outcome = phase_push_to_filesystem(pending, &sync_dir)
        .expect("malformed existing sync file should produce retry outcome");
    assert!(outcome.pushed_ids.is_empty());
    assert_eq!(outcome.push_write_errors, 1);
    assert_eq!(outcome.retry_ids, vec![outbox_id]);

    // Record push results to verify retry accounting.
    phase_record_push_results(&conn, &outcome, &now)
        .expect("recording push results should succeed");

    let retry_count: i64 = conn
        .query_row(
            "SELECT retry_count FROM sync_outbox WHERE id = ?1",
            [outbox_id],
            |row| row.get(0),
        )
        .expect("load retry count");
    assert_eq!(retry_count, 1, "malformed sync file must record a retry");

    let synced_at: Option<String> = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            [outbox_id],
            |row| row.get(0),
        )
        .expect("load synced_at");
    assert!(
        synced_at.is_none(),
        "malformed existing sync file must not mark outbox entry synced"
    );
}

// `existing_sync_file_matches_outbox_entry` was replaced by the
// four-arm `classify_existing_sync_file` (see #2932-H10); the
// boolean-returning helper conflated "no-op-already-pushed" with
// "stale-crash-artifact-needs-overwrite" and looped forever on the
// latter. The replacement's per-arm regression tests live in
// runtime/tests/classifier.rs.

/// Regression for #2630: per-write error messages collected during
/// the filesystem I/O loop must be persisted to `error_logs` by
/// `phase_record_push_results`. Stderr-only logging would be
/// invisible on Tauri release binaries (no console on macOS) and
/// MCP stdio hosts (stderr is consumed by the host protocol);
/// Settings → Diagnostics depends on error_logs surfacing them.
/// This test locks the write in place so a refactor can't silently
/// drop it.
#[test]
fn phase_record_push_results_writes_error_messages_to_error_logs() {
    let conn = setup_runtime_test_conn();
    let outcome = PushPhaseOutcome {
        pushed_ids: Vec::new(),
        retry_ids: Vec::new(),
        push_write_errors: 2,
        attempted_push: 2,
        cancelled: false,
        error_messages: vec![
            "write sync file /tmp/example_1.json failed: disk is full".to_string(),
            "rename sync file /tmp/example_2.json failed: permission denied".to_string(),
        ],
    };

    phase_record_push_results(&conn, &outcome, "2026-04-18T10:00:00Z")
        .expect("phase_record_push_results should succeed when only error messages fail");

    // Load every row written with our source tag.
    let mut stmt = conn
        .prepare(
            "SELECT level, message FROM error_logs \
             WHERE source = 'sync.filesystem_bridge.push' \
             ORDER BY created_at ASC",
        )
        .expect("prepare error_logs read");
    let rows: Vec<(String, String)> = stmt
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query error_logs")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect error_logs rows");

    assert_eq!(
        rows.len(),
        2,
        "each collected error message must produce exactly one error_logs row, got {rows:?}"
    );
    assert!(
        rows.iter().all(|(level, _)| level == "error"),
        "every filesystem-bridge write error must be logged at level=error, got {rows:?}"
    );
    assert!(
        rows.iter()
            .any(|(_, msg)| msg.contains("write sync file") && msg.contains("disk is full")),
        "missing the 'write sync file' message; rows = {rows:?}"
    );
    assert!(
        rows.iter()
            .any(|(_, msg)| msg.contains("rename sync file") && msg.contains("permission denied")),
        "missing the 'rename sync file' message; rows = {rows:?}"
    );
}

/// Companion check: a successful push (no error_messages) must
/// NOT leak spurious error_logs rows. Locks the branching in
/// `phase_record_push_results` so a future simplification can't
/// accidentally always log.
#[test]
fn phase_record_push_results_does_not_log_when_no_error_messages() {
    let conn = setup_runtime_test_conn();
    let outcome = PushPhaseOutcome {
        pushed_ids: Vec::new(),
        retry_ids: Vec::new(),
        push_write_errors: 0,
        attempted_push: 0,
        cancelled: false,
        error_messages: Vec::new(),
    };

    phase_record_push_results(&conn, &outcome, "2026-04-18T10:00:00Z")
        .expect("phase_record_push_results succeeds on empty outcome");

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs \
             WHERE source = 'sync.filesystem_bridge.push'",
            [],
            |row| row.get(0),
        )
        .expect("count error_logs rows");
    assert_eq!(
        count, 0,
        "no error messages means no error_logs rows must be written"
    );
}

#[test]
fn refresh_dispatchable_pending_outbox_drops_rows_deleted_after_snapshot_before_push() {
    let conn = setup_runtime_test_conn();
    let temp = std::env::temp_dir().join(format!(
        "lorvex-fs-dispatchable-refresh-race-{}",
        uuid::Uuid::now_v7()
    ));
    let sync_dir = temp.join("sync");
    fs::create_dir_all(&sync_dir).expect("create sync dir");

    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000004295";
    let envelope = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: task_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1776816000000_0000_6465766963656162")
            .expect("test fixture HLC"),
        payload_schema_version: 1,
        payload: serde_json::json!({
            "id": task_id,
            "title": "Race",
            "status": "completed"
        })
        .to_string(),
        device_id: "device-race".to_string(),
    };
    lorvex_sync::outbox::enqueue(&conn, &envelope).expect("seed pending outbox entry");

    let pending_snapshot = lorvex_sync::outbox::get_pending(&conn).expect("read pending snapshot");
    assert_eq!(
        pending_snapshot.len(),
        1,
        "fixture should start with one pending row"
    );
    let snapshot_id = pending_snapshot[0].id;

    // Race: the row is removed from sync_outbox after the transport
    // read its snapshot but before it dispatches. `retain_still_dispatchable`
    // re-checks each snapshot id against the live table and must drop
    // the row that no longer exists.
    let deleted = conn
        .execute(
            "DELETE FROM sync_outbox WHERE id = ?1",
            rusqlite::params![snapshot_id],
        )
        .expect("delete pending row mid-race");
    assert_eq!(
        deleted, 1,
        "the mid-push delete should remove the pending row"
    );

    let refreshed = refresh_dispatchable_pending_outbox(&conn, pending_snapshot)
        .expect("refresh dispatchable entries");
    assert!(
        refreshed.is_empty(),
        "rows deleted after the snapshot must not be pushed"
    );

    let outcome = phase_push_to_filesystem(refreshed, &sync_dir)
        .expect("push with empty refreshed set should succeed");
    assert_eq!(outcome.attempted_push, 0);
    assert!(outcome.pushed_ids.is_empty());

    let sync_files = fs::read_dir(&sync_dir)
        .expect("read sync dir")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect sync dir entries");
    assert!(
        sync_files.is_empty(),
        "deleted rows must not leave sync files behind"
    );
}
