use super::super::*;
use super::support::*;

#[test]
fn drain_discards_entry_that_exceeded_attempt_cap() {
    // once an entry has been retried MAX_PENDING_INBOX_ATTEMPTS
    // times and the next drain still cannot apply it, the drain
    // discards the entry, logs a `pending_inbox_exhausted`
    // conflict_log row, and does not leave it for horizon GC.
    let conn = test_db();
    let env = make_reminder_envelope_with_missing_task(
        "reminder-stuck",
        "01966a3f-7c8b-7d4e-8f3a-000000002191",
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002191"),
    )
    .unwrap();

    // Simulate the entry having already burned MAX - 1 attempts so
    // this drain pushes it over the cap.
    conn.execute(
        "UPDATE sync_pending_inbox SET attempt_count = ?1",
        params![MAX_PENDING_INBOX_ATTEMPTS - 1],
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.discarded, 1, "entry at cap should be discarded");
    assert_eq!(count_pending(&conn).unwrap(), 0);

    let exhausted_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?1",
            params![naming::RESOLUTION_PENDING_INBOX_EXHAUSTED],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(exhausted_count, 1, "exhausted entry should be logged once");
}

#[test]
fn enqueue_pending_coalesces_duplicate_envelopes() {
    // re-enqueueing the same envelope identity must
    // increment the existing row's attempt_count, not create a new
    // row. Without UPSERT, a chatty puller that re-delivers a stuck
    // envelope hundreds of times would defeat MAX_PENDING_INBOX_ATTEMPTS.
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-coalesce");

    for _ in 0..5 {
        enqueue_pending(
            &conn,
            &env,
            naming::RESOLUTION_FK_UNRESOLVED,
            Some(naming::ENTITY_TASK),
            Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
        )
        .unwrap();
    }

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "duplicate enqueues must coalesce");
    assert_eq!(
        pending[0].attempt_count, 5,
        "each duplicate enqueue increments the existing row"
    );
}

#[test]
fn enqueue_deferred_schema_too_new_does_not_exhaust_retry_budget() {
    let conn = test_db();
    let mut env = make_envelope(naming::ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-00000000f001");
    env.payload_schema_version = lorvex_domain::version::PAYLOAD_SCHEMA_VERSION + 2;
    let reason = DeferralReason::SchemaTooNew {
        remote_version: env.payload_schema_version,
        local_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
    };

    for _ in 0..(MAX_PENDING_INBOX_ATTEMPTS + 5) {
        enqueue_deferred(&conn, &env, &reason).unwrap();
    }

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "schema-too-new row must be retained");
    assert_eq!(
        pending[0].attempt_count, 1,
        "future-schema rows wait for app upgrade; duplicate delivery must not consume poison retries"
    );

    let exhausted_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?1",
            params![naming::RESOLUTION_PENDING_INBOX_EXHAUSTED],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        exhausted_count, 0,
        "future-schema rows must not be conflict-logged as exhausted poison"
    );
}

#[test]
fn enqueue_pending_distinguishes_envelopes_by_version() {
    // A different version of the same entity is a different envelope
    // and must occupy its own row — versions are HLC-stamped and
    // each represents a distinct change to coalesce on identity, not
    // entity alone.
    let conn = test_db();
    let mut env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-multi");
    enqueue_pending(&conn, &env, naming::RESOLUTION_FK_UNRESOLVED, None, None).unwrap();

    env.version = lorvex_domain::hlc::Hlc::parse("1711234999999_0001_deadbeefdeadbeef")
        .expect("test fixture version must be a canonical HLC");
    enqueue_pending(&conn, &env, naming::RESOLUTION_FK_UNRESOLVED, None, None).unwrap();

    assert_eq!(count_pending(&conn).unwrap(), 2);
}

