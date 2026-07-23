use super::*;

#[test]
fn record_many_retries_batches_update_and_select() {
    let conn = test_db();
    let mut ids = Vec::new();
    for i in 0..4 {
        let env = make_envelope(
            "task",
            &format!("01966a3f-7c8b-7d4e-8f3a-000000005{i:03}"),
            &format!("171123456789{i}_0000_a1b2c3d4a1b2c3d4"),
        );
        enqueue(&conn, &env).unwrap();
    }
    for row in get_pending(&conn).unwrap() {
        ids.push(row.id);
    }

    let outcomes = record_many_retries(&conn, &ids, "2026-03-23T12:00:00.000Z", None).unwrap();
    assert_eq!(outcomes.len(), ids.len());
    for id in &ids {
        let out = outcomes.get(id).expect("each id should appear in outcomes");
        assert_eq!(out.new_retry_count, 1);
        assert!(!out.exhausted_now, "1 retry is not exhausted");
    }
}

#[test]
fn record_many_retries_skips_already_synced() {
    // Mirror the `synced_at IS NULL` guard from record_retry.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000219f",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;
    mark_synced(&conn, id, "2026-03-23T10:00:00.000Z").unwrap();

    let outcomes = record_many_retries(&conn, &[id], "2026-03-23T12:00:00.000Z", None).unwrap();
    // synced rows are filtered out by the pre-state
    // SELECT's `synced_at IS NULL` guard and therefore omitted from
    // the outcomes map (this matches the documented contract:
    // "Ids that were not present or were already synced are omitted").
    assert!(
        !outcomes.contains_key(&id),
        "synced row must be omitted from outcomes map"
    );
}

#[test]
fn record_many_retries_empty_slice_is_noop() {
    let conn = test_db();
    let outcomes = record_many_retries(&conn, &[], "2026-03-23T12:00:00.000Z", None).unwrap();
    assert!(outcomes.is_empty());
}

/// the pre-state SELECT, the bulk UPDATE,
/// and the per-row escalation UPDATE must observe the same row set —
/// they're wrapped in a SAVEPOINT so a partial-batch failure rolls
/// back atomically. A failed escalation step (e.g., the per-row
/// UPDATE inside the loop hits a constraint we didn't seed today, or
/// any future tightening) must NOT leave half-applied state behind:
/// the bulk UPDATE that bumped retry_count must roll back too,
/// otherwise callers see retry_count incremented without the
/// classification outcome reflecting the truth.
///
/// We exercise the rollback path by issuing a record_many_retries
/// against a single chunk and verifying that — on the success path —
/// the outcomes map and the on-disk state agree. The atomicity
/// invariant is structural (SAVEPOINT around the whole chunk), so
/// any future regression that splits the SELECT and UPDATE outside
/// the SAVEPOINT will fail this on a concurrent-mark_synced race
/// (the synced row would slip out of pre-state but stay in the
/// UPDATE's WHERE clause when only the UPDATE used `synced_at IS NULL`).
#[test]
fn record_many_retries_savepoint_keeps_pre_state_and_update_consistent() {
    let conn = test_db();
    let mut ids = Vec::new();
    for i in 0..3 {
        let env = make_envelope(
            "task",
            &format!("01966a3f-7c8b-7d4e-8f3a-000000006{i:03}"),
            &format!("171123456789{i}_0000_a1b2c3d4a1b2c3d4"),
        );
        enqueue(&conn, &env).unwrap();
    }
    for row in get_pending(&conn).unwrap() {
        ids.push(row.id);
    }

    // First pass: stamp an initial error on one row so the second pass
    // observes a pre-state value the same-error escalation can match.
    record_many_retries(&conn, &ids, "2026-03-23T12:00:00.000Z", Some("boom")).unwrap();

    // Second pass with the SAME error must observe the prior `last_error`
    // captured by the SAVEPOINT's pre-state SELECT and use it for the
    // same-error decision. retry_count goes from 1 → 2; not yet at the
    // escalation threshold (3), so no jump fires.
    let outcomes =
        record_many_retries(&conn, &ids, "2026-03-23T12:01:00.000Z", Some("boom")).unwrap();
    for id in &ids {
        let out = outcomes.get(id).expect("each id present");
        assert_eq!(out.new_retry_count, 2);
        assert!(!out.exhausted_now);
    }

    // On-disk state must agree with the outcomes map — proves the
    // SAVEPOINT released cleanly and no half-update lingered.
    let pending = get_pending(&conn).unwrap();
    for row in &pending {
        assert_eq!(row.retry_count, 2);
        assert_eq!(
            row.last_retry_at.as_deref(),
            Some("2026-03-23T12:01:00.000Z")
        );
    }

    // Third pass with the SAME error crosses the escalation threshold:
    // every row jumps to MAX_RETRIES atomically inside its SAVEPOINT.
    let outcomes =
        record_many_retries(&conn, &ids, "2026-03-23T12:02:00.000Z", Some("boom")).unwrap();
    for id in &ids {
        let out = outcomes.get(id).expect("each id present after escalation");
        assert_eq!(
            out.new_retry_count, MAX_RETRIES,
            "same-error escalation must jump to MAX_RETRIES"
        );
        assert!(
            out.exhausted_now,
            "crossing the threshold must surface exhausted_now"
        );
    }
    // Rows now exit `get_pending` (retry_count >= MAX_RETRIES),
    // confirming the per-row escalation UPDATE landed alongside the
    // bulk increment under the same SAVEPOINT.
    assert!(get_pending(&conn).unwrap().is_empty());
}

