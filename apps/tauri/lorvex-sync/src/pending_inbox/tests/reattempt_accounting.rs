use super::super::*;
use super::support::*;

#[test]
fn record_reattempt_increments_count() {
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
    let id = pending[0].id;

    record_reattempt(&conn, id).unwrap();
    record_reattempt(&conn, id).unwrap();

    let updated = get_all_pending(&conn).unwrap();
    assert_eq!(updated[0].attempt_count, 3); // 1 initial + 2 reattempts
}

#[test]
fn invariant_blocked_replay_bumps_attempt_once() {
    let conn = test_db();
    let env = make_delete_envelope(naming::ENTITY_LIST, "inbox");
    let reason = DeferralReason::AggregateInvariantBlocked {
        entity_type: naming::EntityKind::List,
        entity_id: "inbox".to_string(),
        invariant: "at_least_one_list",
    };

    enqueue_deferred(&conn, &env, &reason).expect("seed invariant-blocked pending row");
    let summary = drain_pending_inbox(&conn).expect("drain invariant-blocked row");

    assert_eq!(summary.discarded, 0);
    assert_eq!(summary.errors, 0);

    let pending = get_all_pending(&conn).expect("read pending row");
    assert_eq!(pending.len(), 1);
    assert_eq!(
        pending[0].attempt_count, 2,
        "one drain replay should count as one attempt, not one duplicate enqueue plus one reattempt"
    );
    assert_eq!(
        pending[0].missing_entity_type.as_deref(),
        Some(naming::ENTITY_LIST)
    );
    assert_eq!(pending[0].missing_entity_id.as_deref(), Some("inbox"));
}
