use super::*;
use crate::test_db;
use rusqlite::params;

/// HLC versions used across tests. Lexicographic ordering matches temporal ordering.
const V_OLD: &str = "1711234567000_0000_dec0000100000001";
const V_MID: &str = "1711234568000_0000_dec0000100000001";
const V_NEW: &str = "1711234569000_0000_dec0000100000001";

fn tag_payload(display_name: &str, lookup_key: &str, color: Option<&str>) -> String {
    serde_json::json!({
        "display_name": display_name,
        "lookup_key": lookup_key,
        "color": color,
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    })
    .to_string()
}

fn count_tags(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM tags", [], |r| r.get(0))
        .unwrap()
}

fn get_tag_display_name(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row("SELECT display_name FROM tags WHERE id = ?1", [id], |r| {
        r.get(0)
    })
    .ok()
}

fn get_tag_version(conn: &Connection, id: &str) -> Option<String> {
    conn.query_row("SELECT version FROM tags WHERE id = ?1", [id], |r| r.get(0))
        .ok()
}

// -----------------------------------------------------------------------
// apply_tag_upsert: insert
// -----------------------------------------------------------------------

#[test]
fn upsert_inserts_new_tag() {
    let conn = test_db();
    let payload = tag_payload("Urgent", "urgent", Some("#ff0000"));
    apply_tag_upsert(&conn, "tag-001", &payload, V_MID, false.into(), "").unwrap();

    assert_eq!(count_tags(&conn), 1);
    assert_eq!(get_tag_display_name(&conn, "tag-001").unwrap(), "Urgent");
}

