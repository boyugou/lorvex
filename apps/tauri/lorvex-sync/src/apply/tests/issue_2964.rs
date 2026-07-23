//! Regression coverage for issue #2964 (M3 + M4 + M5 + M6).
//!
//! Each block below targets one symptom from the audit:
//!   - M3: cycle-path DFS no longer clones the path on every push.
//!   - M4: per-row SAVEPOINT around `promote_payload_shadows`
//!     iterations.
//!   - M5: redirect chase rewrites `device_id` to local when the
//!     merge tombstone was authored by the local device.
//!   - M6: a delete refused by the in-handler LWW gate must NOT
//!     create a tombstone.

use super::*;
use lorvex_runtime::device_id_to_hlc_suffix;
use lorvex_store::test_support::fixtures::TaskBuilder;

// ──────────────────────────────────────────────────────────────────
// M3: transitive-cycle path reconstruction
// ──────────────────────────────────────────────────────────────────

/// A 4-node transitive cycle exercises the parents-map path
/// reconstruction. Pre-fix the DFS carried a `Vec<String>` per stack
/// frame and cloned it on every push; the new shape walks the
/// `parents` map only when a cycle is actually found and produces
/// the SAME canonical path the cycle-break logic enumerates.
#[test]
fn transitive_cycle_break_walks_full_path_with_parents_map() {
    let conn = test_db();
    const T1: &str = "01966a3f-7c8b-7d4e-8f3a-000000002155";
    const T2: &str = "01966a3f-7c8b-7d4e-8f3a-000000002252";
    const T3: &str = "01966a3f-7c8b-7d4e-8f3a-000000002253";
    const T4: &str = "01966a3f-7c8b-7d4e-8f3a-000000002156";
    for id in [T1, T2, T3, T4] {
        TaskBuilder::new(id).title("T").insert(&conn);
    }
    // Build chain T1 -> T2 -> T3 -> T4 with ascending HLCs.
    for (idx, (from, to)) in [(T1, T2), (T2, T3), (T3, T4)].iter().enumerate() {
        let env = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::TaskDependency,
            entity_id: format!("{from}:{to}"),
            operation: SyncOperation::Upsert,
            // Strictly ascending HLCs so the chain edges are all
            // newer than the cycle-closing edge below.
            version: lorvex_domain::hlc::Hlc::parse(&format!(
                "171123456789{}_0000_a1b2c3d4a1b2c3d4",
                idx + 1
            ))
            .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: PAYLOAD_SCHEMA_VERSION,
            payload: format!(
                r#"{{"task_id":"{from}","depends_on_task_id":"{to}","created_at":""}}"#
            ),
            device_id: "remote-device".to_string(),
        };
        let result = apply_envelope(&conn, &env).unwrap();
        assert_eq!(result, ApplyResult::Applied);
    }

    // Closing edge T4 -> T1 with the OLDEST HLC. The transitive
    // cycle exists; the cycle-break code finds the OLDEST edge on
    // the cycle path (the closing edge itself) and rejects the
    // incoming. The path-walk has to traverse T1 -> T2 -> T3 -> T4.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskDependency,
        entity_id: format!("{T4}:{T1}"),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567000_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: format!(r#"{{"task_id":"{T4}","depends_on_task_id":"{T1}","created_at":""}}"#),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &env);
    assert!(
        result.is_err(),
        "incoming with oldest HLC must lose the cycle tiebreak"
    );

    // All three forward edges survive — every device computes the
    // same verdict.
    let edges: Vec<(String, String)> = conn
        .prepare(
            "SELECT task_id, depends_on_task_id FROM task_dependencies \
             ORDER BY task_id",
        )
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(
        edges,
        vec![
            (T1.to_string(), T2.to_string()),
            (T2.to_string(), T3.to_string()),
            (T3.to_string(), T4.to_string()),
        ]
    );
}

// ──────────────────────────────────────────────────────────────────
// M4: per-row SAVEPOINT in promote_payload_shadows
// ──────────────────────────────────────────────────────────────────

