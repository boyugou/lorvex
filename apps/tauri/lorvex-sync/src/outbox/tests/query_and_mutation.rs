use super::*;

#[test]
fn enqueue_and_get_pending() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );

    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(
        pending[0].envelope.entity_type,
        lorvex_domain::naming::EntityKind::Task
    );
    assert_eq!(
        pending[0].envelope.entity_id,
        "01966a3f-7c8b-7d4e-8f3a-000000002163"
    );
    assert_eq!(
        pending[0].envelope.version.to_string(),
        "1711234567890_0000_a1b2c3d4a1b2c3d4"
    );
    assert!(pending[0].synced_at.is_none());
    assert_eq!(pending[0].retry_count, 0);
}

#[test]
fn retain_still_dispatchable_drops_rows_deleted_after_snapshot() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002194",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "fixture should expose one pending row");

    // A concurrent writer removed the row after this batch was read.
    delete_entry(&conn, pending[0].id).unwrap();

    let refreshed = retain_still_dispatchable(&conn, pending).unwrap();
    assert!(
        refreshed.is_empty(),
        "deleted row must not stay dispatchable"
    );
}

#[test]
fn retain_still_dispatchable_drops_rows_marked_synced_after_snapshot() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-0000000021a0",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "fixture should expose one pending row");

    mark_synced(&conn, pending[0].id, "2026-04-19T00:00:00.000Z").unwrap();

    let refreshed = retain_still_dispatchable(&conn, pending).unwrap();
    assert!(
        refreshed.is_empty(),
        "row already marked synced must not be dispatched again"
    );
}

#[test]
fn retain_still_dispatchable_preserves_original_fifo_order() {
    let conn = test_db();
    let first = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002182",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let second = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002198",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
    );
    let third = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-0000000021a1",
        "1711234567892_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &first).unwrap();
    enqueue(&conn, &second).unwrap();
    enqueue(&conn, &third).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 3, "fixture should expose three pending rows");

    // Drop the last row out from under the batch, then confirm the
    // surviving rows keep their original FIFO order.
    delete_entry(&conn, pending[2].id).unwrap();

    let refreshed = retain_still_dispatchable(&conn, pending).unwrap();
    let entity_ids: Vec<String> = refreshed
        .iter()
        .map(|entry| entry.envelope.entity_id.clone())
        .collect();
    assert_eq!(
        entity_ids,
        vec![
            "01966a3f-7c8b-7d4e-8f3a-000000002182".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000002198".to_string()
        ],
        "surviving rows must keep original FIFO order"
    );
}

#[test]
fn reset_retry_counts_for_transport_switch_resurrects_quarantined_but_not_structurally_poisoned_rows(
) {
    // a row that accumulated `retry_count = MAX_RETRIES - 1`
    // under a flaky transport should get a fresh budget after the user
    // flips to a different transport. Rows whose `retry_count` was
    // bumped all the way to `MAX_RETRIES` by the decode-poison path
    // (structurally malformed, not transport-failure) must stay
    // quarantined regardless.
    let conn = test_db();
    let transport_casualty = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002183",
        "1711234567890_0001_a1b2c3d4a1b2c3d4",
    );
    let structural_poison = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002172",
        "1711234567890_0002_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &transport_casualty).unwrap();
    enqueue(&conn, &structural_poison).unwrap();

    // Simulate: transport_casualty failed 9 times (close to but not
    // at the cap), structural_poison was bumped to MAX by the
    // decode-poison path.
    conn.execute(
        "UPDATE sync_outbox SET retry_count = ?1 WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002183'",
        rusqlite::params![MAX_RETRIES - 1],
    )
    .unwrap();
    conn.execute(
        "UPDATE sync_outbox SET retry_count = ?1 WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002172'",
        rusqlite::params![MAX_RETRIES],
    )
    .unwrap();

    let reset = reset_retry_counts_for_transport_switch(&conn).unwrap();
    assert_eq!(reset, 1, "only the below-MAX row must be reset");

    let flaky_count: i64 = conn
        .query_row(
            "SELECT retry_count FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002183'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(flaky_count, 0, "transport casualty must get a fresh budget");

    let bad_count: i64 = conn
        .query_row(
            "SELECT retry_count FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002172'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        bad_count, MAX_RETRIES,
        "structurally-poisoned row must stay quarantined"
    );
}

#[test]
fn enqueue_delete_operation() {
    let conn = test_db();
    let env = make_delete_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );

    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].envelope.operation, SyncOperation::Delete);
}

