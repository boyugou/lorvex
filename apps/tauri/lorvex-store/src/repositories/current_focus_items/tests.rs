//! Tests for `current_focus_items`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::open_db_in_memory;

#[test]
fn materialize_deduplicates_task_ids() {
    let conn = open_db_in_memory().unwrap();
    // Create a current_focus header row first (FK parent).
    conn.execute(
        "INSERT INTO current_focus (date, timezone, version, created_at, updated_at) \
         VALUES ('2026-03-27', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [],
    )
    .unwrap();

    let ids = vec![
        "a".to_string(),
        "b".to_string(),
        "a".to_string(), // duplicate
        "c".to_string(),
    ];
    materialize_focus_items(&conn, "2026-03-27", &ids).unwrap();

    let result = query_focus_task_ids(&conn, "2026-03-27").unwrap();
    assert_eq!(result, vec!["a", "b", "c"]);
}

#[test]
fn materialize_replaces_existing() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO current_focus (date, timezone, version, created_at, updated_at) \
         VALUES ('2026-03-27', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [],
    )
    .unwrap();

    let ids1 = vec!["x".to_string(), "y".to_string()];
    materialize_focus_items(&conn, "2026-03-27", &ids1).unwrap();

    let ids2 = vec!["p".to_string(), "q".to_string(), "r".to_string()];
    materialize_focus_items(&conn, "2026-03-27", &ids2).unwrap();

    let result = query_focus_task_ids(&conn, "2026-03-27").unwrap();
    assert_eq!(result, vec!["p", "q", "r"]);
}

#[test]
fn materialize_empty_clears_all() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO current_focus (date, timezone, version, created_at, updated_at) \
         VALUES ('2026-03-27', 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [],
    )
    .unwrap();

    materialize_focus_items(&conn, "2026-03-27", &["a".to_string()]).unwrap();
    materialize_focus_items(&conn, "2026-03-27", &[]).unwrap();

    let result = query_focus_task_ids(&conn, "2026-03-27").unwrap();
    assert!(result.is_empty());
}

// -----------------------------------------------------------------------
// Parent row tests
// -----------------------------------------------------------------------

#[test]
fn upsert_creates_new_row() {
    let conn = open_db_in_memory().unwrap();
    let outcome = upsert_current_focus_header(
        &conn,
        "2026-03-27",
        Some("morning briefing"),
        "America/New_York",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();
    assert_eq!(outcome, UpsertOutcome::Created);

    let (briefing, tz): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT briefing, timezone FROM current_focus WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(briefing.as_deref(), Some("morning briefing"));
    assert_eq!(tz.as_deref(), Some("America/New_York"));
}

#[test]
fn upsert_update_preserves_timezone() {
    let conn = open_db_in_memory().unwrap();

    // Create with America/New_York
    upsert_current_focus_header(
        &conn,
        "2026-03-27",
        Some("v1 briefing"),
        "America/New_York",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();

    // Update — pass a different timezone; it should be ignored
    let outcome = upsert_current_focus_header(
        &conn,
        "2026-03-27",
        Some("v2 briefing"),
        "Europe/London",
        "v2",
        "2026-03-27T09:00:00Z",
    )
    .unwrap();
    assert_eq!(outcome, UpsertOutcome::Updated);

    let (briefing, tz, version): (Option<String>, Option<String>, String) = conn
        .query_row(
            "SELECT briefing, timezone, version FROM current_focus WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(briefing.as_deref(), Some("v2 briefing"));
    assert_eq!(tz.as_deref(), Some("America/New_York")); // immutable
    assert_eq!(version, "v2");
}

#[test]
fn touch_header_updates_version_and_timestamp() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-03-27",
        Some("briefing"),
        "UTC",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();

    touch_current_focus_header(&conn, "2026-03-27", Some("v2"), "2026-03-27T09:00:00Z").unwrap();

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, "v2");
    assert_eq!(updated_at, "2026-03-27T09:00:00Z");
}

#[test]
fn touch_header_without_version() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-03-27",
        Some("briefing"),
        "UTC",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();

    touch_current_focus_header(&conn, "2026-03-27", None, "2026-03-27T09:00:00Z").unwrap();

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, "v1"); // unchanged
    assert_eq!(updated_at, "2026-03-27T09:00:00Z");
}

