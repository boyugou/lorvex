use super::*;

const TASK_DUP: &str = "01966a3f-7c8b-7d4e-8f3a-000000000209";
const TASK_MALFORMED_DEVICE: &str = "01966a3f-7c8b-7d4e-8f3a-00000000020a";
const TASK_EMPTY_RECORD_ID: &str = "01966a3f-7c8b-7d4e-8f3a-00000000020b";
const TASK_BAD: &str = "01966a3f-7c8b-7d4e-8f3a-00000000020c";
const TASK_GOOD: &str = "01966a3f-7c8b-7d4e-8f3a-00000000020d";

#[test]
fn apply_remote_sync_envelopes_replay_is_idempotent_for_duplicate_event_id() {
    let conn = setup_sync_test_conn();
    let event = make_sync_event(
        "evt-dup",
        "task",
        TASK_DUP,
        "upsert",
        json!({
            "id": TASK_DUP,
            "title": "From first replay",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T08:00:00Z",
        "device-a",
    );

    let first =
        apply_remote_sync_envelopes_internal(&conn, vec![event.clone()], "2026-03-02T09:00:00Z")
            .expect("first apply");
    let second = apply_remote_sync_envelopes_internal(&conn, vec![event], "2026-03-02T09:05:00Z")
        .expect("second apply");

    assert_eq!(first.processed, 1);
    assert_eq!(first.applied, 1);
    // Second apply: same version, so LWW skips it as stale (not strictly a duplicate,
    // but the entity is already at the same or newer version).
    assert_eq!(second.applied, 0);
    assert_eq!(second.skipped_stale, 1);
}

#[test]
fn apply_remote_sync_envelopes_skips_empty_device_id_without_applying() {
    let conn = setup_sync_test_conn();
    let malformed_device = make_sync_event(
        "evt-malformed-device-id",
        "task",
        TASK_MALFORMED_DEVICE,
        "upsert",
        json!({
            "id": TASK_MALFORMED_DEVICE,
            "title": "Should not apply",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![malformed_device], "2026-03-02T09:10:00Z")
            .expect("apply malformed device_id event");

    assert_eq!(result.received, 1);
    assert_eq!(result.processed, 1);
    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_malformed, 1);
    assert_eq!(task_title(&conn, TASK_MALFORMED_DEVICE), None);
}

#[test]
fn apply_remote_sync_envelopes_counts_empty_transport_id_as_processed_malformed() {
    let conn = setup_sync_test_conn();
    let mut malformed_record_id = make_sync_event(
        "evt-empty-record-id",
        "task",
        TASK_EMPTY_RECORD_ID,
        "upsert",
        json!({
            "id": TASK_EMPTY_RECORD_ID,
            "title": "Should not apply",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "device-a",
    );
    malformed_record_id.id = "   ".to_string();

    let result = apply_remote_sync_envelopes_internal(
        &conn,
        vec![malformed_record_id],
        "2026-03-02T09:10:00Z",
    )
    .expect("apply malformed record id event");

    assert_eq!(result.received, 1);
    assert_eq!(result.processed, 1);
    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_malformed, 1);
    assert_eq!(task_title(&conn, TASK_EMPTY_RECORD_ID), None);
}

#[test]
fn apply_remote_sync_envelopes_skips_malformed_payload_without_rolling_back_batch() {
    let conn = setup_sync_test_conn();
    let invalid_payload_event = make_sync_event(
        "evt-malformed",
        "task",
        TASK_BAD,
        "upsert",
        serde_json::json!({}),
        "2026-03-02T09:00:00Z",
        "device-a",
    );
    // Override payload with invalid JSON.
    let invalid_payload_event = IncomingSyncRecord {
        envelope: lorvex_sync::envelope::SyncEnvelope {
            payload: "{not-valid-json".to_string(),
            ..invalid_payload_event.envelope
        },
        ..invalid_payload_event
    };
    let valid_event = make_sync_event(
        "evt-valid-after-malformed",
        "task",
        TASK_GOOD,
        "upsert",
        json!({
            "id": TASK_GOOD,
            "title": "Applied after malformed",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:01Z",
        "device-b",
    );

    let result = apply_remote_sync_envelopes_internal(
        &conn,
        vec![invalid_payload_event, valid_event],
        "2026-03-02T09:10:00Z",
    )
    .expect("apply mixed valid/malformed payload events");

    assert_eq!(result.received, 2);
    assert_eq!(result.processed, 2);
    assert_eq!(result.applied, 1);
    assert_eq!(result.skipped_malformed, 1);
    assert_eq!(
        task_title(&conn, TASK_GOOD),
        Some("Applied after malformed".to_string())
    );
    assert_eq!(task_title(&conn, TASK_BAD), None);

    let last_error: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_error'",
            [],
            |row| row.get(0),
        )
        .expect("read last_error warning");
    assert!(last_error.contains("skipped 1 malformed incoming sync payload event(s)"));
}