#[test]
fn decode_sync_operation_rejects_unknown_strings() {
    // the schema's CHECK constraint on
    // `sync_outbox.operation` means an unknown value can't
    // reach the DB through normal writes. `decode_sync_operation`
    // stays as defense-in-depth for the theoretical corruption
    // path (raw file tamper, SQLite internal failure). Pin the
    // decode discipline with a direct unit test instead of the
    // older integration test that had to bypass the CHECK via
    // raw INSERT.
    assert!(matches!(
        super::decode_sync_operation("upsert", 3),
        Ok(SyncOperation::Upsert)
    ));
    assert!(matches!(
        super::decode_sync_operation("delete", 3),
        Ok(SyncOperation::Delete)
    ));
    let err = super::decode_sync_operation("merge", 3).expect_err("unknown op must be an Err");
    let msg = err.to_string();
    assert!(
        msg.contains("invalid sync_outbox operation"),
        "expected invalid-op message, got: {msg}",
    );
}

#[test]
fn mark_synced_removes_from_pending() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);

    mark_synced(&conn, pending[0].id, "2026-03-23T12:00:00.000Z").unwrap();

    let pending_after = get_pending(&conn).unwrap();
    assert!(pending_after.is_empty());
}

#[test]
fn mark_synced_clears_last_error() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002196",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    conn.execute(
        "UPDATE sync_outbox SET last_error = ?1, retry_count = ?2 WHERE id = ?3",
        rusqlite::params!["Permission denied", 3i64, id],
    )
    .unwrap();

    mark_synced(&conn, id, "2026-03-23T12:00:00.000Z").unwrap();

    let (synced_at, last_error, retry_count): (Option<String>, Option<String>, i64) = conn
        .query_row(
            "SELECT synced_at, last_error, retry_count FROM sync_outbox WHERE id = ?1",
            rusqlite::params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(
        synced_at.as_deref(),
        Some("2026-03-23T12:00:00.000Z"),
        "synced_at must land"
    );
    assert!(
        last_error.is_none(),
        "last_error must be NULL after a successful sync, got {last_error:?}"
    );
    assert_eq!(
        retry_count, 3,
        "retry_count is intentionally preserved so post-hoc analysis still sees how many retries the row took"
    );
}

#[test]
fn mark_many_synced_batch_marks_all_given_ids_in_one_pass() {
    let conn = test_db();
    for i in 0..5 {
        let env = make_envelope(
            "task",
            &format!("01966a3f-7c8b-7d4e-8f3a-000000004{i:03}"),
            &format!("171123456789{i}_0000_a1b2c3d4a1b2c3d4"),
        );
        enqueue(&conn, &env).unwrap();
    }

    let pending: Vec<i64> = get_pending(&conn).unwrap().iter().map(|e| e.id).collect();
    assert_eq!(pending.len(), 5);

    mark_many_synced(&conn, &pending, "2026-03-23T12:00:00.000Z").unwrap();

    assert!(get_pending(&conn).unwrap().is_empty());
}

#[test]
fn mark_many_synced_preserves_existing_synced_at() {
    // carried over to the batched path: a row
    // already marked synced keeps its original synced_at.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000216f",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    mark_synced(&conn, id, "2026-03-23T10:00:00.000Z").unwrap();
    mark_many_synced(&conn, &[id], "2026-03-23T12:00:00.000Z").unwrap();

    let later: String = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        later, "2026-03-23T10:00:00.000Z",
        "existing synced_at must not be overwritten"
    );
}

#[test]
fn mark_many_synced_empty_slice_is_noop() {
    let conn = test_db();
    mark_many_synced(&conn, &[], "2026-03-23T12:00:00.000Z").unwrap();
}

/// when a row finally lands successfully its
/// historical `last_error` must be wiped — pre-fix the Diagnostics
/// panel rendered stale "Permission denied" / "Network failed"
/// strings forever next to rows that had since synced.
#[test]
fn mark_many_synced_clears_last_error() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002195",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    // Simulate a previous failure leaving last_error set.
    conn.execute(
        "UPDATE sync_outbox SET last_error = ?1, retry_count = ?2 WHERE id = ?3",
        rusqlite::params!["Permission denied", 3i64, id],
    )
    .unwrap();

    mark_many_synced(&conn, &[id], "2026-03-23T12:00:00.000Z").unwrap();

    let (synced_at, last_error, retry_count): (Option<String>, Option<String>, i64) = conn
        .query_row(
            "SELECT synced_at, last_error, retry_count FROM sync_outbox WHERE id = ?1",
            rusqlite::params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(
        synced_at.as_deref(),
        Some("2026-03-23T12:00:00.000Z"),
        "synced_at must land"
    );
    assert!(
        last_error.is_none(),
        "last_error must be NULL after a successful sync, got {last_error:?}"
    );
    assert_eq!(
        retry_count, 3,
        "retry_count is intentionally preserved so post-hoc analysis still sees how many retries the row took"
    );
}