/// a stale-version local write to the
/// `current_focus` header MUST be a no-op. Pre-fix the bare UPDATE
/// blindly wrote `version` + `updated_at`, regressing the row's HLC
/// whenever a peer envelope's version had already landed first.
#[test]
fn upsert_current_focus_header_lww_gate_rejects_stale_version() {
    let conn = open_db_in_memory().unwrap();

    // Seed at v2.
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("winning briefing"),
        "America/New_York",
        "0002000000000_0001_winnerwinnerwi",
        "2026-04-26T08:00:00Z",
    )
    .unwrap();

    // Stale write at v1 must NOT regress version, briefing, or updated_at,
    // and must surface as `LwwRejected` so callers can distinguish a real
    // update from a silently-dropped stale write.
    let stale_outcome = upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("stale briefing"),
        "America/New_York",
        "0001000000000_0001_loseroloseroloser",
        "2026-04-26T09:00:00Z",
    )
    .unwrap();
    assert_eq!(stale_outcome, UpsertOutcome::LwwRejected);

    let (briefing, version, updated_at): (Option<String>, String, String) = conn
        .query_row(
            "SELECT briefing, version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(briefing.as_deref(), Some("winning briefing"));
    assert_eq!(version, "0002000000000_0001_winnerwinnerwi");
    assert_eq!(updated_at, "2026-04-26T08:00:00Z");
}

/// `touch_current_focus_header` with a
/// stale-version stamp MUST be a no-op for the version-bumping
/// branch.
#[test]
fn touch_current_focus_header_lww_gate_rejects_stale_version() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        None,
        "UTC",
        "0002000000000_0001_winnerwinnerwi",
        "2026-04-26T08:00:00Z",
    )
    .unwrap();

    // Stale touch at v1 must not regress version or updated_at.
    touch_current_focus_header(
        &conn,
        "2026-04-26",
        Some("0001000000000_0001_loseroloseroloser"),
        "2026-04-26T09:00:00Z",
    )
    .unwrap();

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, "0002000000000_0001_winnerwinnerwi");
    assert_eq!(updated_at, "2026-04-26T08:00:00Z");
}

#[test]
fn delete_current_focus_removes_row_and_children() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-03-27",
        None,
        "UTC",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();
    materialize_focus_items(&conn, "2026-03-27", &["a".to_string(), "b".to_string()]).unwrap();

    let deleted = delete_current_focus(&conn, "2026-03-27").unwrap();
    assert!(deleted);

    // Parent gone
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus WHERE date = '2026-03-27'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);

    // Children cascaded
    let child_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-27'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(child_count, 0);
}

#[test]
fn delete_nonexistent_returns_false() {
    let conn = open_db_in_memory().unwrap();
    let deleted = delete_current_focus(&conn, "2099-01-01").unwrap();
    assert!(!deleted);
}

/// `materialize_focus_items_with_header_bump`
/// must advance both `version` and `updated_at` on the parent row
/// in the same call that rebuilds children, so peer LWW gates and
/// local sync state stay in lockstep with the materialized list.
#[test]
fn materialize_with_header_bump_advances_parent_version_and_updated_at() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("seed"),
        "UTC",
        "0001000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-04-26T08:00:00Z",
    )
    .unwrap();
    materialize_focus_items(&conn, "2026-04-26", &["a".to_string(), "b".to_string()]).unwrap();

    let new_version = "0001000000999_0000_devicea0devicea0";
    let new_updated_at = "2026-04-26T09:00:00Z";
    materialize_focus_items_with_header_bump(
        &conn,
        "2026-04-26",
        &["c".to_string(), "d".to_string()],
        new_version,
        new_updated_at,
    )
    .unwrap();

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, new_version);
    assert_eq!(updated_at, new_updated_at);
    let task_ids = query_focus_task_ids(&conn, "2026-04-26").unwrap();
    assert_eq!(task_ids, vec!["c", "d"]);
}

