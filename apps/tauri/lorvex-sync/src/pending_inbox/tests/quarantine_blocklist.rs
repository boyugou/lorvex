use super::super::*;
use super::support::*;
use rusqlite::params;

/// drift guard: a poisoned identity recorded in
/// `sync_quarantine_blocklist` must short-circuit `enqueue_pending`
/// so a chatty redelivery (provider retry, file-bridge replay)
/// stops climbing the retry ladder from `attempt_count = 1`. The
/// pre-fix shape would re-create the row, increment the cap, and
/// re-fire an EXHAUSTED conflict on every redelivery.
#[test]
fn enqueue_pending_short_circuits_quarantined_identity() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-poison");

    // Seed the blocklist directly to simulate a prior cap-discard.
    record_quarantine(
        &conn,
        env.entity_type.as_str(),
        &env.entity_id,
        &env.version.to_string(),
    )
    .unwrap();

    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();

    let pending = get_all_pending(&conn).unwrap();
    assert!(
        pending.is_empty(),
        "blocklisted identity must NOT enter pending_inbox; \
         got {} pending row(s)",
        pending.len()
    );
}

/// drift guard: a successful enqueue + cap-discard via repeated
/// drains must end with the identity recorded in the blocklist so
/// future redeliveries short-circuit. We test the synchronous
/// enqueue-side cap (50 redundant enqueues), since it's the
/// shortest path to the cap-promote branch.
#[test]
fn enqueue_pending_records_blocklist_when_cap_promotes() {
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-cap");

    // Drive `attempt_count` from 1 to MAX by re-enqueuing the same
    // identity. Each call increments via UPSERT, and the cap
    // branch fires once `attempt_count >= MAX_PENDING_INBOX_ATTEMPTS`.
    for _ in 0..(MAX_PENDING_INBOX_ATTEMPTS as usize) {
        enqueue_pending(
            &conn,
            &env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
        )
        .unwrap();
    }

    // Final attempt fires the cap branch and removes the row.
    let pending = get_all_pending(&conn).unwrap();
    assert!(
        pending.is_empty(),
        "exhausted identity must be removed from pending_inbox"
    );

    let blocklisted = is_quarantined(
        &conn,
        env.entity_type.as_str(),
        &env.entity_id,
        &env.version.to_string(),
    )
    .unwrap();
    assert!(
        blocklisted,
        "exhausted identity must be recorded in sync_quarantine_blocklist"
    );

    // A subsequent redelivery must short-circuit.
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();
    assert!(
        get_all_pending(&conn).unwrap().is_empty(),
        "post-quarantine redelivery must NOT re-enter pending_inbox"
    );
}

/// First-write-wins on `sync_quarantine_blocklist` (#3307 T2-6):
/// `ON CONFLICT DO NOTHING` must preserve the first-observed `quarantined_at`
/// under a redelivery storm rather than advancing it on every hit. This test
/// guards against a regression that re-enables an overwriting `DO UPDATE`.
#[test]
fn record_quarantine_preserves_first_observed_row() {
    let conn = test_db();

    record_quarantine(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002192",
        "v1",
    )
    .unwrap();
    let first_at: String = conn
        .query_row(
            "SELECT quarantined_at FROM sync_quarantine_blocklist \
             WHERE entity_type = ?1 AND entity_id = ?2 AND version = ?3",
            params![
                naming::ENTITY_TASK,
                "01966a3f-7c8b-7d4e-8f3a-000000002192",
                "v1"
            ],
            |row| row.get(0),
        )
        .unwrap();

    // Force a measurable timestamp delta so a regression that re-enables the
    // overwrite would update `quarantined_at` to a later value.
    std::thread::sleep(std::time::Duration::from_millis(2));

    record_quarantine(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002192",
        "v1",
    )
    .unwrap();
    let second_at: String = conn
        .query_row(
            "SELECT quarantined_at FROM sync_quarantine_blocklist \
             WHERE entity_type = ?1 AND entity_id = ?2 AND version = ?3",
            params![
                naming::ENTITY_TASK,
                "01966a3f-7c8b-7d4e-8f3a-000000002192",
                "v1"
            ],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(
        first_at, second_at,
        "redelivery must NOT advance quarantined_at past the first-observed timestamp"
    );
}
