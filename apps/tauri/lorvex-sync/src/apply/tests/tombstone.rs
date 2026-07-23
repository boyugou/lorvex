use super::*;

fn make_redirect_envelope(entity_type: &str, entity_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(MATRIX_V_B)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: make_payload_for_entity_type(entity_type),
        device_id: "remote-device".to_string(),
    }
}

fn seed_redirect_fixtures(conn: &Connection) {
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002127', 'H', 'daily', 1, 0, '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [],
    ).unwrap();
    conn.execute(
        "INSERT INTO habits (id, name, frequency_type, target_count, archived, version, created_at, updated_at)
         VALUES (?1, 'Reminder Parent', 'daily', 1, 0, '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [DUMMY_UUID_A],
    ).unwrap();
}

fn assert_redirect_lands(conn: &Connection, entity_type: &str, old_id: &str, new_id: &str) {
    // 1. Arrange: tombstone at MATRIX_V_A with redirect old → new.
    create_tombstone(
        conn,
        entity_type,
        old_id,
        MATRIX_V_A,
        "2026-04-01T00:00:00.000Z",
        Some(new_id),
        Some(entity_type),
    )
    .unwrap();

    // 2. Act: envelope targets the old id at a strictly newer version.
    let env = make_redirect_envelope(entity_type, old_id);
    let result = apply_envelope(conn, &env).unwrap();

    // 3. Assert: apply reports the remap with the canonical old→new ids.
    assert_eq!(
        result,
        ApplyResult::Remapped {
            from_entity_id: old_id.to_string(),
            to_entity_id: new_id.to_string(),
        },
        "expected Remapped for {entity_type}, got {result:?}"
    );
}

#[test]
fn apply_skipped_when_tombstoned_with_newer_version() {
    let conn = test_db();

    // Create a tombstone with a newer version.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234569999_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Skipped { .. }));
}

#[test]
fn apply_upsert_wins_over_older_tombstone() {
    let conn = test_db();

    // Create a tombstone with an older version.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234560000_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234569999_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Tombstone should have been removed.
    assert!(!crate::tombstone::is_tombstoned(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163"
    )
    .unwrap());
}

#[test]
fn newer_delete_refreshes_existing_tombstone_and_blocks_between_version_upsert() {
    let conn = test_db();
    let mid_version = "1711234565000_0000_a1b2c3d4a1b2c3d4";

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        LWW_V_OLD,
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let delete_env = make_delete_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        LWW_V_NEW,
    );
    let delete_result = apply_envelope(&conn, &delete_env).unwrap();
    assert_eq!(delete_result, ApplyResult::Applied);

    let tombstone = crate::tombstone::get_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
    )
    .unwrap()
    .expect("newer delete must keep the tombstone present");
    assert_eq!(
        tombstone.version, LWW_V_NEW,
        "newer delete envelopes must advance an existing tombstone version"
    );

    let upsert_env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        mid_version,
    );
    let upsert_result = apply_envelope(&conn, &upsert_env).unwrap();
    assert!(
        matches!(upsert_result, ApplyResult::Skipped { .. }),
        "upserts between the old and refreshed delete versions must not resurrect the row"
    );

    let task_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002163'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(task_count, 0, "task must stay deleted");
}

#[test]
fn apply_remapped_when_tombstoned_with_redirect() {
    let conn = test_db();

    // Create a tombstone with a redirect (merge loser).
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        "1711234560000_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000215f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234569999_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"display_name":"loser","lookup_key":"loser","created_at":"","updated_at":""}"#
            .to_string(),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(
        result,
        ApplyResult::Remapped {
            from_entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000215f".to_string(),
            to_entity_id: "01966a3f-7c8b-7d4e-8f3a-000000002161".to_string(),
        }
    );
}

#[test]
fn redirect_tombstone_wins_regardless_of_version() {
    let conn = test_db();

    // Create redirect tombstone with an OLD version.
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        "1000000000000_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // Envelope has a MUCH newer version.
    let env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Tag,
        entity_id: "01966a3f-7c8b-7d4e-8f3a-00000000215f".to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("9999999999999_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"display_name":"loser","lookup_key":"loser","created_at":"","updated_at":""}"#
            .to_string(),
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &env).unwrap();
    // Redirect is authoritative regardless of version.
    assert!(matches!(result, ApplyResult::Remapped { .. }));
}