/// A failing shadow row must NOT propagate its error to the caller
/// or roll back the surrounding outer transaction; the SAVEPOINT
/// scopes the failure to the single bad row. Pre-fix the bad row's
/// `?` propagated up and tore down every prior promotion.
///
/// We exercise the failure path by directly inserting a malformed
/// row into `sync_payload_shadow` (bypassing the `upsert_shadow`
/// known-key stripping that would normally produce a parseable
/// trimmed payload). When the promote loop reaches this row it
/// invokes the tag handler, which returns InvalidPayload because
/// `display_name` is missing. The savepoint rolls back, the outer
/// transaction stays alive, and the function returns Ok.
#[test]
fn promote_payload_shadows_isolates_failing_row_via_savepoint() {
    let conn = test_db();
    // Direct INSERT bypasses `upsert_shadow`'s known-key stripping
    // so the handler sees the full malformed payload and surfaces
    // the InvalidPayload typed error mid-promotion.
    conn.execute(
        "INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, source_device_id, updated_at
         ) VALUES (?1, '01966a3f-7c8b-7d4e-8f3a-00000000215b', ?2, ?3, ?4, 'remote-device',
                   '2026-04-01T00:00:00.000Z')",
        rusqlite::params![
            naming::ENTITY_TAG,
            MATRIX_V_B,
            PAYLOAD_SCHEMA_VERSION,
            r#"{"lookup_key":"missing-display","created_at":"","updated_at":""}"#,
        ],
    )
    .unwrap();

    // Promote — must NOT propagate the bad shadow's error; the
    // SAVEPOINT confines the failure to its own row.
    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(promoted, 0, "no shadow successfully promotes");

    // The bad shadow remains in the shadow table for a future retry
    // (its writes were rolled back to the SAVEPOINT).
    let bad_remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_payload_shadow \
             WHERE entity_type = ?1 AND entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000215b'",
            [naming::ENTITY_TAG],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        bad_remaining, 1,
        "bad shadow must survive — savepoint rollback preserves it for retry"
    );

    // The failure surfaces in error_logs so diagnostics catch it
    // instead of silently disappearing.
    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.promote_shadow_failed'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        log_count, 1,
        "savepoint rollback must surface in error_logs"
    );

    // CRUCIAL: the outer transaction is still alive — a follow-up
    // write must succeed. Pre-fix the bad shadow's error rolled
    // back the BEGIN IMMEDIATE the test_db opened, leaving the
    // connection in autocommit mode and breaking every subsequent
    // statement.
    lorvex_store::test_support::ListBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000002130")
        .name("after")
        .version(MATRIX_V_B)
        .created_at("")
        .insert(&conn);
}

// ──────────────────────────────────────────────────────────────────
// M5: redirect chase rewrites device_id to local on local merge
// ──────────────────────────────────────────────────────────────────

/// When the redirect tombstone was authored locally (its HLC
/// suffix matches one of the local device's surfaces), the apply
/// pipeline must rewrite the remapped envelope's `device_id` to
/// the local id — every downstream attribution (conflict_log,
/// error_log, payload-shadow source_device_id) inherits that.
#[test]
fn redirect_chase_rewrites_device_id_to_local_on_local_authored_merge() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();

    let conn = test_db();
    let local_device_id = "01966a3f-7c8b-7d4e-8f3a-000000000abc";
    conn.execute(
        &format!(
            "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', '{local_device_id}')"
        ),
        [],
    )
    .unwrap();
    let local_app_suffix = device_id_to_hlc_suffix(local_device_id, HlcSurface::App);

    // Pre-seed the redirect target so the remapped UPSERT lands on
    // a row newer than the inbound envelope and trips the LWW
    // conflict_log path. We need a populated row at the WINNER's id
    // because the conflict_log row is what we use to verify the
    // device_id rewrite — it carries `loser_device_id`.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002161', 'Winner', 'winner', '9000000000000_0000_a1b2c3d4a1b2c3d4', \
                 '2026-04-19T00:00:00.000Z', '2026-04-19T00:00:00.000Z')",
        [],
    )
    .unwrap();

    // Merge tombstone: the loser's HLC carries the LOCAL App
    // suffix — i.e. the local device authored the merge.
    let merge_version = format!("5000000000000_0000_{local_app_suffix}");
    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        &merge_version,
        "2026-04-20T00:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // Inbound envelope from a REMOTE peer for the merge loser at a
    // version older than the winner's local row. The redirect
    // chase remaps to `01966a3f-7c8b-7d4e-8f3a-000000002161`, the LWW gate refuses (winner
    // newer), and the conflict_log row records the skipped
    // envelope — but with the LOCAL device_id (not the remote
    // peer's) because the merge that caused the redirect was
    // authored locally.
    let remote_peer = "01966a3f-7c8b-7d4e-8f3a-deadbeefcafe";
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000215f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("2000000000000_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload:
            r#"{"display_name":"stale","lookup_key":"winner","created_at":"","updated_at":""}"#
                .to_string(),
        device_id: remote_peer.to_string(),
    };

    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));

    let conflict_loser_device_id: String = conn
        .query_row(
            "SELECT loser_device_id FROM sync_conflict_log \
             WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002161' \
             ORDER BY id DESC LIMIT 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_loser_device_id, local_device_id,
        "loser_device_id must be rewritten to the local id when the redirect \
         tombstone was authored locally"
    );
}

