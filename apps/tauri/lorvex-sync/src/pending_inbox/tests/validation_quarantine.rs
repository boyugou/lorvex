use super::super::*;
use super::support::*;

#[test]
fn drain_quarantines_unparseable_envelope_and_continues() {
    // a poisoned pending row (envelope JSON cannot be
    // deserialized, e.g. an `entity_type` retired by a newer build
    // post #3004-H1) used to abort the entire drain via `?` on
    // `parse_envelope`, blocking every subsequent valid pending row
    // from ever being retried — the same poison-pill class fixed
    // for the apply-Err branch in R24. The fix logs to error_logs,
    // bumps `attempt_count` toward the cap, and continues. We
    // assert that a *valid* row queued after the poison row still
    // drains in the same pass.
    let conn = test_db();

    insert_unparseable_pending_row(&conn, naming::ENTITY_TASK_REMINDER, "broken", 1);

    // a valid envelope behind the poison row whose
    // FK target IS already tombstoned with no redirect — the
    // drain will see it, log a fk_unresolved discard, and remove
    // the row. We pick this shape because it requires zero apply
    // pipeline scaffolding (no Task table seeding etc.) yet still
    // exercises a complete drain step against a real envelope.
    let env = make_reminder_envelope_with_missing_task(
        "reminder-after-poison",
        "01966a3f-7c8b-7d4e-8f3a-0000000021a2",
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-0000000021a2"),
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-0000000021a2",
        "1711234999999_0000_deadbeefdeadbeef",
        "2026-03-27T11:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).expect("drain must not abort on poison row");

    // the second row drained cleanly (01966a3f-7c8b-7d4e-8f3a-000000002112 tombstoned with
    // no redirect → discarded as fk_unresolved by the drain's
    // tombstone-handling branch)
    assert_eq!(
        summary.discarded, 1,
        "valid row queued after poison row should still drain"
    );
    // the poison row was counted as an error and is bumped to the
    // attempt cap, ready to be quarantined on the next pass
    assert!(summary.errors >= 1, "poison row should count as error");

    // unparseable diagnostic was written
    let unparseable_logs: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = ?1",
            params!["sync.pending_inbox.unparseable_envelope"],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        unparseable_logs >= 1,
        "expected an unparseable_envelope error_log entry"
    );

    // poison row is still in the inbox but bumped to the cap
    let poison_attempt: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox \
             WHERE envelope_entity_id = 'broken'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        poison_attempt, MAX_PENDING_INBOX_ATTEMPTS,
        "poison row attempt_count should be bumped to the cap"
    );
}

#[test]
fn drain_quarantines_at_cap_unparseable_envelope_to_conflict_log() {
    // when an unparseable row is already at the cap (e.g. a
    // previous drain bumped it), the drain promotes it to a
    // permanent EXHAUSTED conflict_log entry and removes the
    // row — bounding the diagnostic feed and the queue depth.
    let conn = test_db();

    insert_unparseable_pending_row(
        &conn,
        naming::ENTITY_TASK_REMINDER,
        "broken-at-cap",
        MAX_PENDING_INBOX_ATTEMPTS,
    );

    let summary = drain_pending_inbox(&conn).expect("drain must not abort");
    assert_eq!(
        summary.discarded, 1,
        "at-cap unparseable row should be discarded"
    );
    assert_eq!(count_pending(&conn).unwrap(), 0);

    let exhausted_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?1",
            params![naming::RESOLUTION_PENDING_INBOX_EXHAUSTED],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        exhausted_count, 1,
        "at-cap unparseable row should be quarantined to conflict_log"
    );
}

#[test]
fn enqueue_pending_rejects_malformed_payload_json() {
    // Stricter than the old "drain rejects malformed" semantics: a
    // malformed payload is caught at enqueue time, so no DB row is
    // written and every drain cycle is spared the wasted parse. See
    // the defense-in-depth JSON-depth check in `enqueue_pending`.
    let conn = test_db();
    let result = enqueue_pending(
        &conn,
        &SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::TaskReminder,
            entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000214d".to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: 1,
            payload: r#"{"task_id":"01966a3f-7c8b-7d4e-8f3a-000000002188""#.to_string(),
            device_id: "device-001".to_string(),
        },
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000002188"),
    );

    assert!(
        result.is_err(),
        "malformed payload should be rejected at enqueue time"
    );
    assert_eq!(count_pending(&conn).unwrap(), 0);
}

#[test]
fn enqueue_pending_rejects_overly_nested_payload() {
    // Payloads nested deeper than `canonicalize::MAX_JSON_DEPTH` are
    // rejected at enqueue time, matching the guard that outbox writers
    // already enforce.
    let conn = test_db();
    let mut deep = String::new();
    for _ in 0..(crate::canonicalize::MAX_JSON_DEPTH + 2) {
        deep.push_str("{\"x\":");
    }
    deep.push('1');
    for _ in 0..(crate::canonicalize::MAX_JSON_DEPTH + 2) {
        deep.push('}');
    }
    let result = enqueue_pending(
        &conn,
        &SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::Task,
            entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000217b".to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: 1,
            payload: deep,
            device_id: "device-001".to_string(),
        },
        naming::RESOLUTION_FK_UNRESOLVED,
        None,
        None,
    );

    assert!(
        result.is_err(),
        "over-deep payload should be rejected at enqueue time"
    );
    assert_eq!(count_pending(&conn).unwrap(), 0);
}
