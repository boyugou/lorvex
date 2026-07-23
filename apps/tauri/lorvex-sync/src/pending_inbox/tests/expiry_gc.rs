use super::super::*;
use super::support::*;

#[test]
fn has_expired_entries_false_when_recent() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");

    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();

    // Just enqueued, so first_attempted_at is now. 90 days horizon should not expire.
    assert!(!has_expired_entries(&conn, 90).unwrap());
}

#[test]
fn has_expired_entries_true_when_old() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");

    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();

    // Manually backdate the first_attempted_at to simulate an old entry.
    conn.execute(
        "UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z'",
        [],
    )
    .unwrap();

    assert!(has_expired_entries(&conn, 90).unwrap());
}

#[test]
fn has_expired_entries_empty_inbox() {
    let conn = test_db();
    assert!(!has_expired_entries(&conn, 90).unwrap());
}

#[test]
fn gc_expired_entries_deletes_past_horizon() {
    let conn = test_db();
    let old_env = make_envelope(naming::ENTITY_TASK_REMINDER, "old-reminder");
    let new_env = make_envelope(naming::ENTITY_TASK_REMINDER, "new-reminder");

    enqueue_pending(
        &conn,
        &old_env,
        naming::RESOLUTION_FK_UNRESOLVED,
        None,
        None,
    )
    .unwrap();
    enqueue_pending(
        &conn,
        &new_env,
        naming::RESOLUTION_FK_UNRESOLVED,
        None,
        None,
    )
    .unwrap();

    conn.execute(
        "UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z' \
         WHERE id = (SELECT MIN(id) FROM sync_pending_inbox)",
        [],
    )
    .unwrap();

    let deleted = gc_expired_entries(&conn, 90).unwrap();
    assert_eq!(deleted, 1);

    let remaining = get_all_pending(&conn).unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(
        remaining[0].parse_envelope().unwrap().entity_id,
        "new-reminder"
    );
}

#[test]
fn gc_expired_entries_keeps_recent() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-001");
    enqueue_pending(&conn, &env, naming::RESOLUTION_FK_UNRESOLVED, None, None).unwrap();
    let deleted = gc_expired_entries(&conn, 90).unwrap();
    assert_eq!(deleted, 0);
    assert_eq!(get_all_pending(&conn).unwrap().len(), 1);
}