#[test]
fn upsert_rederives_lookup_key_from_display_name_ignoring_payload_value() {
    // Regression for R16: `apply_tag_upsert` must NOT trust a
    // payload-supplied `lookup_key`. An older peer (or a buggy CLI
    // tool) that writes a non-canonical lookup_key would otherwise
    // break `merge_duplicate_tags`, which converges only rows whose
    // lookup_key strings compare literally equal. Re-deriving via
    // `normalize_lookup_key(display_name)` enforces the NFKC +
    // casefold invariant at the sync trust boundary.
    let conn = test_db();
    // Payload advertises a DIFFERENT lookup_key than the
    // display_name would produce.
    let payload = tag_payload("WORK", "not-the-canonical-key", None);
    apply_tag_upsert(&conn, "tag-work", &payload, V_MID, false.into(), "").unwrap();

    let stored: String = conn
        .query_row(
            "SELECT lookup_key FROM tags WHERE id = ?1",
            ["tag-work"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, "work",
        "apply must ignore the payload lookup_key and re-derive from display_name"
    );
}

// -----------------------------------------------------------------------
// apply_tag_upsert: LWW — newer version wins
// -----------------------------------------------------------------------

#[test]
fn upsert_updates_when_version_is_newer() {
    let conn = test_db();
    let p1 = tag_payload("OldName", "urgent", None);
    apply_tag_upsert(&conn, "tag-001", &p1, V_OLD, false.into(), "").unwrap();

    let p2 = tag_payload("NewName", "urgent", Some("#00ff00"));
    apply_tag_upsert(&conn, "tag-001", &p2, V_NEW, false.into(), "").unwrap();

    assert_eq!(count_tags(&conn), 1);
    assert_eq!(get_tag_display_name(&conn, "tag-001").unwrap(), "NewName");
    assert_eq!(get_tag_version(&conn, "tag-001").unwrap(), V_NEW);
}

// -----------------------------------------------------------------------
// apply_tag_upsert: LWW — older version is skipped
// -----------------------------------------------------------------------

#[test]
fn upsert_skips_when_version_is_older() {
    let conn = test_db();
    let p1 = tag_payload("Current", "urgent", None);
    apply_tag_upsert(&conn, "tag-001", &p1, V_NEW, false.into(), "").unwrap();

    // Attempt an older version — should be silently skipped.
    let p2 = tag_payload("Stale", "urgent", None);
    apply_tag_upsert(&conn, "tag-001", &p2, V_OLD, false.into(), "").unwrap();

    assert_eq!(get_tag_display_name(&conn, "tag-001").unwrap(), "Current");
    assert_eq!(get_tag_version(&conn, "tag-001").unwrap(), V_NEW);
}

// -----------------------------------------------------------------------
// apply_tag_delete
// -----------------------------------------------------------------------

#[test]
fn delete_removes_existing_tag() {
    let conn = test_db();
    let p = tag_payload("Bye", "bye", None);
    apply_tag_upsert(&conn, "tag-del", &p, V_MID, false.into(), "").unwrap();
    assert_eq!(count_tags(&conn), 1);

    apply_tag_delete(&conn, "tag-del", V_NEW, "").unwrap();
    assert_eq!(count_tags(&conn), 0);
}

#[test]
fn delete_is_idempotent_for_missing_tag() {
    let conn = test_db();
    // Deleting a tag that does not exist should not error.
    apply_tag_delete(&conn, "nonexistent", V_NEW, "").unwrap();
    assert_eq!(count_tags(&conn), 0);
}

/// a delete envelope whose HLC is
/// strictly less than the local row's `version` MUST NOT remove
/// the row, even if the upstream apply pipeline somehow routed
/// a stale envelope here. The in-row LWW guard makes the handler
/// safe regardless of upstream gating (shadow-promotion replay,
/// pending-restore re-emit, future replay paths).
#[test]
fn stale_delete_envelope_is_refused_by_in_row_lww_guard() {
    let conn = test_db();
    // Seed the tag at a high HLC.
    let p = tag_payload("Stay", "stay", None);
    apply_tag_upsert(&conn, "tag-stay", &p, V_NEW, false.into(), "").unwrap();
    assert_eq!(count_tags(&conn), 1);

    // Apply a delete at a strictly lower HLC. Pre-#2993-M1 the
    // bare `DELETE FROM tags WHERE id = ?1` happily removed the
    // row, so a stale-replay path could resurrect a delete the
    // cluster had already overruled. The fix's `:version >= version`
    // predicate refuses the SQL update — the row stays alive.
    apply_tag_delete(&conn, "tag-stay", V_OLD, "").unwrap();
    assert_eq!(
        count_tags(&conn),
        1,
        "stale delete (V_OLD) MUST NOT remove a row at V_NEW; \
         the in-row LWW guard regressed",
    );
}

// -----------------------------------------------------------------------
// merge_duplicate_tags: lookup_key convergence
// -----------------------------------------------------------------------

#[test]
fn merge_keeps_smaller_id_and_tombstones_loser() {
    let conn = test_db();

    // Insert two tags with display_names that normalize to the same
    // lookup_key but with different IDs. "aaa" < "zzz"
    // lexicographically, so "aaa" should be the winner. We use
    // different casings of the same word so the apply-level
    // normalization correctly converges them (the previous version
    // of this test relied on a hand-specified `lookup_key` field in
    // the payload, which `apply_tag_upsert` now re-derives from the
    // display_name to enforce the NFKC + casefold invariant at the
    // sync trust boundary — see the R16 audit fix in this file).
    let p_winner = tag_payload("WinnerTag", "unused", None);
    apply_tag_upsert(&conn, "aaa", &p_winner, V_MID, false.into(), "").unwrap();

    // Create a task so we can verify task_tags are re-pointed.
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
         VALUES ('task-1', 'T', 'open', '0000000000000_0000_0000000000000000', '', '')",
        [],
    )
    .unwrap();
    // Attach task-1 to the winner tag so the re-point is observable.
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         VALUES ('task-1', 'aaa', '2026-01-01', '0000000000000_0000_0000000000000000')",
        [],
    )
    .unwrap();

    // Insert the duplicate: "winnertag" casefolds to the same
    // lookup_key as "WinnerTag" → merge should trigger, winner
    // (smaller id "aaa") survives.
    let p_loser = tag_payload("winnertag", "unused", Some("#111111"));
    apply_tag_upsert(&conn, "zzz", &p_loser, V_NEW, false.into(), "").unwrap();

    // After merge: only the winner tag should remain. The winner
    // retains whatever display_name was last written to its row
    // (here "WinnerTag" from the first upsert) — merge only
    // deletes the loser row and re-points task_tags, it does not
    // copy the loser's display_name into the winner.
    assert_eq!(count_tags(&conn), 1);
    assert_eq!(get_tag_display_name(&conn, "aaa").unwrap(), "WinnerTag");
    assert!(get_tag_display_name(&conn, "zzz").is_none());

    // The loser should have a tombstone with redirect to the winner.
    let (redirect_id, redirect_type): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT redirect_entity_id, redirect_entity_type FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![naming::ENTITY_TAG, "zzz"],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(redirect_id.as_deref(), Some("aaa"));
    assert_eq!(redirect_type.as_deref(), Some(naming::ENTITY_TAG));

    // task_tags should still link task-1 to the winner.
    let tag_id: String = conn
        .query_row(
            "SELECT tag_id FROM task_tags WHERE task_id = 'task-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tag_id, "aaa");
}