/// H3 regression — a stale-version local rebuild MUST be rejected
/// by the parent UPDATE's LWW gate, surface as
/// `StoreError::StaleVersion`, and leave the parent row + child
/// items untouched. Pre-fix the parent UPDATE was ungated despite
/// the doc-comment citing the hazard, so a local rebuild whose
/// freshly-minted HLC lex-compared older than an already-applied
/// peer envelope would silently regress the parent row's HLC and
/// blow away the peer's freshly-applied child list.
#[test]
fn materialize_with_header_bump_rejects_stale_version() {
    let conn = open_db_in_memory().unwrap();
    let winner = "0002000000000_0001_winnerwinnerwi";
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("seed"),
        "UTC",
        winner,
        "2026-04-26T08:00:00Z",
    )
    .unwrap();
    // Land a peer-applied child list so we can verify the rebuild
    // does NOT clobber it on the stale-version path.
    materialize_focus_items(
        &conn,
        "2026-04-26",
        &["winner-a".to_string(), "winner-b".to_string()],
    )
    .unwrap();

    let stale = "0001000000000_0001_loseroloseroloser";
    let err = materialize_focus_items_with_header_bump(
        &conn,
        "2026-04-26",
        &["loser-x".to_string()],
        stale,
        "2026-04-26T09:00:00Z",
    )
    .unwrap_err();
    match err {
        StoreError::StaleVersion { entity, id } => {
            assert_eq!(entity, "current_focus");
            assert_eq!(id, "2026-04-26");
        }
        other => panic!("expected StaleVersion, got {other:?}"),
    }

    // Parent row HLC is unchanged.
    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, winner);
    assert_eq!(updated_at, "2026-04-26T08:00:00Z");
    // Child list is unchanged.
    let task_ids = query_focus_task_ids(&conn, "2026-04-26").unwrap();
    assert_eq!(task_ids, vec!["winner-a", "winner-b"]);
}

/// H3 — equal-version re-stamp (the canonical local-write
/// orchestration: upsert header at V, then rebuild children with
/// the SAME V) must succeed. The strict `>` form rejected this
/// contracted re-stamp and broke every MCP set/save_focus path;
/// the gate is `>=` so the row's children get rebuilt while the
/// parent's `version` is a no-op write. `updated_at` advances to
/// the supplied `now`.
#[test]
fn materialize_with_header_bump_accepts_equal_version_restamp() {
    let conn = open_db_in_memory().unwrap();
    let v = "0001000000000_0001_a0a0a0a0a0a0a0a0";
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("seed"),
        "UTC",
        v,
        "2026-04-26T08:00:00Z",
    )
    .unwrap();

    materialize_focus_items_with_header_bump(
        &conn,
        "2026-04-26",
        &["a".to_string(), "b".to_string()],
        v,
        "2026-04-26T09:00:00Z",
    )
    .expect("equal-version re-stamp must succeed");

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, v);
    assert_eq!(updated_at, "2026-04-26T09:00:00Z");
    let task_ids = query_focus_task_ids(&conn, "2026-04-26").unwrap();
    assert_eq!(task_ids, vec!["a", "b"]);
}

/// H3 — calling the helper without an existing parent row must
/// surface `StaleVersion` instead of silently inserting orphaned
/// child rows. Production paths upsert the header before calling
/// this helper; a missing-parent state is a caller bug, but
/// short-circuiting here keeps the child list from drifting out of
/// step with the (absent) parent.
#[test]
fn materialize_with_header_bump_rejects_missing_parent_row() {
    let conn = open_db_in_memory().unwrap();
    let err = materialize_focus_items_with_header_bump(
        &conn,
        "2099-01-01",
        &["a".to_string()],
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2099-01-01T00:00:00Z",
    )
    .unwrap_err();
    assert!(matches!(err, StoreError::StaleVersion { .. }));

    // No child rows leaked through.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2099-01-01'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
}

/// the sync-apply path must NOT touch `current_focus`
/// header columns from the helper's arguments. After
/// `sync_upsert_current_focus` writes the envelope payload's
/// `(version, updated_at)`, the bare `materialize_focus_items` call
/// only rebuilds children — the parent row's header reflects the
/// envelope, never any local helper input.
#[test]
fn sync_apply_path_preserves_envelope_version_after_rebuild() {
    let conn = open_db_in_memory().unwrap();
    upsert_current_focus_header(
        &conn,
        "2026-04-26",
        Some("baseline"),
        "UTC",
        "0001000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-04-26T08:00:00Z",
    )
    .unwrap();

    let envelope_version = "0002000000000_0000_remoteremote00";
    let envelope_updated_at = "2026-04-26T10:30:00Z";
    let wrote = sync_upsert_current_focus(
        &conn,
        "2026-04-26",
        Some("remote-briefing"),
        Some("Europe/London"),
        envelope_version,
        "2026-04-26T08:00:00Z",
        envelope_updated_at,
        ">",
    )
    .unwrap();
    assert!(wrote);
    materialize_focus_items(&conn, "2026-04-26", &["x".to_string(), "y".to_string()]).unwrap();

    let (version, updated_at): (String, String) = conn
        .query_row(
            "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(version, envelope_version);
    assert_eq!(updated_at, envelope_updated_at);
}
