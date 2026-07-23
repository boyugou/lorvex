use super::support::*;

// ===========================================================================
// 16. redirect chain > 1 hop ending at a
//     hard-tombstoned id must drop a stale upsert and emit a
//     `RESOLUTION_TOMBSTONE_WINS` conflict_log row.
// ===========================================================================

/// the redirect-target tombstone-vs-upsert guard at
/// `apply/mod.rs::apply_envelope` (the
/// `target_ts.redirect_entity_id.is_none()` branch) was previously
/// exercised only for a single redirect hop. A chain `A -> B -> C` where
/// the final target `C` carries a hard (non-redirect) DELETE tombstone
/// is the multi-hop case: an upsert for `A` must walk both redirect
/// tombstones, observe that the chain terminates at the hard-deleted
/// `C`, and refuse to resurrect `C` against an envelope version older
/// than the C tombstone.
///
/// Pre-fix the chain walk and the tombstone-vs-upsert guard were both
/// implemented but the guard had no test coverage for chain length > 1.
/// A regression that only checked the FIRST hop's tombstone for the
/// hard-delete branch would silently resurrect `C` because no test
/// would catch it. This test pins the multi-hop contract so future
/// edits to the redirect-walker / target-guard interaction can't break
/// it without surfacing a failure.
#[test]
fn redirect_chain_two_hops_ending_at_hard_tombstone_drops_upsert() {
    let conn = test_db();

    // Hop 1: A redirects to B. Authored at V1 (the merge that absorbed A).
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003117",
        V1,
        "2026-04-01T10:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000003119"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // Hop 2: B redirects to C. Authored at V2 (the second merge).
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003119",
        V2,
        "2026-04-01T11:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-00000000311b"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // Hop 3 / chain terminus: C is hard-deleted. No `redirect_entity_id`,
    // tombstone version is V3 (the newest in the cluster). C must NOT
    // exist in `tags` — its row was hard-deleted before the tombstone
    // landed, which is exactly the failure mode the guard exists to
    // catch (a stale upsert resurrecting a hard-deleted target).
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311b",
        V3,
        "2026-04-01T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // A late-replayed upsert for 01966a3f-7c8b-7d4e-8f3a-000000003117 arrives from a peer that hadn't
    // yet seen any of the three tombstones. The envelope's version is
    // strictly OLDER than the hard-delete tombstone on C — any
    // resurrection here would silently revive a deleted tag.
    let payload = r#"{
        "name": "shared-tag",
        "display_name": "Shared",
        "lookup_key": "shared-tag",
        "created_at": "2026-03-30T10:00:00.000Z",
        "updated_at": "2026-03-30T11:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003117",
        V2,
        payload,
    );

    let result = apply_envelope(&conn, &env).unwrap();

    // After walking A -> B -> C, the redirect-target guard must observe
    // that C is hard-tombstoned at V3 > envelope's V2 and skip apply.
    match result {
        ApplyResult::Skipped {
            reason,
            winner_version,
        } => {
            assert!(
                reason.contains("01966a3f-7c8b-7d4e-8f3a-00000000311b")
                    && reason.contains("tombstoned"),
                "skip reason should reference the redirect target's hard \
                 tombstone, got: {reason}"
            );
            let winner_hlc = winner_version
                .expect("hard-tombstone winner must surface a typed Hlc winner_version");
            assert_eq!(winner_hlc.to_string(), V3);
        }
        other => panic!(
            "expected Skipped (hard tombstone wins over stale chain-end upsert), \
             got {other:?}"
        ),
    }

    // None of the three ids may have been written to `tags` — the
    // chain terminus is dead, and no live row may exist on any
    // pre-merge identity.
    assert_eq!(
        count_rows(&conn, "tags", "id IN ('01966a3f-7c8b-7d4e-8f3a-000000003117','01966a3f-7c8b-7d4e-8f3a-000000003119','01966a3f-7c8b-7d4e-8f3a-00000000311b')"),
        0
    );

    // The tombstone on C must remain — `remove_tombstone` would have
    // fired only if the envelope had STRICTLY newer HLC than the
    // tombstone (concurrent-update-wins-over-concurrent-delete).
    let still_dead = get_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000311b",
    )
    .unwrap()
    .expect(
        "hard tombstone for 01966a3f-7c8b-7d4e-8f3a-00000000311b must survive the stale upsert",
    );
    assert!(still_dead.redirect_entity_id.is_none());
    assert_eq!(still_dead.version, V3);

    // The skip must also surface in `sync_conflict_log` so the
    // diagnostics panel sees it (M1 contract). This is
    // the load-bearing breadcrumb for an operator chasing "why did a
    // late peer-replay vanish silently?".
    let (resolution_type, entity_id_logged): (String, String) = conn
        .query_row(
            "SELECT resolution_type, entity_id \
             FROM sync_conflict_log \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("conflict_log row for the dropped chain-end upsert");
    assert_eq!(resolution_type, naming::RESOLUTION_TOMBSTONE_WINS);
    // The remapped envelope's entity_id is C — that's what the guard
    // logs. Prior to the H4 audit it was unverified that the multi-hop
    // walk reached C at all; this assertion pins it.
    assert_eq!(entity_id_logged, "01966a3f-7c8b-7d4e-8f3a-00000000311b");
}
