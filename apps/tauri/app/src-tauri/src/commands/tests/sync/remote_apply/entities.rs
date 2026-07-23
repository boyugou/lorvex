use lorvex_domain::naming::EDGE_TASK_DEPENDENCY;

use super::*;

const CALENDAR_EVENT_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000205";
const TASK_1: &str = "01966a3f-7c8b-7d4e-8f3a-000000000206";
const TASK_A: &str = "01966a3f-7c8b-7d4e-8f3a-000000000207";
const TASK_B: &str = "01966a3f-7c8b-7d4e-8f3a-000000000208";

#[test]
fn apply_remote_sync_envelopes_supports_calendar_event_entities() {
    let conn = setup_sync_test_conn();
    let upsert_event = make_sync_event(
        "evt-cal-upsert",
        "calendar_event",
        CALENDAR_EVENT_1,
        "upsert",
        json!({
            "id": CALENDAR_EVENT_1,
            "title": "Weekly sync",
            "start_date": "2026-03-03",
            "start_time": "09:00",
            "end_date": "2026-03-03",
            "end_time": "09:30",
            "all_day": false,
            "source": "manual",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T08:00:00Z",
        "device-a",
    );
    apply_remote_sync_envelopes_internal(&conn, vec![upsert_event], "2026-03-02T09:00:00Z")
        .expect("apply calendar upsert");

    let title: String = conn
        .query_row(
            "SELECT title FROM calendar_events WHERE id = ?1",
            params![CALENDAR_EVENT_1],
            |row| row.get(0),
        )
        .expect("calendar event should exist");
    assert_eq!(title, "Weekly sync");

    let delete_event = make_sync_event(
        "evt-cal-delete",
        "calendar_event",
        CALENDAR_EVENT_1,
        "delete",
        json!({ "id": CALENDAR_EVENT_1, "title": "Weekly sync" }),
        "2026-03-02T10:00:00Z",
        "device-b",
    );
    apply_remote_sync_envelopes_internal(&conn, vec![delete_event], "2026-03-02T10:05:00Z")
        .expect("apply calendar delete");

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
            params![CALENDAR_EVENT_1],
            |row| row.get(0),
        )
        .expect("count calendar rows");
    assert_eq!(count, 0);
}

#[test]
fn apply_remote_sync_envelopes_task_upsert_with_missing_list_is_deferred() {
    let conn = setup_sync_test_conn();
    let upsert_task = make_sync_event(
        "evt-task-missing-list",
        "task",
        TASK_1,
        "upsert",
        json!({
            "id": TASK_1,
            "title": "Task with stale list reference",
            "status": "open",
            "list_id": "missing-list",
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T09:00:00Z",
        "device-a",
    );

    let result =
        apply_remote_sync_envelopes_internal(&conn, vec![upsert_task], "2026-03-02T09:05:00Z")
            .expect("apply task upsert with missing list");

    // Task is deferred to pending_inbox (not applied) because list doesn't exist yet.
    assert_eq!(result.applied, 0);
    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            params![TASK_1],
            |row| row.get(0),
        )
        .expect("count task rows");
    assert_eq!(task_count, 0);

    // Verify it's in the pending inbox (waiting for the missing list)
    let pending_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_pending_inbox WHERE missing_entity_id = 'missing-list'",
            [],
            |row| row.get(0),
        )
        .expect("count pending inbox rows");
    assert_eq!(pending_count, 1);
}

#[test]
fn apply_remote_sync_envelopes_applies_depends_on_and_skips_stale_peer() {
    let conn = setup_sync_test_conn();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_A)
        .title("Task A")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-02T08:00:00Z")
        .priority(Some(3))
        .insert(&conn);
    // Set an HLC version so the new pipeline can do LWW comparison.
    // HLC for 2026-03-02T11:00:00Z = 1772449200000
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(TASK_B)
        .title("Task B local newer title")
        .version("1772449200000_0000_6465766963656c6f")
        .created_at("2026-03-02T08:00:00Z")
        .updated_at("2026-03-02T11:00:00Z")
        .priority(Some(1))
        .insert(&conn);

    let add_dependency_to_a = make_sync_event(
        "evt-remote-a-depends-on-b",
        EDGE_TASK_DEPENDENCY,
        &format!("{TASK_A}:{TASK_B}"),
        "upsert",
        json!({
            "task_id": TASK_A,
            "depends_on_task_id": TASK_B
        }),
        "2026-03-02T10:00:00Z",
        "device-remote",
    );
    let stale_peer_upsert_for_b = make_sync_event(
        "evt-remote-b-stale",
        "task",
        TASK_B,
        "upsert",
        json!({
            "id": TASK_B,
            "title": "Task B remote stale title",
            "status": "open",
            "priority": 1,
            "depends_on": null,
            "created_at": "2026-03-02T08:00:00Z"
        }),
        "2026-03-02T10:00:00Z",
        "device-remote",
    );

    let result = apply_remote_sync_envelopes_internal(
        &conn,
        vec![add_dependency_to_a, stale_peer_upsert_for_b],
        "2026-03-02T11:05:00Z",
    )
    .expect("apply remote dependency batch");

    assert_eq!(result.received, 2);
    assert_eq!(result.applied, 1);
    assert_eq!(result.skipped_stale, 1);

    // Verify dependency edge was created in edge table
    let a_dep_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id = ?2",
            params![TASK_A, TASK_B],
            |row| row.get(0),
        )
        .expect("read task a dependency edges");
    assert_eq!(
        a_dep_count, 1,
        "Task A should depend on Task B via edge table"
    );

    // Task B should keep its local newer title (stale remote was skipped)
    let b_title: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = ?1",
            params![TASK_B],
            |row| row.get(0),
        )
        .expect("read task b title");
    assert_eq!(b_title, "Task B local newer title");
}
