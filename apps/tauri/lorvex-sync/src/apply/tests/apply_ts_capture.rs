//! `apply_envelope` captures
//! `lorvex_domain::sync_timestamp_now()` exactly once at envelope
//! entry and threads the captured value through every helper that
//! needs a `resolved_at` / `deleted_at` timestamp.
//!
//! Pre-fix the pipeline called `sync_timestamp_now()` independently
//! at every site (pre-delete-restore snapshot, tombstone creation,
//! cascading-children helpers, conflict-log inserts, recurrence /
//! tag merges). Within a single envelope these reads could differ
//! by milliseconds, producing mismatched correlated timestamps in
//! the cascade rows a single delete authored.
//!
//! These tests prove the contract by feeding two envelopes back-to-
//! back through `apply_envelope` and asserting:
//!
//! 1. Every cascade tombstone row produced by a single delete shares
//!    the same `deleted_at` string. With the pre-fix shape, three
//!    independent `sync_timestamp_now()` reads (one per cascade
//!    helper) would produce three slightly-different millisecond
//!    timestamps; with the threaded `apply_ts` they MUST match.
//!
//! 2. Two back-to-back envelopes produce strictly different
//!    timestamps from each other (so we can confirm the fixture
//!    actually exercises the timing path — equality across two
//!    envelopes would mean the test could pass even if the fix
//!    hadn't been applied).

use super::*;

use rusqlite::params;

const V_ENV1: &str = "1711234567000_0000_a1b2c3d4a1b2c3d4";
const V_ENV2: &str = "1811234567000_0000_a1b2c3d4a1b2c3d4";

/// Insert a parent task plus a cascade-tombstoneable edge so a
/// subsequent delete envelope produces multiple cascade tombstone
/// rows. The cascade goes through `apply_task_delete` →
/// `tombstone_cascading_children_for_task` → `tombstone_composite_edges`,
/// each of which used to read `sync_timestamp_now()` independently.
fn seed_task_with_cascade(conn: &rusqlite::Connection, task_id: &str, version: &str) {
    let list_id = lorvex_store::INBOX_LIST_ID;
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, created_at, updated_at, version) \
         VALUES (?1, 'Inbox', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', ?2)",
        params![list_id, "0000000000000_0000_a0a0a0a0a0a0a0a0"],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at) \
         VALUES (?1, 'T', 'open', ?2, ?3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        params![task_id, list_id, version],
    )
    .unwrap();
    // Seed two child entities so the cascade helper produces multiple
    // tombstone rows that all need to share the captured `apply_ts`.
    let tag_id = format!("01966a3f-7c8b-7d4e-8f3a-00000000215e{task_id}");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES (?1, 'X', 'x', ?2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        params![tag_id, "0000000000000_0000_a0a0a0a0a0a0a0a0"],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         VALUES (?1, ?2, '2026-01-01T00:00:00Z', ?3)",
        params![task_id, tag_id, "0000000000000_0000_a0a0a0a0a0a0a0a0"],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, created_at, version) \
         VALUES (?1, ?2, '2030-01-01T00:00:00Z', '2026-01-01T00:00:00Z', ?3)",
        params![
            format!("01966a3f-7c8b-7d4e-8f3a-000000002149{task_id}"),
            task_id,
            "0000000000000_0000_a0a0a0a0a0a0a0a0"
        ],
    )
    .unwrap();
}

/// Read every cascade tombstone row's `deleted_at` for a given
/// parent task. The test asserts they're all identical — the
/// threaded `apply_ts` produces a single string shared by every
/// row, while the pre-fix shape produced N independent strings.
fn read_cascade_deleted_ats(
    conn: &rusqlite::Connection,
    task_id: &str,
    parent_version: &str,
) -> Vec<String> {
    // Parent tombstone (entity_id = task_id) PLUS every child /
    // edge tombstone that names the parent in its composite id.
    // Composite-id LIKE patterns mirror `tombstone_cascading_children_for_task`
    // in `apply/aggregate/task.rs`.
    let mut stmt = conn
        .prepare(
            "SELECT deleted_at FROM sync_tombstones \
             WHERE (entity_type = 'task' AND entity_id = ?1) \
                OR (entity_type IN ('task_tag', 'task_dependency', \
                                    'task_calendar_event_link') \
                    AND entity_id LIKE ?1 || ':%') \
                OR (entity_type IN ('task_reminder', 'task_checklist_item') \
                    AND entity_id IN (SELECT id FROM task_reminders WHERE task_id = ?1 \
                                      UNION ALL \
                                      SELECT id FROM task_checklist_items WHERE task_id = ?1))",
        )
        .unwrap();
    let _ = parent_version;
    let rows: Vec<String> = stmt
        .query_map([task_id], |row| row.get::<_, String>(0))
        .unwrap()
        .map(|r| r.unwrap())
        .collect();
    rows
}