#[test]
fn merge_repoints_task_tags_from_loser_to_winner() {
    let conn = test_db();

    // Winner tag (smaller ID). display_name "shared" normalizes to
    // lookup_key "shared".
    let p1 = tag_payload("shared", "unused", None);
    apply_tag_upsert(&conn, "alpha", &p1, V_OLD, false.into(), "").unwrap();

    // Create two tasks.
    for (id, title) in [("t1", "Task1"), ("t2", "Task2")] {
        conn.execute(
            &format!(
                "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
                 VALUES ('{id}', '{title}', 'open', '0000000000000_0000_0000000000000000', '', '')"
            ),
            [],
        )
        .unwrap();
    }

    // Attach t1 to alpha, t2 to the upcoming loser "beta".
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         VALUES ('t1', 'alpha', '', '0000000000000_0000_0000000000000000')",
        [],
    )
    .unwrap();
    // Insert beta with a display_name whose normalized lookup_key
    // differs from alpha's, so the FK is satisfied without
    // triggering convergence.
    let p2 = tag_payload("unrelated", "unused", None);
    apply_tag_upsert(&conn, "beta", &p2, V_OLD, false.into(), "").unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         VALUES ('t2', 'beta', '', '0000000000000_0000_0000000000000000')",
        [],
    )
    .unwrap();

    // Now update beta so its display_name normalizes to the same
    // lookup_key as alpha's (`"shared"`). apply_tag_upsert
    // re-derives `lookup_key = normalize_lookup_key(display_name)`
    // at the sync trust boundary, so this transition drives the
    // merge_duplicate_tags path.
    let p2_collision = tag_payload("Shared", "unused", None);
    apply_tag_upsert(&conn, "beta", &p2_collision, V_NEW, false.into(), "").unwrap();

    // After merge: only alpha survives.
    assert_eq!(count_tags(&conn), 1);
    assert!(get_tag_display_name(&conn, "alpha").is_some());
    assert!(get_tag_display_name(&conn, "beta").is_none());

    // Both tasks should now be linked to alpha.
    let mut stmt = conn
        .prepare("SELECT task_id FROM task_tags WHERE tag_id = 'alpha' ORDER BY task_id")
        .unwrap();
    let tasks: Vec<String> = stmt
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(tasks, vec!["t1", "t2"]);

    // No task_tags should reference beta.
    let beta_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE tag_id = 'beta'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(beta_count, 0);
}

