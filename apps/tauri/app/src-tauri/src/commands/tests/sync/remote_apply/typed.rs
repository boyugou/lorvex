use super::*;
use crate::commands::sync::runtime::apply_remote_sync_records_with_checkpoint_writer;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization};

const TASK_DEFERRED_ENQUEUE_FAILURE: &str = "01966a3f-7c8b-7d4e-8f3a-00000000020f";
const TASK_PENDING_DRAIN_FAILURE: &str = "01966a3f-7c8b-7d4e-8f3a-000000000210";
const TASK_CHECKPOINT_ROLLBACK: &str = "01966a3f-7c8b-7d4e-8f3a-000000000211";
const TASK_CURSOR_APPLIED: &str = "01966a3f-7c8b-7d4e-8f3a-000000000212";
const TASK_CURSOR_DEFERRED: &str = "01966a3f-7c8b-7d4e-8f3a-000000000213";
const TASK_CURSOR_GC_GUARD: &str = "01966a3f-7c8b-7d4e-8f3a-000000000214";
const TASK_CURSOR_ONLY_DEFERRED: &str = "01966a3f-7c8b-7d4e-8f3a-000000000215";

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_rolls_back_when_enqueue_deferred_fails() {
    let conn = setup_sync_test_conn();
    conn.execute("DROP TABLE sync_pending_inbox", [])
        .expect("drop sync_pending_inbox");

    let mut deferred = make_sync_event(
        "evt-typed-deferred-enqueue-failure",
        "task",
        TASK_DEFERRED_ENQUEUE_FAILURE,
        "upsert",
        json!({
            "id": TASK_DEFERRED_ENQUEUE_FAILURE,
            "title": "Should defer",
            "status": "open",
            "created_at": "2026-03-29T09:00:00Z",
        }),
        "2026-03-29T09:00:00Z",
        "device-typed-deferred",
    );
    deferred.envelope.payload_schema_version = lorvex_domain::version::PAYLOAD_SCHEMA_VERSION + 2;

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![deferred],
        "2026-03-29T09:05:00Z",
        RemoteApplyMode::StrictAtomic,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    );

    let error = result.expect_err("deferred enqueue failure should roll back");
    assert!(
        error.to_string().contains("sync_pending_inbox"),
        "unexpected error: {error}"
    );

    let last_pull_at: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_pull_at");
    assert!(last_pull_at.is_none());
}

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_preserves_applied_records_on_pending_drain_failure(
) {
    // The drain is a best-effort side effect, not a correctness gate:
    // genuine data that was just applied must not be rolled back because
    // the pending-inbox drain hit a SQL error (e.g. schema drift). This is
    // the opposite behavior from the initial implementation; see the F4.2
    // finding in the sync pipeline audit.
    let conn = setup_sync_test_conn();
    conn.execute("DROP TABLE sync_pending_inbox", [])
        .expect("drop sync_pending_inbox");

    let event = make_sync_event(
        "evt-typed-pending-drain-failure",
        "task",
        TASK_PENDING_DRAIN_FAILURE,
        "upsert",
        json!({
            "id": TASK_PENDING_DRAIN_FAILURE,
            "title": "Should NOT roll back on pending drain failure",
            "status": "open",
            "created_at": "2026-03-29T09:00:00Z",
        }),
        "2026-03-29T09:00:00Z",
        "device-typed-drain",
    );

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![event],
        "2026-03-29T09:05:00Z",
        RemoteApplyMode::StrictAtomic,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    )
    .expect("apply should succeed despite drain failure");
    assert_eq!(result.applied, 1);
    assert_eq!(
        task_title(&conn, TASK_PENDING_DRAIN_FAILURE),
        Some("Should NOT roll back on pending drain failure".to_string()),
    );

    let last_pull_at: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_pull_at");
    assert_eq!(last_pull_at.as_deref(), Some("2026-03-29T09:05:00Z"));

    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source = 'sync.apply.pending_inbox_drain'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read pending inbox drain diagnostic");
    assert_eq!(row.0, "sync.apply.pending_inbox_drain");
    assert_eq!(row.1, "warn");
    assert_eq!(row.2, "Sync apply pending inbox drain failed");
    assert!(row.3.contains("sync_pending_inbox"));
}

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_rolls_back_on_checkpoint_error() {
    let conn = setup_sync_test_conn();
    let event = make_sync_event(
        "evt-typed-checkpoint-rollback",
        "task",
        TASK_CHECKPOINT_ROLLBACK,
        "upsert",
        json!({
            "id": TASK_CHECKPOINT_ROLLBACK,
            "title": "Should roll back on checkpoint error",
            "status": "open",
            "created_at": "2026-03-29T09:00:00Z",
        }),
        "2026-03-29T09:00:00Z",
        "device-typed-a",
    );

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![event],
        "2026-03-29T09:05:00Z",
        RemoteApplyMode::StrictAtomic,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)?;
            Err(crate::error::AppError::Validation(
                "checkpoint writer failed after apply".to_string(),
            ))
        },
    );

    let error = result.expect_err("typed checkpoint writer should fail");
    assert!(
        error
            .to_string()
            .contains("checkpoint writer failed after apply"),
        "unexpected error: {error}"
    );
    assert_eq!(task_title(&conn, TASK_CHECKPOINT_ROLLBACK), None);

    let last_pull_at: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_pull_at");
    assert!(last_pull_at.is_none());
}

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_best_effort_persists_checkpoint() {
    let conn = setup_sync_test_conn();
    // See remote checkpoint.rs for the rationale: unknown
    // `entity_type` is now rejected at the typed wire boundary, so
    // the apply-time failure path is exercised via a malformed
    // `task_dependency` edge id (no `task_a:task_b` separator).
    let malformed = make_sync_event(
        "evt-typed-malformed",
        "task_dependency",
        "invalid-no-colon",
        "upsert",
        json!({}),
        "2026-03-29T10:00:00Z",
        "device-typed-b",
    );

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![malformed],
        "2026-03-29T10:05:00Z",
        RemoteApplyMode::BestEffort,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    )
    .expect("best-effort typed apply should succeed");

    assert_eq!(result.received, 1);
    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_malformed, 1);

    let last_pull_at: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .expect("query last_pull_at");
    assert_eq!(last_pull_at, "2026-03-29T10:05:00Z");
}

