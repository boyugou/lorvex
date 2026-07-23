use super::super::*;
use super::support::*;

#[test]
fn enqueue_and_get_pending() {
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

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].reason, naming::RESOLUTION_FK_UNRESOLVED);
    assert_eq!(
        pending[0].missing_entity_type.as_deref(),
        Some(naming::ENTITY_TASK)
    );
    assert_eq!(
        pending[0].missing_entity_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189")
    );
    assert_eq!(pending[0].attempt_count, 1);
}

#[test]
fn parse_envelope_roundtrip() {
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

    let pending = get_all_pending(&conn).unwrap();
    let parsed = pending[0].parse_envelope().expect("should parse back");
    assert_eq!(
        parsed.entity_type,
        lorvex_domain::naming::EntityKind::TaskReminder
    );
    assert_eq!(parsed.entity_id, "reminder-001");
    assert_eq!(parsed.operation, SyncOperation::Upsert);
}

#[test]
fn remove_pending_deletes_entry() {
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

    let pending = get_all_pending(&conn).unwrap();
    remove_pending(&conn, pending[0].id).unwrap();

    let remaining = get_all_pending(&conn).unwrap();
    assert!(remaining.is_empty());
}

#[test]
fn count_pending_empty() {
    let conn = test_db();
    assert_eq!(count_pending(&conn).unwrap(), 0);
}

#[test]
fn count_pending_after_inserts() {
    let conn = test_db();

    for i in 0..3 {
        let env = make_envelope(naming::ENTITY_TASK_REMINDER, &format!("reminder-{i:03}"));
        enqueue_pending(
            &conn,
            &env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some(&format!("01966a3f-7c8b-7d4e-8f3a-000000002162{i:03}")),
        )
        .unwrap();
    }

    assert_eq!(count_pending(&conn).unwrap(), 3);
}

#[test]
fn enqueue_without_missing_info() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-000000002163");

    // Some stall reasons might not have specific missing entity info.
    enqueue_pending(&conn, &env, "schema_incompatible", None, None).unwrap();

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert!(pending[0].missing_entity_type.is_none());
    assert!(pending[0].missing_entity_id.is_none());
}

#[test]
fn fifo_ordering() {
    let conn = test_db();

    for i in 0..5 {
        let env = make_envelope(naming::ENTITY_TASK_REMINDER, &format!("reminder-{i:03}"));
        enqueue_pending(
            &conn,
            &env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some("01966a3f-7c8b-7d4e-8f3a-00000000216b"),
        )
        .unwrap();
    }

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 5);
    for i in 0..4 {
        assert!(
            pending[i].id < pending[i + 1].id,
            "should be ordered by id ASC"
        );
    }
}