/// Companion: when the merge tombstone was authored by a REMOTE
/// peer (its HLC suffix is foreign), the device_id stays the
/// inbound envelope's original peer — the rewrite is exactly
/// scoped to local-authored merges.
#[test]
fn redirect_chase_keeps_remote_device_id_when_merge_authored_remotely() {
    let _guard = collision_test_mutex()
        .lock()
        .expect("collision test mutex poisoned");
    reset_device_identity_collision_guard_for_testing();

    let conn = test_db();
    let local_device_id = "01966a3f-7c8b-7d4e-8f3a-000000000def";
    conn.execute(
        &format!(
            "INSERT INTO sync_checkpoints (key, value) VALUES ('device_id', '{local_device_id}')"
        ),
        [],
    )
    .unwrap();

    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002161', 'Winner', 'winner', '9000000000000_0000_a1b2c3d4a1b2c3d4', \
                 '2026-04-19T00:00:00.000Z', '2026-04-19T00:00:00.000Z')",
        [],
    )
    .unwrap();

    // Merge tombstone authored by a foreign suffix.
    crate::tombstone::create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        // Suffix `feedfeedfeedfeed` cannot match any local surface
        // hash for the seeded device_id.
        "5000000000000_0000_feedfeedfeedfeed",
        "2026-04-20T00:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let remote_peer = "01966a3f-7c8b-7d4e-8f3a-deadbeefcafe";
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000215f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("2000000000000_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload:
            r#"{"display_name":"stale","lookup_key":"winner","created_at":"","updated_at":""}"#
                .to_string(),
        device_id: remote_peer.to_string(),
    };
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));

    let conflict_loser_device_id: String = conn
        .query_row(
            "SELECT loser_device_id FROM sync_conflict_log \
             WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002161' \
             ORDER BY id DESC LIMIT 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_loser_device_id, remote_peer,
        "remote-authored merges must NOT rewrite device_id"
    );
}

// ──────────────────────────────────────────────────────────────────
// M6: in-handler LWW-rejected delete must NOT tombstone
// ──────────────────────────────────────────────────────────────────

/// Pre-fix `apply_envelope` always created a tombstone after a
/// delete envelope reached `apply_entity` — even when the
/// in-handler `:version >= version` gate refused the DELETE
/// because the local row's version was strictly greater. The
/// tombstone at the envelope's older HLC then dominated future
/// re-syncs and durably wiped the local winner. Post-fix the
/// dispatcher reports `LwwRejected`, the caller suppresses
/// tombstone creation, and the local row survives.
///
/// We stage this through `promote_payload_shadows` because it's
/// the only path that calls the delete handler with the SQL
/// `:version >= version` predicate active under conditions where
/// the outer LWW gate's parsed-HLC compare went the other way —
/// otherwise the outer gate already short-circuits before reaching
/// the handler. Concretely: a corrupt-but-string-greater local
/// version. The outer gate logs the corruption and falls through;
/// the handler's string compare refuses; M6 says don't tombstone.
#[test]
fn delete_with_corrupt_local_version_does_not_create_tombstone_when_handler_refuses() {
    let conn = test_db();

    // Seed a list with a CORRUPT-but-string-greater version. The
    // outer LWW gate will fail to parse it, log to error_logs, and
    // fall through. The in-handler `:version >= version` will then
    // refuse because the literal corrupt string sorts above the
    // envelope's well-formed version.
    lorvex_store::test_support::ListBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000213a")
        .name("keep me")
        .version("zzz-not-an-hlc-but-string-greater")
        .created_at("2026-04-20T00:00:00.000Z")
        .insert(&conn);
    // Add a second list so the at-least-one-list invariant doesn't
    // pre-empt the in-handler LWW gate.
    lorvex_store::test_support::ListBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000213c")
        .name("other")
        .created_at("2026-04-20T00:00:00.000Z")
        .insert(&conn);

    let env = make_delete_envelope(
        naming::ENTITY_LIST,
        "01966a3f-7c8b-7d4e-8f3a-00000000213a",
        LWW_V_NEW,
    );
    let result = apply_envelope(&conn, &env).unwrap();

    // Pre-fix this would have been `Applied`; post-fix it surfaces
    // as `Skipped` with the LWW-loss reason.
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped when in-handler LWW refuses the delete, got {result:?}"
    );

    // Local row survives.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000213a'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1, "local row must survive in-handler LWW refusal");

    // CRUCIAL: no tombstone was minted at the envelope's HLC.
    // Pre-fix we would have written one and corrupted future
    // re-syncs.
    assert!(
        !crate::tombstone::is_tombstoned(
            &conn,
            naming::ENTITY_LIST,
            "01966a3f-7c8b-7d4e-8f3a-00000000213a"
        )
        .unwrap(),
        "M6 regression: in-handler LWW rejection must NOT create a tombstone"
    );

    // The skip should have produced a conflict_log row so
    // diagnostics see it.
    let conflict_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log \
             WHERE entity_type = ?1 AND entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000213a'",
            [naming::ENTITY_LIST],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_count, 1,
        "in-handler LWW skip must surface in conflict_log"
    );
}