#[test]
fn apply_remote_sync_records_device_cursor_ignores_deferred_and_malformed_records() {
    let conn = setup_sync_test_conn();
    let device_id = "device-cursor-watermark";
    let applied_version = "2026-03-29T09:00:00Z";
    let applied = make_sync_event(
        "evt-cursor-applied",
        "task",
        TASK_CURSOR_APPLIED,
        "upsert",
        json!({
            "id": TASK_CURSOR_APPLIED,
            "title": "Applied cursor baseline",
            "status": "open",
            "created_at": applied_version,
        }),
        applied_version,
        device_id,
    );
    let deferred = make_sync_event(
        "evt-cursor-deferred",
        "task",
        TASK_CURSOR_DEFERRED,
        "upsert",
        json!({
            "id": TASK_CURSOR_DEFERRED,
            "title": "Deferred should not advance cursor",
            "status": "open",
            "list_id": "missing-list-for-cursor",
            "created_at": "2026-03-29T10:00:00Z",
        }),
        "2026-03-29T10:00:00Z",
        device_id,
    );
    let malformed = make_sync_event(
        "evt-cursor-malformed",
        "task_dependency",
        "invalid-no-colon",
        "upsert",
        json!({}),
        "2026-03-29T11:00:00Z",
        device_id,
    );

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![deferred, malformed, applied],
        "2026-03-29T11:05:00Z",
        RemoteApplyMode::BestEffort,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    )
    .expect("best-effort apply should succeed");

    assert_eq!(result.applied, 1);
    assert_eq!(result.skipped_deferred, 1);
    assert_eq!(result.skipped_malformed, 1);

    let last_applied_version: Option<String> = conn
        .query_row(
            "SELECT last_applied_version FROM sync_device_cursors WHERE device_id = ?1",
            params![device_id],
            |row| row.get(0),
        )
        .optional()
        .expect("query device cursor");
    let expected_version = make_hlc_version(applied_version, device_id).to_string();
    assert_eq!(
        last_applied_version.as_deref(),
        Some(expected_version.as_str()),
        "cursor watermark must reflect only records that actually applied",
    );
}