#[test]
fn no_merge_when_lookup_keys_differ() {
    let conn = test_db();
    let p1 = tag_payload("Tag A", "key_a", None);
    let p2 = tag_payload("Tag B", "key_b", None);
    apply_tag_upsert(&conn, "tag-a", &p1, V_MID, false.into(), "").unwrap();
    apply_tag_upsert(&conn, "tag-b", &p2, V_MID, false.into(), "").unwrap();

    // Both tags should coexist — no merge.
    assert_eq!(count_tags(&conn), 2);
    assert!(get_tag_display_name(&conn, "tag-a").is_some());
    assert!(get_tag_display_name(&conn, "tag-b").is_some());
}

#[test]
fn stale_envelope_does_not_trigger_merge() {
    let conn = test_db();

    // Insert the "winner" tag with a newer version.
    let p1 = tag_payload("Winner", "dup_key", None);
    apply_tag_upsert(&conn, "aaa", &p1, V_NEW, false.into(), "").unwrap();

    // Insert a second tag with a different lookup_key first.
    let p2 = tag_payload("Other", "other_key", None);
    apply_tag_upsert(&conn, "zzz", &p2, V_MID, false.into(), "").unwrap();
    assert_eq!(count_tags(&conn), 2);

    // Now send a stale (older version) upsert for "zzz" that happens to
    // have lookup_key "dup_key". Because the version is older than the
    // existing row, the upsert should be rejected and NO merge should run.
    let p_stale = tag_payload("StaleCollision", "dup_key", None);
    apply_tag_upsert(&conn, "zzz", &p_stale, V_OLD, false.into(), "").unwrap();

    // Both tags should still exist — the stale envelope was skipped.
    assert_eq!(count_tags(&conn), 2);
    // zzz should retain its original display_name.
    assert_eq!(get_tag_display_name(&conn, "zzz").unwrap(), "Other");
}

// -----------------------------------------------------------------------
// winner row stamping + HlcState feedback.
//
// Two structural bugs the merge previously left in place:
//   H5 — children/edges advance to `merge_version` but the winner
//        aggregate row stays at `triggering_version`. A peer reading
//        the snapshot then sees winner.version < children.version.
//   M1 — `merge_version` is minted via direct `Hlc::new(...)`, never
//        through `hlc_state.generate()`. The in-process clock has no
//        record of having emitted that HLC, so a subsequent local
//        edit can produce an HLC strictly less than `merge_version`,
//        regressing every child row this merge just stamped.
// -----------------------------------------------------------------------

/// H5 regression: after a tag merge, the winner row's `version`
/// equals `merge_version` (and is strictly greater than the
/// triggering envelope's version + every participant version).
#[test]
fn merge_stamps_winner_tag_version_at_merge_version() {
    let conn = test_db();

    // Two tags whose normalized lookup_key matches → triggers
    // merge_duplicate_tags. "aaa" < "zzz" so "aaa" is the winner.
    let p1 = tag_payload("Shared", "unused", None);
    apply_tag_upsert(&conn, "aaa", &p1, V_MID, false.into(), "").unwrap();
    let p2 = tag_payload("shared", "unused", None);
    apply_tag_upsert(&conn, "zzz", &p2, V_NEW, false.into(), "").unwrap();

    // After merge: only winner remains.
    assert!(get_tag_display_name(&conn, "aaa").is_some());
    assert!(get_tag_display_name(&conn, "zzz").is_none());

    // Winner's version must be the merge_version, NOT the
    // triggering envelope's version (V_NEW). The merge_version
    // equals the loser tombstone's version.
    let winner_version = get_tag_version(&conn, "aaa").unwrap();
    let tombstone_version: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![naming::ENTITY_TAG, "zzz"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        winner_version, tombstone_version,
        "winner.version must equal merge_version (== loser tombstone version)"
    );

    // Strictly greater than the triggering envelope's version.
    let winner_hlc = Hlc::parse(&winner_version).unwrap();
    let triggering_hlc = Hlc::parse(V_NEW).unwrap();
    assert!(
        winner_hlc > triggering_hlc,
        "winner.version ({winner_version}) must be > triggering version ({V_NEW})"
    );
}

