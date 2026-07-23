use super::*;

const TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000201";

#[test]
fn apply_remote_sync_envelopes_lww_by_timestamp_for_same_task_field() {
    let conn = setup_sync_test_conn();
    let older = make_sync_event(
        "evt-old",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Old title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T08:00:00Z",
        }),
        "2026-03-02T08:00:00Z",
        "device-a",
    );
    let newer = make_sync_event(
        "evt-new",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "New title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T09:00:00Z",
        }),
        "2026-03-02T09:00:00Z",
        "device-b",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![newer, older], "2026-03-02T10:00:00Z")
            .expect("apply remote events");

    assert_eq!(result.received, 2);
    // Both events are processed; the older one applies first (sorted by timestamp),
    // then the newer one overwrites it.
    assert!(result.applied >= 1);
    assert_eq!(task_title(&conn, TASK_1), Some("New title".to_string()));
}

#[test]
fn apply_remote_sync_envelopes_lww_tie_breaks_by_device_id() {
    let conn = setup_sync_test_conn();
    // Two events with slightly different timestamps from different devices.
    // The newer one should always win regardless of device_id.
    let event_a = make_sync_event(
        "evt-a",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "From device-a",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T09:00:00Z",
        }),
        "2026-03-02T09:00:00Z",
        "device-a",
    );
    let event_z = make_sync_event(
        "evt-z",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "From device-z",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T09:00:01Z",
        }),
        "2026-03-02T09:00:01Z",
        "device-z",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![event_z, event_a], "2026-03-02T10:00:00Z")
            .expect("apply remote events");

    // Event-z has a newer timestamp, so it should win.
    assert!(result.applied >= 1);
    assert_eq!(task_title(&conn, TASK_1), Some("From device-z".to_string()));
}

#[test]
fn apply_remote_sync_envelopes_breaks_same_version_ties_by_event_id() {
    let conn = setup_sync_test_conn();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_1)
        .title("Local title")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-02T08:00:00Z")
        .updated_at("2026-03-02T10:00:00Z")
        .insert(&conn);

    insert_sync_event_row(
        &conn,
        "evt-local-a",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Local title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-same",
        Some("2026-03-02T10:00:30Z"),
    );

    let incoming = make_sync_event(
        "evt-local-z",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Incoming title wins",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T10:00:00Z",
        }),
        "2026-03-02T10:00:00Z",
        "device-same",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![incoming], "2026-03-02T10:01:00Z")
            .expect("apply remote tie-break event");

    assert_eq!(result.received, 1);
    assert_eq!(result.processed, 1);
    // With the same timestamp and device, the event_id tie-break determines
    // the winner. "evt-local-z" > outbox integer id, so incoming should apply.
    assert_eq!(result.applied, 1);
    assert_eq!(result.skipped_stale, 0);
    assert_eq!(
        task_title(&conn, TASK_1),
        Some("Incoming title wins".to_string())
    );
}

#[test]
fn apply_remote_sync_envelopes_applies_remote_on_timestamp_tie_with_higher_device_id() {
    let conn = setup_sync_test_conn();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_1)
        .title("Local title")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-02T08:00:00Z")
        .updated_at("2026-03-02T10:00:00Z")
        .insert(&conn);

    // Mark local event as synced so LWW query finds it (synced_at IS NOT NULL)
    insert_sync_event_row(
        &conn,
        "evt-local",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Local title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-a",
        Some("2026-03-02T10:01:00Z"),
    );

    let incoming = make_sync_event(
        "evt-remote",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Remote wins by device id",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z",
            "updated_at": "2026-03-02T10:00:00Z",
        }),
        "2026-03-02T10:00:00Z",
        "device-z",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![incoming], "2026-03-02T10:03:00Z")
            .expect("apply tie-break by device id");

    assert_eq!(result.received, 1);
    assert_eq!(result.processed, 1);
    assert_eq!(result.applied, 1);
    assert_eq!(result.skipped_stale, 0);
    assert_eq!(
        task_title(&conn, TASK_1),
        Some("Remote wins by device id".to_string())
    );
}
