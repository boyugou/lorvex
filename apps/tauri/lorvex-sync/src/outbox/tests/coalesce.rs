use super::*;

#[test]
fn enqueue_coalesced_replaces_existing() {
    let conn = test_db();
    let env1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let mut env2 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
    );
    env2.payload = r#"{"title":"updated"}"#.to_string();

    enqueue(&conn, &env1).unwrap();
    let replaced = enqueue_coalesced(&conn, &env2).unwrap();
    assert!(
        replaced.is_some(),
        "a newer envelope replaces the queued row and returns the new id"
    );

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "coalesce should result in single entry");
    assert_eq!(
        pending[0].envelope.version.to_string(),
        "1711234567891_0000_a1b2c3d4a1b2c3d4"
    );
    assert_eq!(pending[0].envelope.payload, r#"{"title":"updated"}"#);
}

// the two integration tests that
// poisoned a sync_outbox row with an unknown operation string
// have been retired — the schema's CHECK constraint on
// `operation` blocks the poison INSERT at the DB layer, so the
// quarantine / error_logs code paths are now unreachable through
// normal writes. The discipline the tests pinned is preserved by
// (a) the DB CHECK itself, and (b) the
// decode_sync_operation_rejects_unknown_strings unit test above
// which still verifies the defensive in-code decoder.

#[test]
fn enqueue_coalesced_rejects_stale_snapshot() {
    // A stale-snapshot enqueue must not overwrite a queued newer-HLC
    // envelope: the coalescer preserves the existing row completely
    // untouched and returns `None` so the caller knows nothing was
    // queued.
    let conn = test_db();
    let newer = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
    );
    let mut stale = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    stale.payload = r#"{"title":"stale"}"#.to_string();

    enqueue(&conn, &newer).unwrap();
    let outcome = enqueue_coalesced(&conn, &stale).unwrap();
    assert!(
        outcome.is_none(),
        "a stale incoming envelope is a no-op returning None",
    );

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "exactly one row remains");
    assert_eq!(
        pending[0].envelope.version.to_string(),
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
        "newer envelope must survive",
    );
    assert_eq!(
        pending[0].envelope.payload, newer.payload,
        "existing row payload must be preserved untouched",
    );
}

#[test]
fn enqueue_coalesced_identical_version_is_noop() {
    // Equal version is treated as stale (strictly-greater required) —
    // an identical-HLC duplicate must not shuffle or rewrite the
    // queued row.
    let conn = test_db();
    let env1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let env2 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env1).unwrap();
    let outcome = enqueue_coalesced(&conn, &env2).unwrap();
    assert!(
        outcome.is_none(),
        "identical version is a no-op returning None"
    );
    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].envelope.version, env1.version);
}

// pre-flip a `enqueue_coalesced_refuses_tainted_incoming_version`
// test asserted that an unparseable INCOMING `version: String` was refused
// with `OutboxError::TaintedVersion`. With the wire-boundary flip
// (`SyncEnvelope.version: Hlc`), a tainted incoming envelope is structurally
// unrepresentable — the typed field can no longer hold the malformed
// string in the first place, and serde rejects malformed envelopes at
// the deserialize edge before they reach the outbox. The corresponding
// taint-rejection invariant is now enforced upstream by
// `Hlc::parse`/serde, not by the outbox.

#[test]
fn enqueue_coalesced_canonical_replaces_tainted_existing() {
    // a canonical incoming version paired with a tainted
    // *existing* row (a corrupted-DB scenario surviving from a
    // pre-typed deployment) must replace the predecessor — the
    // existing row was already tainted so the LWW gate has no
    // canonical basis to keep it. The wire-boundary `Hlc` typing
    // makes it impossible to author a tainted envelope through the
    // typed `make_envelope` helper; simulate the corrupted predecessor
    // by inserting it directly via SQL, bypassing the typed enqueue
    // path. The downstream `enqueue_coalesced` LWW arm
    // `(existing_parse = Err)` is the surface this test still pins.
    let conn = test_db();
    let now = lorvex_domain::sync_timestamp_now();
    conn.execute(
        "INSERT INTO sync_outbox
            (entity_type, entity_id, operation, version,
             payload_schema_version, payload, device_id, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        rusqlite::params![
            "task",
            "01966a3f-7c8b-7d4e-8f3a-0000000021a3",
            lorvex_domain::naming::OP_UPSERT,
            "seed",
            1,
            r#"{"title":"test"}"#,
            "device-001",
            now,
        ],
    )
    .expect("seed tainted predecessor row");

    let canonical = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-0000000021a3",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue_coalesced(&conn, &canonical).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].envelope.version, canonical.version);
}

#[test]
fn enqueue_coalesced_does_not_affect_different_entity() {
    let conn = test_db();
    let env1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let env2 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002164",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
    );

    enqueue(&conn, &env1).unwrap();
    enqueue_coalesced(&conn, &env2).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 2, "different entities should both remain");
}

#[test]
fn enqueue_coalesced_preserves_synced_entries() {
    let conn = test_db();
    let env1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env1).unwrap();

    let pending = get_pending(&conn).unwrap();
    mark_synced(&conn, pending[0].id, "2026-03-23T12:00:00.000Z").unwrap();

    // Coalesce should not touch the synced entry.
    let env2 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue_coalesced(&conn, &env2).unwrap();

    // Should have 2 entries total: one synced, one pending.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 2);

    let pending_after = get_pending(&conn).unwrap();
    assert_eq!(pending_after.len(), 1);
    assert_eq!(
        pending_after[0].envelope.version.to_string(),
        "1711234567891_0000_a1b2c3d4a1b2c3d4"
    );
}