#[test]
fn apply_remote_sync_records_device_cursor_blocks_tombstone_gc_for_unapplied_only_device() {
    let conn = setup_sync_test_conn();
    let applied_device = "device-cursor-applied-peer";
    let unapplied_device = "device-cursor-unapplied-peer";
    let tombstone_version = make_hlc_version("2026-03-29T08:00:00Z", "device-delete").to_string();
    let applied_watermark = make_hlc_version("2026-03-29T12:00:00Z", applied_device).to_string();

    lorvex_sync::tombstone::create_tombstone(
        &conn,
        "task",
        TASK_CURSOR_GC_GUARD,
        &tombstone_version,
        "2026-03-29T08:00:00.000Z",
        None,
        None,
    )
    .expect("create tombstone");
    lorvex_sync::tombstone::upsert_device_cursor_with_version(
        &conn,
        applied_device,
        "2026-05-07T10:00:00.000Z",
        Some(&applied_watermark),
    )
    .expect("seed applied peer cursor");

    let deferred = make_sync_event(
        "evt-cursor-only-deferred",
        "task",
        TASK_CURSOR_ONLY_DEFERRED,
        "upsert",
        json!({
            "id": TASK_CURSOR_ONLY_DEFERRED,
            "title": "Deferred-only peer should block GC",
            "status": "open",
            "list_id": "missing-list-for-cursor-only-peer",
            "created_at": "2026-03-29T11:00:00Z",
        }),
        "2026-03-29T11:00:00Z",
        unapplied_device,
    );

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        vec![deferred],
        "2026-05-07T10:05:00.000Z",
        RemoteApplyMode::BestEffort,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    )
    .expect("best-effort deferred-only apply should succeed");

    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_deferred, 1);

    let (unapplied_cursor_count, unapplied_cursor): (i64, Option<String>) = conn
        .query_row(
            "SELECT COUNT(*), MAX(last_applied_version) FROM sync_device_cursors WHERE device_id = ?1",
            params![unapplied_device],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("query unapplied peer cursor");
    assert_eq!(
        unapplied_cursor_count, 1,
        "unapplied-only peer should still get an active cursor row",
    );
    assert_eq!(
        unapplied_cursor, None,
        "unapplied-only peer should have an active NULL cursor row",
    );

    let deleted = lorvex_sync::tombstone::gc_tombstones_watermark(&conn)
        .expect("run tombstone GC with unapplied peer cursor");
    assert_eq!(
        deleted, 0,
        "NULL cursor for an active unapplied peer must suppress version-watermark GC",
    );
    assert!(
        lorvex_sync::tombstone::get_tombstone(&conn, "task", TASK_CURSOR_GC_GUARD)
            .expect("query guarded tombstone")
            .is_some(),
        "tombstone should remain until every active peer has an applied watermark",
    );
}

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_rolls_back_when_enter_maintenance_mode_fails() {
    let conn = setup_sync_test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::DropTrigger { .. } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let records = (0..51)
        .map(|index| {
            let task_id = format!("01966a3f-7c8b-7d4e-8f3a-{:012x}", 0x230 + index);
            make_sync_event(
                &format!("evt-typed-enter-maintenance-{index}"),
                "task",
                &task_id,
                "upsert",
                json!({
                    "id": task_id.clone(),
                    "title": format!("Should roll back enter maintenance {index}"),
                    "status": "open",
                    "created_at": "2026-03-29T11:00:00Z",
                }),
                "2026-03-29T11:00:00Z",
                "device-typed-enter-maintenance",
            )
        })
        .collect();

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        records,
        "2026-03-29T11:05:00Z",
        RemoteApplyMode::StrictAtomic,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    );

    let error = result.expect_err("maintenance-mode enter failure should roll back");
    assert!(
        error.to_string().contains("not authorized"),
        "unexpected error: {error}"
    );
    assert_eq!(
        task_title(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000230"),
        None
    );

    let last_pull_at: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_pull_at");
    assert!(last_pull_at.is_none());
}

#[test]
fn apply_remote_sync_records_with_checkpoint_writer_rolls_back_when_exit_maintenance_mode_fails() {
    let conn = setup_sync_test_conn();
    conn.authorizer(Some(|ctx: AuthContext<'_>| match ctx.action {
        AuthAction::Insert {
            table_name: "tasks_fts",
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }))
    .expect("install authorizer");

    let records = (0..51)
        .map(|index| {
            let task_id = format!("01966a3f-7c8b-7d4e-8f3a-{:012x}", 0x270 + index);
            make_sync_event(
                &format!("evt-typed-exit-maintenance-{index}"),
                "task",
                &task_id,
                "upsert",
                json!({
                    "id": task_id.clone(),
                    "title": format!("Should roll back exit maintenance {index}"),
                    "status": "open",
                    "created_at": "2026-03-29T12:00:00Z",
                }),
                "2026-03-29T12:00:00Z",
                "device-typed-exit-maintenance",
            )
        })
        .collect();

    let result = apply_remote_sync_records_with_checkpoint_writer(
        &conn,
        records,
        "2026-03-29T12:05:00Z",
        RemoteApplyMode::StrictAtomic,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)
        },
    );

    let error = result.expect_err("maintenance-mode exit failure should roll back");
    assert!(
        error.to_string().contains("not authorized"),
        "unexpected error: {error}"
    );
    assert_eq!(
        task_title(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000270"),
        None
    );

    let last_pull_at: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_pull_at'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_pull_at");
    assert!(last_pull_at.is_none());
}
