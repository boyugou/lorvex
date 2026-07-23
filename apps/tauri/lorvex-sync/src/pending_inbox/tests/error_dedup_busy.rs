use super::super::*;
use super::support::*;

/// a permanently-erroring entry that
/// produces THE SAME error message on every drain cycle must
/// only write a single `error_logs` row across N drain cycles —
/// not N rows. Pre-fix, every drain wrote a duplicate entry,
/// so a stuck poison-pill grew `error_logs` linearly with the
/// retention horizon (90 days × ~24 drains/day = 2160 rows for
/// one stuck envelope).
///
/// We exercise this with the same tombstone-redirect-cycle setup
/// that drives the cap-discard regression test, but we run TWO
/// drain cycles and assert error_logs has exactly one row, not
/// two. The H2 cap-discard fires only on the final drain, so
/// each pre-cap drain re-attempts and would re-log without M5.
#[test]
fn drain_dedups_repeated_error_logs_for_same_failure_message() {
    let conn = test_db();

    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002179",
        "9999999999999_0001_dedupe000",
        "2026-04-19T08:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-00000000217a"),
        Some(naming::ENTITY_TASK),
    )
    .unwrap();
    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-00000000217a",
        "9999999999999_0002_dedupe000",
        "2026-04-19T08:00:01.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002179"),
        Some(naming::ENTITY_TASK),
    )
    .unwrap();

    let envelope_json = serde_json::to_string(&SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002179".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload:
            r#"{"title":"poison","status":"open","defer_count":0,"created_at":"","updated_at":""}"#
                .to_string(),
        device_id: "device-001".to_string(),
    })
    .unwrap();
    // Seed at attempt_count = 1 so the cap-discard branch (which
    // fires at MAX_PENDING_INBOX_ATTEMPTS) does NOT trip during
    // the two drain cycles below — we want to observe the
    // dedup behavior across attempts well before the cap.
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (
            ?1, ?2, NULL, NULL,
            ?3, '01966a3f-7c8b-7d4e-8f3a-000000002179',
            '1711234567890_0000_a1b2c3d4a1b2c3d4',
            '2026-04-19T08:00:00.000Z',
            '2026-04-19T08:00:00.000Z',
            1
         )",
        params![
            envelope_json,
            naming::RESOLUTION_FK_UNRESOLVED,
            naming::ENTITY_TASK
        ],
    )
    .unwrap();

    // First drain — should log once.
    drain_pending_inbox(&conn).unwrap();
    let after_first: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.pending_inbox'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(after_first, 1, "first drain must log the error once");

    // Second drain with the SAME poison pill must NOT add a
    // duplicate row — the M5 dedup compares the new error string
    // to `last_error` and skips the log when they match.
    drain_pending_inbox(&conn).unwrap();
    let after_second: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.pending_inbox'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        after_second, 1,
        "repeated identical errors must not accumulate error_logs rows — dedup gap regressed"
    );

    // The pending entry's attempt_count must still have advanced
    // (dedup affects logging, not retry bookkeeping).
    let attempt_count: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox LIMIT 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        attempt_count, 3,
        "attempt_count must increment on every drain regardless of dedup"
    );
}

/// a transient `SQLITE_BUSY` / `SQLITE_LOCKED`
/// error during pending inbox drain must NOT bump
/// `attempt_count`. The classifier inspects the underlying
/// SQLite error code and routes the recoverable class through
/// `record_reattempt_busy`, which only bumps
/// `last_attempted_at`. Pre-fix the Err branch always called
/// `record_reattempt_with_error`, so a queue full of legitimate
/// envelopes hammered by concurrent writes could exhaust their
/// 50-attempt budget and discard rows that had never actually
/// run the apply handler.
#[test]
fn busy_or_locked_apply_failure_does_not_bump_attempt_count() {
    // Synthetic ApplyError variants representing the two
    // transient SQLite error codes the classifier recognizes.
    let busy = ApplyError::Db(rusqlite::Error::SqliteFailure(
        rusqlite::ffi::Error {
            code: rusqlite::ErrorCode::DatabaseBusy,
            extended_code: 5,
        },
        Some("database is locked".to_string()),
    ));
    let locked = ApplyError::Db(rusqlite::Error::SqliteFailure(
        rusqlite::ffi::Error {
            code: rusqlite::ErrorCode::DatabaseLocked,
            extended_code: 6,
        },
        Some("database table is locked".to_string()),
    ));
    // Sentinel: a permanent failure class must NOT be classified
    // as transient. Pick something the classifier should reject.
    let permanent = ApplyError::InvalidPayload("bad".to_string());

    assert!(
        is_transient_busy_or_locked(&busy),
        "SQLITE_BUSY must classify as transient"
    );
    assert!(
        is_transient_busy_or_locked(&locked),
        "SQLITE_LOCKED must classify as transient"
    );
    assert!(
        !is_transient_busy_or_locked(&permanent),
        "InvalidPayload must NOT classify as transient"
    );

    // End-to-end: enqueue an entry, then call
    // `record_reattempt_busy` and verify the attempt_count stays
    // pinned while `last_attempted_at` advances.
    let conn = test_db();
    let env = make_envelope(naming::ENTITY_TASK_REMINDER, "reminder-busy");
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002189"),
    )
    .unwrap();

    let initial: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox LIMIT 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    let initial_ts: String = conn
        .query_row(
            "SELECT last_attempted_at FROM sync_pending_inbox LIMIT 1",
            [],
            |r| r.get(0),
        )
        .unwrap();

    // Sleep just long enough for the millisecond-precision
    // `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` to advance.
    //
    // 5ms was right at the edge of the Windows
    // scheduler tick (15.6ms) and produced flakes on CI runners
    // that scheduled the test thread late. 25ms is comfortably
    // above the tick budget on every supported platform (macOS:
    // 1ms, Linux: 1ms, Windows: 15.6ms) while still keeping the
    // test fast.
    const TIMESTAMP_ADVANCE_GUARD_MS: u64 = 25;
    std::thread::sleep(std::time::Duration::from_millis(TIMESTAMP_ADVANCE_GUARD_MS));

    let entry_id: i64 = conn
        .query_row("SELECT id FROM sync_pending_inbox LIMIT 1", [], |r| {
            r.get(0)
        })
        .unwrap();
    record_reattempt_busy(&conn, entry_id).unwrap();

    let after: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox WHERE id = ?1",
            params![entry_id],
            |r| r.get(0),
        )
        .unwrap();
    let after_ts: String = conn
        .query_row(
            "SELECT last_attempted_at FROM sync_pending_inbox WHERE id = ?1",
            params![entry_id],
            |r| r.get(0),
        )
        .unwrap();

    assert_eq!(after, initial, "transient busy must NOT bump attempt_count");
    assert!(
        after_ts > initial_ts,
        "transient busy must still advance last_attempted_at \
         (before: {initial_ts}, after: {after_ts})"
    );
}