#[test]
fn redirect_skips_remapped_envelope_when_target_has_newer_local_version() {
    let conn = test_db();

    // Seed the redirect target with a NEWER local version than the
    // stale envelope is about to carry.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002161', 'Winner', 'winner', '9000000000000_0000_a1b2c3d4a1b2c3d4', \
                 '2026-03-22T00:00:00.000Z', '2026-03-22T00:00:00.000Z')",
        [],
    )
    .unwrap();

    // Redirect tombstone: loser → winner.
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        "1000000000000_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000002161"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    // Stale pre-merge envelope for the loser at an OLD version. After
    // remapping to `01966a3f-7c8b-7d4e-8f3a-000000002161`, the LWW guard must skip because the
    // winner already has a newer local version.
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
        device_id: "remote-device".to_string(),
    };
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Skipped { .. }),
        "expected Skipped, got {result:?}"
    );

    // Winner row must still carry the newer version and display name.
    let (display_name, version): (String, String) = conn
        .query_row(
            "SELECT display_name, version FROM tags WHERE id = ?1",
            ["01966a3f-7c8b-7d4e-8f3a-000000002161"],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(display_name, "Winner");
    assert_eq!(version, "9000000000000_0000_a1b2c3d4a1b2c3d4");
}

#[test]
fn apply_delete_envelope_succeeds() {
    let conn = test_db();
    let env = make_delete_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

#[test]
fn apply_invalid_version_in_tombstone_errors() {
    let conn = test_db();

    // Create a tombstone with an invalid version string.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "not-a-valid-hlc",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    let result = apply_envelope(&conn, &env);
    assert!(matches!(result, Err(ApplyError::InvalidVersion(_))));
}

#[test]
fn apply_remapped_when_tombstoned_with_redirect_habit_reminder_policy() {
    let conn = test_db();
    seed_redirect_fixtures(&conn);
    assert_redirect_lands(
        &conn,
        naming::ENTITY_HABIT_REMINDER_POLICY,
        "01966a3f-7c8b-7d4e-8f3a-000000002146",
        "01966a3f-7c8b-7d4e-8f3a-000000002145",
    );
    let count_new: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM habit_reminder_policies WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002145'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count_new, 1);
}

#[test]
fn apply_remapped_when_tombstoned_with_redirect_memory_revision() {
    let conn = test_db();
    // memory_revisions have no FK constraint at the apply level -
    // they reference `memory_key` as a soft reference.
    const REV_OLD: &str = "01966a3f-7c8b-7d4e-8f3a-000000002401";
    const REV_NEW: &str = "01966a3f-7c8b-7d4e-8f3a-000000002402";
    assert_redirect_lands(&conn, naming::ENTITY_MEMORY_REVISION, REV_OLD, REV_NEW);
    let count_new: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE id = ?1",
            [REV_NEW],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count_new, 1);
}

// natural-key entity types (current_focus,
// focus_schedule, daily_review, preference, memory) are
// content-addressed by their natural key (date, NFC string) and
// never participate in the merge-redirect protocol. The previous
// `apply_remapped_when_tombstoned_with_redirect_focus_schedule` and
// `apply_remapped_when_tombstoned_with_redirect_current_focus`
// tests exercised a defensive path that production never reaches —
// a tombstone redirecting `2026-04-01 → 2026-04-02` cannot be
// produced by any local writer because dates are immutable
// identities. The `debug_assert!` in `remap_entity_id` now formally
// prohibits this, surfacing as a panic in unit tests if a future
// refactor accidentally registers a natural-key redirect tombstone.
// These tests are intentionally removed (no backward compat).

// ---------------------------------------------------------------------------
// redirect-chain chase regressions.
// ---------------------------------------------------------------------------

/// Build a deterministic UUIDv7-shaped task id for the chain tests.
fn task_chain_id(suffix: u8) -> String {
    format!("00000000-0000-7000-8000-0000000030{suffix:02x}")
}

/// a redirect chain longer than `REDIRECT_CHAIN_CAP`
/// must surface as `TombstoneRedirectChainTooDeep`, NOT silently
/// land the apply at an intermediate id (which is what the
/// pre-#3002 chase loop did when the cap was exhausted but the
/// chain continued).
#[test]
fn chase_redirect_chain_surfaces_chain_too_deep_at_cap_plus_one() {
    let conn = test_db();
    // Build a task → task → task → ... chain of `REDIRECT_CHAIN_CAP + 2`
    // hops (so the chain still has a redirect at the cap-th node).
    // Each node has a strictly-increasing HLC version so the
    // tombstone INSERTs satisfy any version-monotonicity guards.
    let chain_len = REDIRECT_CHAIN_CAP + 2;
    let ids: Vec<String> = (0..=chain_len).map(|i| task_chain_id(i as u8)).collect();
    for (i, from) in ids.iter().take(chain_len).enumerate() {
        let to = &ids[i + 1];
        let version = format!("17112345{i:05}_0000_aaaaaaaaaaaaaaaa");
        create_tombstone(
            &conn,
            naming::ENTITY_TASK,
            from,
            &version,
            "2026-04-01T00:00:00.000Z",
            Some(to.as_str()),
            None,
        )
        .unwrap();
    }

    let result = chase_redirect_chain(&conn, naming::ENTITY_TASK, &ids[0]);
    let err = result.expect_err("chase must error on a chain deeper than the cap");
    match err {
        ApplyError::TombstoneRedirectChainTooDeep {
            entity_type,
            entity_id,
            chain_length,
            terminal_id,
        } => {
            assert_eq!(entity_type, naming::ENTITY_TASK);
            assert_eq!(entity_id, ids[0]);
            // The hop log captures `REDIRECT_CHAIN_CAP` advances.
            assert_eq!(chain_length, REDIRECT_CHAIN_CAP);
            assert_eq!(terminal_id, ids[REDIRECT_CHAIN_CAP]);
        }
        other => panic!("expected TombstoneRedirectChainTooDeep, got {other:?}"),
    }
}

