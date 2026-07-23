use super::*;

const TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000204";

#[test]
fn apply_remote_sync_envelopes_handles_delete_update_conflicts() {
    // Scenario 1: Delete (newer) wins over upsert (older).
    // With the lorvex-sync pipeline, a newer delete tombstones the entity.
    // The older upsert is skipped because the tombstone version is newer.
    let conn_delete_wins = setup_sync_test_conn();
    let upsert_old = make_sync_event(
        "evt-upsert-old",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Active task",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T08:00:00Z",
        "device-a",
    );
    let delete_new = make_sync_event(
        "evt-delete-new",
        "task",
        TASK_1,
        "delete",
        json!({}),
        "2026-03-02T09:00:00Z",
        "device-b",
    );
    apply_remote_sync_envelopes_internal(
        &conn_delete_wins,
        vec![delete_new, upsert_old],
        "2026-03-02T10:00:00Z",
    )
    .expect("apply delete-win events");
    // After delete wins, the task row should be gone.
    assert_eq!(task_status(&conn_delete_wins, TASK_1), None);

    // Scenario 2: Upsert (newer) wins over delete (older).
    // With the lorvex-sync pipeline, a newer upsert removes the tombstone
    // and creates/updates the entity.
    let conn_upsert_wins = setup_sync_test_conn();
    let delete_old = make_sync_event(
        "evt-delete-old",
        "task",
        TASK_1,
        "delete",
        json!({}),
        "2026-03-02T08:00:00Z",
        "device-a",
    );
    let upsert_new = make_sync_event(
        "evt-upsert-new",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Reopened task",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "device-b",
    );
    apply_remote_sync_envelopes_internal(
        &conn_upsert_wins,
        vec![upsert_new, delete_old],
        "2026-03-02T10:00:00Z",
    )
    .expect("apply upsert-win events");
    assert_eq!(
        task_status(&conn_upsert_wins, TASK_1),
        Some("open".to_string())
    );
    assert_eq!(
        task_title(&conn_upsert_wins, TASK_1),
        Some("Reopened task".to_string())
    );
}

#[test]
fn apply_remote_sync_envelopes_delete_update_tie_breaks_by_device_id() {
    // Scenario 1: delete (device-z, newer timestamp) vs upsert (device-a, older).
    let conn_delete_wins = setup_sync_test_conn();
    let upsert_a = make_sync_event(
        "evt-upsert-a",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "From device-a",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "device-a",
    );
    let delete_z = make_sync_event(
        "evt-delete-z",
        "task",
        TASK_1,
        "delete",
        json!({}),
        "2026-03-02T09:00:01Z",
        "device-z",
    );
    apply_remote_sync_envelopes_internal(
        &conn_delete_wins,
        vec![upsert_a, delete_z],
        "2026-03-02T10:00:00Z",
    )
    .expect("apply tie-break delete-win events");
    // Delete is newer, so task should be gone.
    assert_eq!(task_status(&conn_delete_wins, TASK_1), None);

    // Scenario 2: upsert (device-z, newer timestamp) vs delete (device-a, older).
    let conn_upsert_wins = setup_sync_test_conn();
    let delete_a = make_sync_event(
        "evt-delete-a",
        "task",
        TASK_1,
        "delete",
        json!({}),
        "2026-03-02T09:00:00Z",
        "device-a",
    );
    let upsert_z = make_sync_event(
        "evt-upsert-z",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "From device-z",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:01Z",
        "device-z",
    );
    apply_remote_sync_envelopes_internal(
        &conn_upsert_wins,
        vec![delete_a, upsert_z],
        "2026-03-02T10:00:00Z",
    )
    .expect("apply tie-break upsert-win events");
    assert_eq!(
        task_status(&conn_upsert_wins, TASK_1),
        Some("open".to_string())
    );
    assert_eq!(
        task_title(&conn_upsert_wins, TASK_1),
        Some("From device-z".to_string())
    );
}
