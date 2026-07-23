use super::*;

/// the coalesce LWW guard must compare
/// versions with the typed `Hlc::parse` ordering, not raw byte
/// compare. The byte compare yields the same answer for canonical
/// HLCs (fixed-width lex-ordered) but a malformed legacy version
/// could trip a silent miscoalesce. This test pins the typed-HLC
/// ordering for the production case (canonical strings).
#[test]
fn coalesce_uses_typed_hlc_compare_for_lww() {
    let conn = test_db();
    // Newer HLC by physical-ms component lands first.
    let env_newer = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002186",
        "1711234567899_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue_coalesced(&conn, &env_newer).unwrap();

    // Older HLC must lose the coalesce comparison even though
    // string-wise the suffix differs (typed compare collapses
    // suffix to a tiebreak after physical_ms + counter). The suffix
    // here is a valid 16-char lowercase-hex value — M3
    // refuses envelopes whose `version` fails `Hlc::parse`, so the
    // test must use a canonically-shaped suffix to exercise the
    // typed-compare branch (not the boundary refusal).
    let env_older = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002186",
        "1711234567890_0000_ffffffffffffffff",
    );
    enqueue_coalesced(&conn, &env_older).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT version FROM sync_outbox \
             WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002186' AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, "1711234567899_0000_a1b2c3d4a1b2c3d4",
        "typed HLC compare must keep the newer envelope, even when the older \
         envelope has a lexicographically-larger suffix"
    );

    // Reverse order: an even newer envelope replaces the existing.
    let env_newest = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002186",
        "1711234567999_0000_0000000000000000",
    );
    enqueue_coalesced(&conn, &env_newest).unwrap();
    let stored: String = conn
        .query_row(
            "SELECT version FROM sync_outbox \
             WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002186' AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "1711234567999_0000_0000000000000000");
}

/// every enqueue surface MUST refuse a
/// malformed envelope. Pre-fix, `enqueue` and
/// `enqueue_coalesced` skipped `envelope.validate()` and
/// relied on every in-process caller to validate up-front; a future
/// audit / re-emit utility loading raw bytes off disk would otherwise
/// land an oversized or path-traversal envelope straight in the
/// outbox where remote-provider / filesystem-bridge push then exposes it to
/// peers.
#[test]
fn enqueue_rejects_envelope_with_path_traversal_entity_id() {
    let conn = test_db();
    let mut env = make_envelope("task", "ok", "1711234567890_0000_a1b2c3d4a1b2c3d4");
    env.entity_id = "../etc/passwd".to_string();

    let result = enqueue(&conn, &env);
    assert!(
        result.is_err(),
        "enqueue must reject path-traversal entity_id"
    );
}

#[test]
fn enqueue_coalesced_rejects_envelope_with_oversized_payload() {
    use crate::envelope::MAX_ENVELOPE_PAYLOAD_BYTES;
    let conn = test_db();
    let mut env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002173",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload = "x".repeat(MAX_ENVELOPE_PAYLOAD_BYTES + 1);

    let result = enqueue_coalesced(&conn, &env);
    assert!(
        result.is_err(),
        "coalesced enqueue must reject oversized payload"
    );
    let pending = get_pending(&conn).unwrap();
    assert!(
        pending.is_empty(),
        "no row may land in the outbox after a rejected enqueue"
    );
}

