use super::*;

const LIST_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000216";
const TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000217";
const TASK_2: &str = "01966a3f-7c8b-7d4e-8f3a-000000000218";

#[test]
fn apply_remote_sync_envelopes_is_deterministic_across_input_order() {
    let events = vec![
        make_sync_event(
            "evt-list",
            "list",
            LIST_1,
            "upsert",
            json!({
                "id": LIST_1,
                "name": "Project A",
                "created_at": "2026-03-02T08:00:00Z"
            }),
            "2026-03-02T08:00:00Z",
            "device-a",
        ),
        make_sync_event(
            "evt-task-initial",
            "task",
            TASK_1,
            "upsert",
            json!({
                "id": TASK_1,
                "title": "Draft",
                "status": "open",
                "list_id": LIST_1,
                "created_at": "2026-03-02T08:10:00Z"
            }),
            "2026-03-02T08:10:00Z",
            "device-a",
        ),
        make_sync_event(
            "evt-task-final",
            "task",
            TASK_1,
            "upsert",
            json!({
                "id": TASK_1,
                "title": "Final",
                "status": "open",
                "list_id": LIST_1,
                "created_at": "2026-03-02T08:10:00Z"
            }),
            "2026-03-02T09:10:00Z",
            "device-c",
        ),
        make_sync_event(
            "evt-task-2",
            "task",
            TASK_2,
            "upsert",
            json!({
                "id": TASK_2,
                "title": "Secondary",
                "status": "open",
                "list_id": LIST_1,
                "created_at": "2026-03-02T08:20:00Z"
            }),
            "2026-03-02T08:20:00Z",
            "device-b",
        ),
    ];

    let conn_a = setup_sync_test_conn();
    let result_a =
        apply_remote_sync_envelopes_internal(&conn_a, events.clone(), "2026-03-02T10:00:00Z")
            .expect("apply order A");
    let snapshot_a = task_snapshot(&conn_a);

    let mut reversed = events;
    reversed.reverse();
    let conn_b = setup_sync_test_conn();
    let result_b = apply_remote_sync_envelopes_internal(&conn_b, reversed, "2026-03-02T10:00:00Z")
        .expect("apply order B");
    let snapshot_b = task_snapshot(&conn_b);

    assert_eq!(result_a.applied, result_b.applied);
    assert_eq!(result_a.skipped_stale, result_b.skipped_stale);
    assert_eq!(snapshot_a, snapshot_b);
}