/// a chain that terminates EXACTLY at the cap
/// (i.e. cap-th node is non-redirect) must NOT trip ChainTooDeep —
/// the chase should return cleanly with the terminus.
#[test]
fn chase_redirect_chain_terminates_cleanly_at_cap() {
    let conn = test_db();
    let chain_len = REDIRECT_CHAIN_CAP;
    let ids: Vec<String> = (0..=chain_len).map(|i| task_chain_id(i as u8)).collect();
    for (i, from) in ids.iter().take(chain_len).enumerate() {
        let to = &ids[i + 1];
        let version = format!("17112345{i:05}_0000_aaaaaaaaaaaaaaaa");
        create_tombstone(
            &conn,
            naming::ENTITY_TASK,
            from,
            &version,
            "2026-04-01T00:00:00.000Z",
            Some(to.as_str()),
            None,
        )
        .unwrap();
    }
    // Final hop is NOT a redirect; chase should land on it cleanly.
    let (final_type, final_id, hops) =
        chase_redirect_chain(&conn, naming::ENTITY_TASK, &ids[0]).unwrap();
    assert_eq!(final_type, naming::ENTITY_TASK);
    assert_eq!(final_id, ids[chain_len]);
    assert_eq!(hops.len(), chain_len);
}

/// a cross-type redirect tombstone (task → habit)
/// must update the entity_type the chase walks under so the next
/// hop's tombstone lookup runs against the correct table. The
/// pre-#3002 chase always re-passed the original entity_type and
/// silently ignored `redirect_entity_type`.
#[test]
fn chase_redirect_chain_honors_cross_type_redirect_target() {
    let conn = test_db();
    let task_id = "00000000-0000-7000-8000-000000003200";
    let habit_id = "00000000-0000-7000-8000-000000003201";

    // Cross-type tombstone: task `task_id` redirects to habit `habit_id`.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        task_id,
        "1711234567000_0000_aaaaaaaaaaaaaaaa",
        "2026-04-01T00:00:00.000Z",
        Some(habit_id),
        Some(naming::ENTITY_HABIT),
    )
    .unwrap();

    let (final_type, final_id, hops) =
        chase_redirect_chain(&conn, naming::ENTITY_TASK, task_id).unwrap();
    assert_eq!(
        final_type,
        naming::ENTITY_HABIT,
        "cross-type chase must update entity_type per hop"
    );
    assert_eq!(final_id, habit_id);
    assert_eq!(hops.len(), 1);
    assert_eq!(hops[0].from_entity_type, naming::ENTITY_TASK);
    // `final_type` (asserted above) carries the terminal hop's
    // destination type — the redundant `hops[0].to_entity_type`
    // field has been removed from `RedirectHop`.
}

/// a self-redirect first-hop must trip cycle
/// detection BEFORE advancing into the loop.
///
/// `create_tombstone` rejects `(entity_type, entity_id)` self-
/// redirects at the write boundary (#2999-M3), so we cannot
/// directly INSERT one to exercise the cycle path. We instead
/// build the smallest legal cycle: A → B → A, which the chase
/// MUST detect on the second hop because the visited-set seeds
/// with the initial id.
#[test]
fn chase_redirect_chain_detects_two_hop_mutual_cycle() {
    let conn = test_db();
    let id_a = "00000000-0000-7000-8000-000000003300";
    let id_b = "00000000-0000-7000-8000-000000003301";

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        id_a,
        "1711234567000_0000_aaaaaaaaaaaaaaaa",
        "2026-04-01T00:00:00.000Z",
        Some(id_b),
        None,
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        id_b,
        "1711234568000_0000_aaaaaaaaaaaaaaaa",
        "2026-04-01T00:00:00.000Z",
        Some(id_a),
        None,
    )
    .unwrap();

    let result = chase_redirect_chain(&conn, naming::ENTITY_TASK, id_a);
    let err = result.expect_err("mutual A→B / B→A must surface as a cycle");
    assert!(
        matches!(err, ApplyError::TombstoneRedirectCycle { .. }),
        "expected TombstoneRedirectCycle, got {err:?}"
    );
}