/// when the body's INSERT hits a
/// UNIQUE constraint violation (the partial index
/// `idx_sync_outbox_unsynced_per_entity` fires when a racing
/// writer landed a row between our SELECT and INSERT), the
/// per-attempt SAVEPOINT must roll back the prior row's DELETE
/// so the second attempt's SELECT still sees the racing row and
/// the original queued envelope is never lost.
///
/// We simulate the race with an AFTER-DELETE trigger that
/// re-injects a phantom unsynced row right after the body's
/// DELETE runs — guaranteed to make the body's INSERT collide.
#[test]
fn coalesce_savepoint_preserves_racing_row_on_unique_conflict() {
    let conn = test_db();
    let v_old = "1711234567890_0000_a1b2c3d4a1b2c3d4";
    let v_new = "1711234567999_0000_a1b2c3d4a1b2c3d4";
    let env_old = make_envelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002185", v_old);

    // Seed the original unsynced row. This is what the body should
    // observe on its FIRST attempt's SELECT.
    enqueue_coalesced(&conn, &env_old).unwrap();

    // Install a permanent AFTER-DELETE trigger that re-inserts a
    // phantom row matching the partial UNIQUE index whenever the
    // body's DELETE fires. The trigger's INSERT runs inside the
    // attempt's SAVEPOINT, so when the body's INSERT then collides
    // with SQLITE_CONSTRAINT_UNIQUE the SAVEPOINT must roll back
    // BOTH the body's DELETE and the trigger's INSERT — leaving
    // the original seeded row intact for the next attempt's
    // SELECT to observe again.
    conn.execute_batch(
        "CREATE TEMP TRIGGER h7_force_unique
         AFTER DELETE ON sync_outbox
         WHEN OLD.synced_at IS NULL
         BEGIN
            INSERT INTO sync_outbox
                (entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id, created_at)
            VALUES (OLD.entity_type, OLD.entity_id, OLD.operation, OLD.version,
                    OLD.payload_schema_version, OLD.payload, OLD.device_id, OLD.created_at);
         END;",
    )
    .unwrap();

    // The trigger forces a UNIQUE conflict on every attempt, so
    // the bounded retry MAX_CONFLICT_RETRIES exhausts and the
    // helper returns Err. The PROPERTY we assert is that even
    // after retry exhaustion, the original seeded row still
    // sits in the outbox with its version INTACT — which is only
    // possible if every attempt's SAVEPOINT rolled back the body's
    // DELETE.
    let env_new = make_envelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002185", v_new);
    let result = enqueue_coalesced(&conn, &env_new);
    assert!(
        result.is_err(),
        "retry exhaustion under a forced UNIQUE conflict must surface as Err"
    );

    // Disarm the trigger so the post-condition queries don't
    // recurse into it.
    conn.execute_batch("DROP TRIGGER h7_force_unique").unwrap();

    // Critical: the original row must STILL be present with its
    // original version — every attempt's SAVEPOINT rolled back the
    // body's DELETE, keeping the seeded row alive across retry
    // exhaustion.
    let rows: Vec<String> = conn
        .prepare(
            "SELECT version FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002185' \
             AND synced_at IS NULL",
        )
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        rows.len(),
        1,
        "the original unsynced row must survive retry exhaustion"
    );
    assert_eq!(
        rows[0], v_old,
        "version must remain the seeded original — every attempt rolled back"
    );
}

/// drift guard: when the coalesce branch overwrites a queued
/// `Delete(T2)` with a fresh `Upsert(T3)`, the dropped Delete must
/// be audit-logged so peer audit consumers can reconstruct intent.
/// Pre-fix the Delete envelope simply vanished — the lifecycle read
/// "row created → row re-edited" instead of "row created → row
/// deleted → row resurrected".
#[test]
fn coalesce_audit_logs_dropped_delete_when_upsert_overwrites_queued_delete() {
    let conn = test_db();

    // First, queue an Upsert(T1) so a subsequent Delete is a coalesce.
    let upsert_t1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002184",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue_coalesced(&conn, &upsert_t1).unwrap();

    // Then a Delete(T2) — this overwrites the Upsert(T1) row.
    let delete_t2 = make_delete_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002184",
        "1811234567890_0000_b1b2c3d4b1b2c3d4",
    );
    enqueue_coalesced(&conn, &delete_t2).unwrap();

    // Now the H4 case: an Upsert(T3) coalesces over the queued
    // Delete. The Delete row gets overwritten — the audit-log site
    // must record this, since peer audit consumers cannot otherwise
    // know the cluster wanted the row gone at T2.
    let upsert_t3 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002184",
        "1911234567890_0000_c1b2c3d4c1b2c3d4",
    );
    enqueue_coalesced(&conn, &upsert_t3).unwrap();

    let dropped_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog \
             WHERE operation = 'sync.outbox.coalesced_delete_dropped'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        dropped_count >= 1,
        "outbox coalesce must audit-log when an Upsert overwrites a queued Delete; \
         got {dropped_count} entries in ai_changelog"
    );
}

/// drift guard: an `Upsert → Upsert` coalesce must NOT trip the
/// dropped-Delete audit, since no Delete intent is being lost. Pure
/// upsert chains are the common case (every edit on a row coalesces
/// into the latest version) and they must stay quiet.
#[test]
fn coalesce_does_not_audit_log_when_upsert_overwrites_queued_upsert() {
    let conn = test_db();

    let upsert_t1 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002193",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue_coalesced(&conn, &upsert_t1).unwrap();

    let upsert_t2 = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002193",
        "1811234567890_0000_b1b2c3d4b1b2c3d4",
    );
    enqueue_coalesced(&conn, &upsert_t2).unwrap();

    let dropped_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog \
             WHERE operation = 'sync.outbox.coalesced_delete_dropped'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        dropped_count, 0,
        "Upsert → Upsert coalesce must not log a dropped-Delete audit entry"
    );
}