#[test]
fn apply_envelope_shares_one_apply_ts_across_cascade_tombstones() {
    let conn = test_db();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000216a";
    seed_task_with_cascade(&conn, task_id, V_ENV1);

    // Delete the task at a strictly newer version — cascade fires
    // and produces (parent + edge + child) tombstone rows.
    let env = make_delete_envelope(naming::ENTITY_TASK, task_id, V_ENV2);
    apply_envelope(&conn, &env).expect("delete envelope applies");

    let deleted_ats = read_cascade_deleted_ats(&conn, task_id, V_ENV1);
    assert!(
        deleted_ats.len() >= 2,
        "fixture must produce ≥2 cascade tombstone rows; got {} ({deleted_ats:?})",
        deleted_ats.len()
    );
    let first = &deleted_ats[0];
    for ts in &deleted_ats[1..] {
        assert_eq!(
            ts, first,
            "every cascade tombstone row produced by one envelope MUST share \
             the same `apply_ts`; got mismatched: {first} vs {ts} \
             across rows {deleted_ats:?}"
        );
    }
}

#[test]
fn back_to_back_envelopes_capture_distinct_apply_ts() {
    // Two envelopes apply through the pipeline back-to-back. The
    // captured `apply_ts` for envelope A must be distinct from
    // envelope B's (else the test couldn't tell whether the
    // single-envelope-shares-one-ts test was meaningful — equality
    // across BOTH envelopes would let the bug pass).
    let conn = test_db();

    let task_a = "01966a3f-7c8b-7d4e-8f3a-000000002168";
    let task_b = "01966a3f-7c8b-7d4e-8f3a-000000002169";
    seed_task_with_cascade(&conn, task_a, V_ENV1);
    seed_task_with_cascade(&conn, task_b, V_ENV1);

    // Apply two delete envelopes in sequence. The 1 ms precision of
    // `sync_timestamp_now()` (millisecond RFC 3339, see
    // `lorvex-domain/src/time/sync_timestamp.rs`) means consecutive calls from
    // inside a single test are overwhelmingly distinct because the
    // apply path between them runs much more than 1 ms of work.
    apply_envelope(
        &conn,
        &make_delete_envelope(naming::ENTITY_TASK, task_a, V_ENV2),
    )
    .unwrap();
    apply_envelope(
        &conn,
        &make_delete_envelope(naming::ENTITY_TASK, task_b, V_ENV2),
    )
    .unwrap();

    let ts_a = read_cascade_deleted_ats(&conn, task_a, V_ENV1);
    let ts_b = read_cascade_deleted_ats(&conn, task_b, V_ENV1);
    assert!(!ts_a.is_empty() && !ts_b.is_empty());

    // Each envelope's own rows are internally consistent.
    for ts in &ts_a[1..] {
        assert_eq!(ts, &ts_a[0]);
    }
    for ts in &ts_b[1..] {
        assert_eq!(ts, &ts_b[0]);
    }
    // And the two envelopes carry distinct captured timestamps.
    // (If they happened to land in the same millisecond the test is
    // meaningless rather than wrong; assertion-style "almost always"
    // is acceptable here because the apply path between two
    // envelopes runs much more than 1 ms of work.)
    assert_ne!(
        ts_a[0], ts_b[0],
        "back-to-back envelopes must capture distinct apply_ts; \
         equality means the fixture is too fast to exercise the \
         per-envelope capture and the test is non-discriminating"
    );
}