// ──────────────────────────────────────────────────────────────────
// #3051 H1: post-handler unparseable-equal must surface LwwRejected
// ──────────────────────────────────────────────────────────────────

/// Pre-#3051-H1 the post-handler LWW-rejection check parsed
/// `post_version` typed and, when the parse failed (legacy literal
/// like `'v1'` / `'seed'`), set `post_is_strictly_newer = false` and
/// fell through to `Applied`. But the in-handler SQL gate
/// `?:version >= row.version` byte-compares — digits sort BELOW
/// letters in ASCII, so a canonical envelope (digit-leading) is
/// refused by the SQL while the post-check says "Applied". Result:
/// a tombstone gets minted at the envelope's HLC over a still-live
/// row. Post-fix: when both `pre_version` and `post_version` are
/// unparseable AND equal, we surface `LwwRejected` so the caller
/// suppresses the tombstone.
///
/// Drives a `preference` aggregate (`StandardAggregate` handler:
/// no typed `LwwGatedDeleteOutcome`, so the post-handler check is
/// the only gate after the SQL `:version >= version` predicate).
#[test]
fn delete_with_unparseable_equal_local_version_surfaces_lww_rejected() {
    let conn = test_db();

    // Seed a preference row with a CORRUPT-but-letter-leading
    // version. Outer LWW gate fails to parse it, falls through
    // (logs to error_logs). The in-handler SQL gate byte-compares
    // the canonical digit-leading envelope vs `'v1'` and refuses
    // (digits < letters in ASCII).
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) \
         VALUES ('timezone', 'live', 'v1', '2026-04-20T00:00:00.000Z')",
        [],
    )
    .unwrap();

    let env = make_delete_envelope(naming::ENTITY_PREFERENCE, "timezone", LWW_V_NEW);
    let result = apply_envelope(&conn, &env).unwrap();

    // Pre-fix: `Applied` → tombstone minted over the live row.
    // Post-fix: `Skipped` with LWW-loss reason and no tombstone.
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped when SQL gate refuses on byte-compare \
         and post_version==pre_version (both unparseable), got {result:?}"
    );

    // Local row survives.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM preferences WHERE key = 'timezone'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        count, 1,
        "local preference row must survive in-handler SQL byte-compare refusal"
    );

    // No tombstone — pre-fix the post-handler said "Applied" and
    // a tombstone landed at the envelope's HLC.
    assert!(
        !crate::tombstone::is_tombstoned(&conn, naming::ENTITY_PREFERENCE, "timezone").unwrap(),
        "#3051 H1 regression: post-handler LWW unparseable-equal must NOT create a tombstone"
    );

    // The post-handler check logged the corruption to error_logs.
    let err_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs \
             WHERE source = 'sync.apply.post_handler_lww_unparseable'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(
        err_count >= 1,
        "post-handler unparseable detection must log to error_logs"
    );
}
