use super::*;

const TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000202";
const TASK_PRECISION: &str = "01966a3f-7c8b-7d4e-8f3a-000000000203";

#[test]
fn apply_remote_sync_envelopes_skips_stale_updates_but_records_event() {
    let conn = setup_sync_test_conn();
    let newest = make_sync_event(
        "evt-newest",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Newest title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "device-z",
    );
    apply_remote_sync_envelopes_internal(&conn, vec![newest], "2026-03-02T09:05:00Z")
        .expect("apply newest");

    let stale = make_sync_event(
        "evt-stale",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Stale title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T08:30:00Z",
        "device-a",
    );
    let result = apply_remote_sync_envelopes_internal(&conn, vec![stale], "2026-03-02T09:10:00Z")
        .expect("apply stale");

    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_stale, 1);
    assert_eq!(result.processed, 1);
    assert_eq!(task_title(&conn, TASK_1), Some("Newest title".to_string()));
}

#[test]
fn apply_remote_sync_envelopes_uses_microsecond_precision_when_resolving_latest_local_version() {
    let conn = setup_sync_test_conn();

    // Insert a task with an HLC version so the new pipeline can do LWW
    // comparison against it (the entity's version column is the source of
    // truth for stale detection in the lorvex-sync pipeline).
    // HLC for 2026-03-02T10:00:00.900Z = 1772445600900
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_PRECISION)
        .title("Latest local")
        .version("1772445600900_0000_6465766963656161")
        .created_at("2026-03-02T08:00:00Z")
        .updated_at("2026-03-02T10:00:00Z")
        .insert(&conn);

    // The incoming event has a timestamp equivalent to 2026-03-02T10:00:00.500Z = 1772294400500
    let incoming_mid = make_sync_event(
        "evt-remote-mid",
        "task",
        TASK_PRECISION,
        "upsert",
        json!({
            "id": TASK_PRECISION,
            "title": "Remote mid timestamp",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00.500000Z",
        "device-b",
    );
    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![incoming_mid], "2026-03-02T10:01:00Z")
            .expect("apply incoming mid timestamp");

    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_stale, 1);
    assert_eq!(
        task_title(&conn, TASK_PRECISION),
        Some("Latest local".to_string())
    );
}

#[test]
fn apply_remote_sync_envelopes_skips_stale_remote_when_local_write_is_newer() {
    let conn = setup_sync_test_conn();

    // Insert a task with an HLC version — the new pipeline uses the entity's
    // version column for stale detection.
    // HLC for 2026-03-02T10:00:00Z = 1772445600000
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_1)
        .title("Local newer title")
        .version("1772445600000_0000_6465766963656c6f")
        .created_at("2026-03-02T08:00:00Z")
        .updated_at("2026-03-02T10:00:00Z")
        .insert(&conn);

    let incoming = make_sync_event(
        "evt-remote-older",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Remote stale title",
            "status": "open",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:59:59Z",
        "device-remote",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![incoming], "2026-03-02T10:02:00Z")
            .expect("apply stale remote event");

    assert_eq!(result.received, 1);
    assert_eq!(result.processed, 1);
    assert_eq!(result.applied, 0);
    assert_eq!(result.skipped_stale, 1);
    assert_eq!(
        task_title(&conn, TASK_1),
        Some("Local newer title".to_string())
    );
}
