use super::*;

#[test]
fn multiple_enqueues_ordered_fifo() {
    let conn = test_db();
    for i in 0..5 {
        let env = make_envelope(
            "task",
            &format!("01966a3f-7c8b-7d4e-8f3a-000000003{i:03}"),
            &format!("171123456789{i}_0000_a1b2c3d4a1b2c3d4"),
        );
        enqueue(&conn, &env).unwrap();
    }

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 5);
    for (i, entry) in pending.iter().enumerate() {
        assert_eq!(
            entry.envelope.entity_id,
            format!("01966a3f-7c8b-7d4e-8f3a-000000003{i:03}")
        );
    }
}

#[test]
fn gc_synced_deletes_old_entries() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    // Mark as synced with a very old timestamp.
    mark_synced(&conn, pending[0].id, "2020-01-01T00:00:00.000Z").unwrap();

    let deleted = gc_synced(&conn, 1).unwrap();
    assert_eq!(deleted, 1);

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn gc_synced_preserves_recent_entries() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    // Mark as synced with current-ish timestamp (the default created_at is now).
    mark_synced(&conn, pending[0].id, "2099-01-01T00:00:00.000Z").unwrap();

    let deleted = gc_synced(&conn, 1).unwrap();
    assert_eq!(deleted, 0, "recently synced entries should not be GC'd");
}

#[test]
fn gc_synced_preserves_unsynced_entries() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let deleted = gc_synced(&conn, 0).unwrap();
    assert_eq!(deleted, 0, "unsynced entries should not be GC'd");
}

#[test]
fn gc_synced_reaps_exhausted_retry_entries_past_retention() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let id = get_pending(&conn).unwrap()[0].id;
    // Drive the entry into the "permanently failed" terminal state by
    // bumping retry_count to the MAX_RETRIES ceiling, stamping a
    // `last_error` (the M3 surfacing gate), and backdating its
    // creation stamp past the retention window.
    conn.execute(
        "UPDATE sync_outbox \
         SET retry_count = ?1, \
             last_error = 'permanent: schema mismatch', \
             created_at = '2020-01-01T00:00:00.000Z' \
         WHERE id = ?2",
        params![MAX_RETRIES, id],
    )
    .unwrap();

    let deleted = gc_synced(&conn, 1).unwrap();
    assert_eq!(
        deleted, 1,
        "exhausted-retry entries past retention should be GC'd"
    );

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn gc_synced_preserves_exhausted_retry_entries_within_retention() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let id = get_pending(&conn).unwrap()[0].id;
    // retry_count is at the ceiling but the entry was created just now,
    // so the retention window hasn't elapsed.
    conn.execute(
        "UPDATE sync_outbox SET retry_count = ?1, last_error = 'transient' WHERE id = ?2",
        params![MAX_RETRIES, id],
    )
    .unwrap();

    let deleted = gc_synced(&conn, 1).unwrap();
    assert_eq!(
        deleted, 0,
        "freshly-created exhausted-retry entries should be preserved until retention elapses"
    );
}

/// a row that crossed `MAX_RETRIES` past
/// the retention window WITHOUT a stamped `last_error` (the surfacing
/// gate) MUST survive the GC. Pre-fix, the retention sweep deleted
/// any unsynced row at the cap regardless of whether the user had
/// been shown a diagnostic — so a same-error escalation that crashed
/// before stamping `last_error`, or a future code path that bumps
/// `retry_count` to the cap without persisting an error message,
/// would silently disappear after the retention horizon.
#[test]
fn gc_synced_preserves_exhausted_entries_with_no_last_error() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000218b",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let id = get_pending(&conn).unwrap()[0].id;
    // Cap is reached, creation is past the retention window — but
    // `last_error` is left NULL, simulating a path where the failure
    // was never surfaced.
    conn.execute(
        "UPDATE sync_outbox SET retry_count = ?1, created_at = '2020-01-01T00:00:00.000Z' WHERE id = ?2",
        params![MAX_RETRIES, id],
    )
    .unwrap();

    let deleted = gc_synced(&conn, 1).unwrap();
    assert_eq!(
        deleted, 0,
        "rows missing `last_error` must survive the permanent-failure GC"
    );
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn reset_row_retry_count_revives_quarantined_row() {
    // a single row at MAX_RETRIES can be targeted by
    // the per-row reset helper, restoring it to the pending queue.
    // `last_error` is also cleared so the diagnostics surface shows
    // a clean slate for the next push.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002181",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;

    // Drive the row into permanent-failure state with a lingering
    // last_error, exactly as a real transport failure would.
    conn.execute(
        "UPDATE sync_outbox SET retry_count = ?1, last_retry_at = ?2, last_error = ?3 \
         WHERE id = ?4",
        rusqlite::params![
            MAX_RETRIES,
            "2026-03-23T12:00:00.000Z",
            "Remote provider rejected record: payload too large",
            id,
        ],
    )
    .unwrap();

    assert!(
        get_pending(&conn).unwrap().is_empty(),
        "row above MAX_RETRIES must not be pending",
    );

    let updated = reset_row_retry_count(&conn, id).unwrap();
    assert!(updated, "reset must report that it changed a row");

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "reset row must return to pending queue");
    assert_eq!(pending[0].retry_count, 0);
    assert!(pending[0].last_retry_at.is_none());

    let last_error: Option<String> = conn
        .query_row(
            "SELECT last_error FROM sync_outbox WHERE id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        last_error.is_none(),
        "last_error must be cleared so diagnostics show a clean slate",
    );
}

#[test]
fn reset_row_retry_count_does_not_resurrect_synced_row() {
    // A row that has already been pushed must never be moved back
    // into the pending queue by a per-row reset — that would cause
    // a duplicate push of an already-accepted envelope.
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-00000000219f",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();
    let id = get_pending(&conn).unwrap()[0].id;
    mark_synced(&conn, id, "2026-03-23T12:00:00.000Z").unwrap();

    let updated = reset_row_retry_count(&conn, id).unwrap();
    assert!(!updated, "synced row must not be updated by per-row reset");

    // Confirm synced_at survives and no pending row appears.
    let synced_at: Option<String> = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(synced_at.as_deref(), Some("2026-03-23T12:00:00.000Z"));
    assert!(get_pending(&conn).unwrap().is_empty());
}