#[test]
fn drain_deferred_schema_too_new_does_not_discard_at_attempt_cap() {
    let conn = test_db();
    let mut env = make_envelope(naming::ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-00000000f002");
    env.payload_schema_version = lorvex_domain::version::PAYLOAD_SCHEMA_VERSION + 2;
    let reason = DeferralReason::SchemaTooNew {
        remote_version: env.payload_schema_version,
        local_version: lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
    };
    enqueue_deferred(&conn, &env, &reason).unwrap();
    conn.execute(
        "UPDATE sync_pending_inbox SET attempt_count = ?1",
        params![MAX_PENDING_INBOX_ATTEMPTS - 1],
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.discarded, 0);
    assert_eq!(count_pending(&conn).unwrap(), 1);

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(
        pending[0].attempt_count,
        MAX_PENDING_INBOX_ATTEMPTS - 1,
        "schema-too-new drain retries must not consume the poison retry budget"
    );
}

#[test]
fn drain_keeps_entry_below_attempt_cap() {
    // Sanity check: an entry that hasn't reached the cap yet should
    // stay in the inbox after a failed drain.
    let conn = test_db();
    let env = make_reminder_envelope_with_missing_task(
        "reminder-still-trying",
        "01966a3f-7c8b-7d4e-8f3a-000000002189",
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.discarded, 0);
    assert_eq!(count_pending(&conn).unwrap(), 1);

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(
        pending[0].attempt_count, 2,
        "attempt_count should increment"
    );
}

/// a permanently-erroring envelope
/// (one that triggers `apply_envelope` to return `Err(_)` on every
/// drain pass) MUST be discarded once it crosses
/// `MAX_PENDING_INBOX_ATTEMPTS`. Pre-fix, the Err branch only
/// recorded a reattempt and re-logged to error_logs every cycle,
/// leaving the entry in the table for the full
/// FULL_RESYNC_HORIZON_DAYS (90 days). The poison-pill regression
/// re-introduced exactly the failure mode that audit R24 / #2582
/// closed for the Ok(Deferred) branch.
///
/// We trigger the Err branch by seeding a tombstone-redirect
/// cycle (A→B, B→A) on the entity, then enqueueing an envelope
/// targeting A. `apply_envelope` follows the redirect chain,
/// detects the cycle, and returns
/// `ApplyError::TombstoneRedirectCycle` — the canonical
/// "permanently bad envelope" shape. Without the H2 fix, the
/// resulting Err branch increments attempt_count without
/// discarding, and the same envelope re-errors on every drain
/// for 90 days.
#[test]
fn drain_discards_permanently_erroring_entry_after_attempt_cap() {
    let conn = test_db();

    // Set up a tombstone-redirect cycle. Both rows must lex-sort
    // strictly above the envelope's HLC so `create_tombstone`'s
    // `excluded.version > version` guard accepts both inserts.
    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002177",
        "9999999999999_0001_cyclebee",
        "2026-04-19T08:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002178"),
        Some(naming::ENTITY_TASK),
    )
    .unwrap();
    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002178",
        "9999999999999_0002_cyclebee",
        "2026-04-19T08:00:01.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002177"),
        Some(naming::ENTITY_TASK),
    )
    .unwrap();

    let envelope_json = serde_json::to_string(&SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002177".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        // Minimal valid task payload — apply_envelope reaches the
        // tombstone-redirect chase BEFORE deserializing the
        // payload, so we don't need a full task here.
        payload:
            r#"{"title":"poison","status":"open","defer_count":0,"created_at":"","updated_at":""}"#
                .to_string(),
        device_id: "device-001".to_string(),
    })
    .unwrap();
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (
            ?1, ?2, NULL, NULL,
            ?3, '01966a3f-7c8b-7d4e-8f3a-000000002177',
            '1711234567890_0000_a1b2c3d4a1b2c3d4',
            '2026-04-19T08:00:00.000Z',
            '2026-04-19T08:00:00.000Z',
            ?4
         )",
        params![
            envelope_json,
            naming::RESOLUTION_FK_UNRESOLVED,
            naming::ENTITY_TASK,
            MAX_PENDING_INBOX_ATTEMPTS - 1,
        ],
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(
        summary.errors, 1,
        "permanently-erroring envelope should be counted as an error"
    );
    assert_eq!(
        summary.discarded, 1,
        "entry at cap MUST be discarded — closes #2937-H2 poison-pill"
    );
    assert_eq!(
        count_pending(&conn).unwrap(),
        0,
        "stuck entry must be removed from sync_pending_inbox"
    );

    let exhausted_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?1",
            params![naming::RESOLUTION_PENDING_INBOX_EXHAUSTED],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        exhausted_count, 1,
        "discard from Err branch must log a RESOLUTION_PENDING_INBOX_EXHAUSTED conflict"
    );
}
