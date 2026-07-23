//! Tests for `task`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::test_db;

/// a cascade-tombstone for a child
/// edge whose own `version` exceeds the parent delete's HLC must
/// be stamped at the child's higher version. Otherwise a later
/// replay of the child's pre-cascade upsert (whose HLC dominates
/// the parent-stamped tombstone) would lift the tombstone and
/// silently revive the edge.
#[test]
fn cascade_tombstone_uses_max_of_parent_and_edge_version() {
    let conn = test_db();

    // Seed minimal tag and task rows.
    let task_id = "00000000-0000-7000-8000-000000000010";
    let tag_id = "tag-x";
    conn.execute(
        "INSERT INTO tasks (id, title, status, version,
                            created_at, updated_at, defer_count)
         VALUES (?1, 'T', 'open', '1711234567000_0000_dec0000100000001',
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)",
        params![task_id],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version,
                           created_at, updated_at)
         VALUES (?1, 'X', 'x', '1711234567000_0000_dec0000100000001',
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![tag_id],
    )
    .unwrap();

    // Edge row carries a STRICTLY NEWER HLC than the impending
    // parent delete — simulates a concurrent edge edit racing
    // the cascade.
    let edge_version = "1711234599000_0000_dec0000200000002";
    let parent_delete_version = "1711234567500_0000_dec0000100000001";
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
         VALUES (?1, ?2, '2026-04-01T00:00:00.000Z', ?3)",
        params![task_id, tag_id, edge_version],
    )
    .unwrap();

    // Run the parent delete via the cascade helper. The
    // tombstone for the edge composite id MUST be stamped at
    // the edge's own (greater) version, not the parent's
    // delete version.
    super::apply_task_delete(&conn, task_id, parent_delete_version, "").unwrap();

    let edge_entity_id = format!("{task_id}:{tag_id}");
    let stored_tombstone_version: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![lorvex_domain::naming::EDGE_TASK_TAG, &edge_entity_id],
            |row| row.get(0),
        )
        .expect("edge tombstone must exist");

    assert_eq!(
        stored_tombstone_version, edge_version,
        "cascade tombstone must be stamped at the edge row's own version, \
         not the parent's lower delete version"
    );

    // Sanity: tombstone version is strictly greater than the
    // parent delete version.
    let ts_hlc = lorvex_domain::hlc::Hlc::parse(&stored_tombstone_version).unwrap();
    let parent_hlc = lorvex_domain::hlc::Hlc::parse(parent_delete_version).unwrap();
    assert!(ts_hlc > parent_hlc);
}

/// `apply_task_delete` is reachable
/// from `apply_entity_with_version_mode(_, true)` (shadow
/// promotion) and any future replay path. The in-row predicate
/// `?2 >= tasks.version` must reject a stale delete whose
/// version is strictly less than the current local version,
/// even if the upper-level LWW gate is bypassed.
#[test]
fn apply_task_delete_refuses_to_remove_a_newer_local_row() {
    let conn = test_db();
    let task_id = "00000000-0000-7000-8000-000000000020";
    let local_version = "1711234599000_0000_dec0000200000002";
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at, defer_count)
         VALUES (?1, 'T', 'open', ?2, '2026-04-01T00:00:00.000Z',
                 '2026-04-01T00:00:00.000Z', 0)",
        params![task_id, local_version],
    )
    .unwrap();

    // Stale delete: stamp version is strictly less than the
    // local row's version. Calling the helper directly bypasses
    // the upper-level LWW gate but the in-row predicate must
    // still hold the line.
    let stale_version = "1711234567000_0000_dec0000100000001";
    super::apply_task_delete(&conn, task_id, stale_version, "").unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        count, 1,
        "stale-version delete must NOT remove a newer local task row"
    );
}

/// when the local row's `version`
/// fails to parse as an HLC (legacy `'v1'`-style literal,
/// hand-edited DB, fixture from an older migration), the
/// pre-#3002 delete handler ran the parsed-HLC short-circuit
/// (which falls through on parse failure), then the cascade
/// tombstone pass, then `evaluate_delete_lww`. The byte-compare
/// fallback in `evaluate_delete_lww` REJECTS the delete (ASCII
/// letters sort above digits, so `'v1'` lex-dominates a
/// canonical HLC), but by then the child / edge tombstones had
/// already been committed in `sync_tombstones`. The net effect
/// was orphan tombstones with HLCs ≥ peers' subsequent edge
/// upsert HLCs — peers stayed permanently rejected.
///
/// With the `gate_then_cascade` helper the LWW gate runs
/// FIRST. On `Reject`, the cascade closure is never invoked,
/// so the child tombstones are never written and peers can
/// continue to converge edge state freely.
#[test]
fn cascade_does_not_run_when_byte_compare_fallback_rejects_legacy_local_version() {
    let conn = test_db();
    let task_id = "00000000-0000-7000-8000-000000000031";
    let tag_id = "tag-#3002-h1";
    let canonical_envelope_version = "1711234599000_0000_dec0000200000002";
    // Legacy unparseable local version. ASCII 'v' (0x76) sorts
    // strictly above any digit (0x30-0x39), so the byte-compare
    // fallback in `evaluate_delete_lww` interprets `'v1'` as
    // the dominating version and rejects the delete.
    let legacy_local_version = "v1";

    conn.execute(
        "INSERT INTO tasks (id, title, status, version,
                            created_at, updated_at, defer_count)
         VALUES (?1, 'T', 'open', ?2,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)",
        params![task_id, legacy_local_version],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version,
                           created_at, updated_at)
         VALUES (?1, 'X', 'x', ?2,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![tag_id, canonical_envelope_version],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
         VALUES (?1, ?2, '2026-04-01T00:00:00.000Z', ?3)",
        params![task_id, tag_id, canonical_envelope_version],
    )
    .unwrap();

    let outcome = super::apply_task_delete(
        &conn,
        task_id,
        canonical_envelope_version,
        "2026-04-01T00:00:00.000Z",
    )
    .unwrap();

    assert!(
        matches!(outcome, super::super::LwwGatedDeleteOutcome::LwwRejected(_)),
        "byte-compare fallback must surface the loss as LwwRejected, got {outcome:?}"
    );

    // Parent row must still be alive.
    let parent_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = ?1",
            params![task_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        parent_count, 1,
        "byte-compare-rejected delete must leave the parent task alive"
    );

    // Critical: NO cascade tombstone must have been written for
    // the task_tag edge. Pre-#3002 this assertion would fail —
    // the cascade pass committed the tombstone before the
    // post-cascade gate refused the parent delete.
    let edge_entity_id = format!("{task_id}:{tag_id}");
    let edge_tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![lorvex_domain::naming::EDGE_TASK_TAG, &edge_entity_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        edge_tombstone_count, 0,
        "cascade tombstone must NOT be written when the LWW gate rejects the parent delete"
    );
}
