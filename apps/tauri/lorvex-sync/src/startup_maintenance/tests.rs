use crate::envelope::{SyncEnvelope, SyncOperation};
use lorvex_domain::naming;

use super::{
    flag_reseed_required_due_to_pending_horizon_in_transaction, gc_expired_pending_queues,
    run_pending_queue_retention_maintenance, run_startup_sync_maintenance_with_options,
    StartupSyncMaintenanceOptions,
};
use crate::pending_inbox::PendingDrainSummary;

fn make_envelope(entity_type: &str, entity_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: r#"{"title":"test"}"#.to_string(),
        device_id: "device-001".to_string(),
    }
}

fn make_preference_envelope(key: &str, value: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Preference,
        entity_id: key.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: format!(r#"{{"value":"{value}","updated_at":"2026-03-24T00:00:00.000Z"}}"#),
        device_id: "remote-device".to_string(),
    }
}

#[test]
fn pending_horizon_marker_and_conflict_log_are_atomic() {
    let conn = lorvex_store::test_support::test_conn();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");
    crate::pending_inbox::enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("task-missing"),
    )
    .expect("enqueue pending");
    conn.execute(
        "UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z'",
        [],
    )
    .expect("backdate pending row");

    lorvex_store::with_immediate_transaction(&conn, |conn| {
        flag_reseed_required_due_to_pending_horizon_in_transaction(conn)
    })
    .expect("flag reseed");

    let marker = lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_RESEED_REQUIRED)
        .expect("read reseed marker");
    assert_eq!(marker.as_deref(), Some("true"));

    let conflicts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log \
             WHERE resolution_type = ?1 AND entity_type = 'sync_pending_inbox'",
            [naming::RESOLUTION_RESEED_REQUIRED],
            |row| row.get(0),
        )
        .expect("count reseed conflicts");
    assert_eq!(conflicts, 1);
}

#[test]
fn pending_queue_retention_flags_reseed_then_gc_drops_expired_rows() {
    let conn = lorvex_store::test_support::test_conn();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");
    crate::pending_inbox::enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("task-missing"),
    )
    .expect("enqueue pending");
    conn.execute(
        "UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z'",
        [],
    )
    .expect("backdate pending row");

    run_pending_queue_retention_maintenance(&conn).expect("retention maintenance");

    let marker = lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_RESEED_REQUIRED)
        .expect("read reseed marker");
    assert_eq!(marker.as_deref(), Some("true"));
    assert_eq!(
        crate::pending_inbox::count_pending(&conn).expect("count pending"),
        0
    );
}

#[test]
fn gc_expired_pending_queues_reports_deleted_counts() {
    let conn = lorvex_store::test_support::test_conn();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");
    crate::pending_inbox::enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("task-missing"),
    )
    .expect("enqueue pending");
    conn.execute(
        "UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z'",
        [],
    )
    .expect("backdate pending row");

    let inbox = gc_expired_pending_queues(&conn).expect("gc pending queues");
    assert_eq!(inbox, 1);
}

#[test]
fn startup_sync_maintenance_still_drains_when_retention_fails() {
    let conn = crate::test_db();

    let report = run_startup_sync_maintenance_with_options(
        &conn,
        StartupSyncMaintenanceOptions {
            promote_payload_shadows: false,
        },
    )
    .expect("drain should still run even when retention cannot open a nested transaction");

    assert!(
        report.pending_queue_retention_error.is_some(),
        "outer transaction should make retention fail in this fixture"
    );
    assert_eq!(
        report.warnings.len(),
        1,
        "retention failure should be returned as a structured warning"
    );
    assert_eq!(
        report.warnings[0].source,
        "sync.startup.pending_queue_retention_failed"
    );
    assert_eq!(report.pending_inbox_drain, PendingDrainSummary::default());
}

#[test]
fn startup_sync_maintenance_drains_pending_inbox_from_autocommit_connection() {
    let conn = lorvex_store::test_support::test_conn();
    assert!(
        conn.is_autocommit(),
        "startup callers use ordinary autocommit connections"
    );
    let env = make_preference_envelope("theme", "dark");
    crate::pending_inbox::enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        None,
        None,
    )
    .expect("enqueue pending preference");

    let report = run_startup_sync_maintenance_with_options(
        &conn,
        StartupSyncMaintenanceOptions {
            promote_payload_shadows: false,
        },
    )
    .expect("startup maintenance should transaction-wrap pending drain");

    assert_eq!(report.pending_inbox_drain.replayed, 1);
    assert_eq!(
        crate::pending_inbox::count_pending(&conn).expect("count pending"),
        0
    );
    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = 'theme'",
            [],
            |row| row.get(0),
        )
        .expect("preference should be applied by startup drain");
    assert_eq!(value, "\"dark\"");
}

#[test]
fn autocommit_pending_inbox_drain_rolls_back_apply_when_bookkeeping_fails() {
    let conn = lorvex_store::test_support::test_conn();
    let env = make_preference_envelope("theme", "dark");
    crate::pending_inbox::enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        None,
        None,
    )
    .expect("enqueue pending preference");
    conn.execute_batch(
        "CREATE TRIGGER sync_pending_inbox_delete_block
         BEFORE DELETE ON sync_pending_inbox
         BEGIN
           SELECT RAISE(ABORT, 'test pending bookkeeping failure');
         END;",
    )
    .expect("install failing pending delete trigger");

    let err = crate::pending_inbox::drain_pending_inbox(&conn)
        .expect_err("pending delete failure should abort the wrapped drain transaction");
    assert!(
        err.to_string().contains("test pending bookkeeping failure"),
        "unexpected error: {err}"
    );

    let applied_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM preferences WHERE key = 'theme'",
            [],
            |row| row.get(0),
        )
        .expect("count preference rows");
    assert_eq!(
        applied_rows, 0,
        "preference upsert must roll back with pending-row bookkeeping"
    );
    assert_eq!(
        crate::pending_inbox::count_pending(&conn).expect("count pending"),
        1,
        "pending row must remain after rollback"
    );
}