/// M1 regression: after a tag merge, the registered local-event
/// observer fires exactly once with `merge_version`. A test
/// HlcState that consumes the observation via `update_on_receive`
/// then generates a strictly-greater HLC.
#[test]
fn merge_observes_local_event_with_merge_version() {
    use lorvex_domain::hlc_state::HlcState;
    use std::sync::{Arc, Mutex};

    let conn = test_db();

    // Capture every observed HLC. The closure mirrors how a real
    // Tauri/MCP wiring would route observed merges to its
    // process-wide HlcState — `update_on_receive` advances past
    // the merge_version even though the merge author IS this
    // device.
    let observed = Arc::new(Mutex::new(Vec::<Hlc>::new()));
    let observed_for_closure = Arc::clone(&observed);
    let test_state = Arc::new(Mutex::new(HlcState::new("a1b2c3d4e5f60718").unwrap()));
    let state_for_closure = Arc::clone(&test_state);

    let merge_version = crate::hlc::with_temporary_observer(
        move |hlc| {
            observed_for_closure
                .lock()
                .expect("observed lock")
                .push(hlc.clone());
            state_for_closure
                .lock()
                .expect("state lock")
                .update_on_receive(hlc, hlc.physical_ms());
        },
        || {
            let p1 = tag_payload("Shared", "unused", None);
            apply_tag_upsert(&conn, "aaa", &p1, V_MID, false.into(), "").unwrap();
            let p2 = tag_payload("shared", "unused", None);
            apply_tag_upsert(&conn, "zzz", &p2, V_NEW, false.into(), "").unwrap();
            get_tag_version(&conn, "aaa").expect("winner version")
        },
    );

    // Observer fired at least once and one of the observed HLCs
    // is exactly `merge_version`. (The merge can fire only the
    // once-collapsing event; we assert presence rather than
    // exact count to stay resilient against future merge
    // refactors that mint additional local events.)
    let observed = observed.lock().expect("observed lock");
    let merge_hlc = Hlc::parse(&merge_version).unwrap();
    assert!(
        observed.iter().any(|h| h == &merge_hlc),
        "observer must have received merge_version {merge_version}; got {observed:?}"
    );

    // After the observation, the test HlcState's next `generate`
    // must produce an HLC strictly greater than `merge_version`.
    let next = test_state
        .lock()
        .expect("state lock")
        .generate_with_physical(merge_hlc.physical_ms());
    assert!(
        next > merge_hlc,
        "next generated HLC ({next}) must strictly exceed merge_version ({merge_version})"
    );
}

#[test]
fn merge_reports_clear_error_when_no_canonical_hlc_successor_exists() {
    let conn = test_db();
    let ceiling = lorvex_domain::hlc::MAX_HLC_PHYSICAL_MS;
    let max_counter = lorvex_domain::hlc_state::MAX_COUNTER;
    let winner_version = format!("{ceiling}_{:04}_dec0000100000001", max_counter - 1);
    let loser_version = format!("{ceiling}_{max_counter:04}_dec0000200000002");

    let p1 = tag_payload("Shared", "unused", None);
    apply_tag_upsert(&conn, "aaa", &p1, &winner_version, false.into(), "").unwrap();
    let p2 = tag_payload("shared", "unused", None);
    let err = apply_tag_upsert(&conn, "zzz", &p2, &loser_version, false.into(), "")
        .expect_err("ceiling merge must fail with a typed version error");

    match err {
        ApplyError::InvalidVersion(message) => {
            assert!(
                message.contains("tag merge")
                    && message.contains("no canonical HLC successor")
                    && message.contains(&loser_version),
                "unexpected ceiling error message: {message}"
            );
        }
        other => panic!("expected InvalidVersion, got {other:?}"),
    }
}

// -----------------------------------------------------------------------
// tag-merge conflict log records the loser's
// distinct display_name / color so the lossy attribute drop is
// discoverable in the diagnostics surface instead of vanishing
// silently.
// -----------------------------------------------------------------------