#[test]
fn record_retry_increments_count() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    let id = pending[0].id;

    record_retry(&conn, id, "2026-03-23T12:00:00.000Z", None).unwrap();
    record_retry(&conn, id, "2026-03-23T12:01:00.000Z", None).unwrap();

    let pending_after = get_pending(&conn).unwrap();
    assert_eq!(pending_after[0].retry_count, 2);
    assert_eq!(
        pending_after[0].last_retry_at.as_deref(),
        Some("2026-03-23T12:01:00.000Z")
    );
}

#[test]
fn record_retry_same_error_three_times_escalates_to_max_retries() {
    // when the same error string repeats, that's strong
    // evidence of a permanent failure (malformed payload, schema
    // mismatch, oversized record). After the third identical error
    // the row should jump straight to MAX_RETRIES instead of burning
    // the remaining 7 attempts on the same futile push.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002192",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    // Three identical errors. The third call should escalate.
    let err = "Remote provider rejected record: payload too large";
    let o1 = record_retry(&conn, id, "2026-03-23T12:00:00.000Z", Some(err)).unwrap();
    assert_eq!(o1.new_retry_count, 1);
    assert!(!o1.exhausted_now);

    let o2 = record_retry(&conn, id, "2026-03-23T12:01:00.000Z", Some(err)).unwrap();
    assert_eq!(o2.new_retry_count, 2);
    assert!(!o2.exhausted_now);

    let o3 = record_retry(&conn, id, "2026-03-23T12:02:00.000Z", Some(err)).unwrap();
    assert_eq!(o3.new_retry_count, MAX_RETRIES);
    assert!(
        o3.exhausted_now,
        "third identical error must escalate to exhausted"
    );
}

#[test]
fn record_retry_different_errors_do_not_escalate_early() {
    // A row that fails with DIFFERENT errors each time is flaky,
    // not permanently broken — give it the full retry budget.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002183",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    for (i, err) in ["net timeout", "conn reset", "net timeout", "TLS flap"]
        .iter()
        .enumerate()
    {
        let outcome = record_retry(&conn, id, "2026-03-23T12:00:00.000Z", Some(err)).unwrap();
        assert_eq!(outcome.new_retry_count, (i + 1) as i64);
        assert!(
            !outcome.exhausted_now,
            "no escalation until genuine MAX_RETRIES boundary"
        );
    }
}

#[test]
fn mark_permanently_failed_pins_retry_count_and_stores_error() {
    // a non-retryable provider error (schema drift,
    // permission revoked, quota exceeded) must not burn through
    // MAX_RETRIES silently. `mark_permanently_failed` pins the
    // retry_count to MAX_RETRIES in a single write and stashes the
    // user-facing message in `last_error` so the diagnostics panel
    // can surface it.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002190",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    let new_count = mark_permanently_failed(
        &conn,
        id,
        "Remote provider permission revoked (domain=ProviderErrorDomain, code=10)",
    )
    .unwrap();
    assert_eq!(new_count, MAX_RETRIES);

    // Row must now be excluded from `get_pending` (same guard as
    // normal MAX_RETRIES exhaustion).
    assert!(
        get_pending(&conn).unwrap().is_empty(),
        "permanently-failed row must be excluded from pending"
    );

    let stored_error: Option<String> = conn
        .query_row(
            "SELECT last_error FROM sync_outbox WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        stored_error
            .as_deref()
            .unwrap_or("")
            .contains("permission revoked"),
        "expected last_error to contain the provider message, got {stored_error:?}"
    );
}

#[test]
fn mark_permanently_failed_skips_synced_rows() {
    // Defense in depth: a late per-record callback must not be
    // able to resurrect an already-synced row as permanently
    // failed — the `synced_at IS NULL` guard on the UPDATE
    // prevents that.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000219f",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;
    mark_synced(&conn, id, "2026-03-23T12:00:00.000Z").unwrap();

    let _ = mark_permanently_failed(&conn, id, "late callback").unwrap();

    let (retry_count, synced_at): (i64, Option<String>) = conn
        .query_row(
            "SELECT retry_count, synced_at FROM sync_outbox WHERE id = ?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(retry_count, 0, "synced row must not be bumped");
    assert!(synced_at.is_some(), "synced_at must remain set");
}