/// When the loser tag carries a different `display_name` and `color`
/// from the winner, the merge logs a `tag_merge` conflict_log row
/// whose `loser_payload` captures both diverging fields and whose
/// `loser_version` / `loser_device_id` reference the loser's HLC.
#[test]
fn merge_logs_conflict_when_loser_display_name_or_color_differs() {
    let conn = test_db();

    // Winner: id "aaa", display "WinnerTag", no color.
    let p_winner = tag_payload("WinnerTag", "unused", None);
    apply_tag_upsert(&conn, "aaa", &p_winner, V_MID, false.into(), "ts-1").unwrap();

    // Loser: id "zzz", normalizes to the same lookup_key, with a
    // distinct color AND a casefold-divergent display_name.
    let p_loser = tag_payload("winnertag", "unused", Some("#0066ff"));
    apply_tag_upsert(&conn, "zzz", &p_loser, V_NEW, false.into(), "ts-2").unwrap();

    // Winner survived, loser was tombstoned.
    assert!(get_tag_display_name(&conn, "aaa").is_some());
    assert!(get_tag_display_name(&conn, "zzz").is_none());

    // Conflict log: the merge produced exactly one tag_merge entry.
    let (loser_version, loser_device_id, loser_payload, resolution_type, resolved_at): (
        String,
        String,
        Option<String>,
        String,
        String,
    ) = conn
        .query_row(
            "SELECT loser_version, loser_device_id, loser_payload, resolution_type, resolved_at \
             FROM sync_conflict_log \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![naming::ENTITY_TAG, "aaa"],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("merge must record exactly one tag_merge conflict_log row");

    assert_eq!(resolution_type, naming::RESOLUTION_TAG_MERGE);
    assert_eq!(
        loser_version, V_NEW,
        "loser_version must reference the loser tag's HLC"
    );
    // V_NEW's HLC suffix is "dec0000100000001"; the merge logs that suffix as
    // the device id so the diagnostics panel can attribute the dropped
    // tag to a specific peer.
    let expected_suffix = Hlc::parse(V_NEW).unwrap().device_suffix().to_string();
    assert_eq!(loser_device_id, expected_suffix);
    assert_eq!(
        resolved_at, "ts-2",
        "merge must propagate the once-per-envelope apply_ts"
    );

    let payload = loser_payload.expect("loser_payload must be set");
    let parsed: serde_json::Value =
        serde_json::from_str(&payload).expect("loser_payload must be valid JSON");
    assert_eq!(
        parsed.get("display_name"),
        Some(&serde_json::json!("winnertag"))
    );
    assert_eq!(parsed.get("color"), Some(&serde_json::json!("#0066ff")));
}

/// When the loser tag's `display_name` and `color` are identical to
/// the winner's, the merge is genuinely lossless and NO conflict_log
/// row is emitted. Re-pointing task_tags is not by itself a "lossy
/// drop" event.
#[test]
fn merge_does_not_log_conflict_when_loser_fields_match_winner() {
    let conn = test_db();

    // Winner and loser share the same display_name (after NFKC
    // casefold) AND the same color. The only difference is the id.
    let p_winner = tag_payload("Shared", "unused", Some("#abcdef"));
    apply_tag_upsert(&conn, "aaa", &p_winner, V_MID, false.into(), "ts-1").unwrap();

    let p_loser = tag_payload("Shared", "unused", Some("#abcdef"));
    apply_tag_upsert(&conn, "zzz", &p_loser, V_NEW, false.into(), "ts-2").unwrap();

    // Merge happened (loser deleted) but no conflict_log row.
    assert!(get_tag_display_name(&conn, "zzz").is_none());
    let conflict_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log \
             WHERE entity_type = ?1 AND resolution_type = ?2",
            params![naming::ENTITY_TAG, naming::RESOLUTION_TAG_MERGE],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        conflict_count, 0,
        "lossless merge must not record a tag_merge conflict_log row"
    );
}
