//! Tests for `audit_retention`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::test_db;

/// Insert a changelog entry whose timestamp is `days_ago` days in the past,
/// computed server-side via SQLite's date math for test determinism.
fn insert_entry_days_ago(conn: &Connection, id: &str, days_ago: i32) {
    let modifier = format!("-{days_ago} days");
    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
         VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?2), 'create', 'task', 'test summary', 'ai')",
        params![id, modifier],
    )
    .unwrap();
}

/// Count total changelog entries (test-only diagnostic).
fn count_changelog(conn: &Connection) -> u64 {
    conn.prepare_cached("SELECT COUNT(*) FROM ai_changelog")
        .unwrap()
        .query_row([], |r| r.get::<_, i64>(0).map(|v| v as u64))
        .unwrap()
}

/// Return the set of changelog ids currently in the table.
fn changelog_ids(conn: &Connection) -> Vec<String> {
    let mut stmt = conn
        .prepare("SELECT id FROM ai_changelog ORDER BY id ASC")
        .unwrap();
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    rows
}

#[test]
fn gc_changelog_deletes_old_preserves_recent() {
    let conn = test_db();

    insert_entry_days_ago(&conn, "recent", 5);
    insert_entry_days_ago(&conn, "old", 100);

    assert_eq!(count_changelog(&conn), 2);

    // GC with 90-day retention.
    let deleted = gc_changelog_by_retention_days(&conn, Some(90)).unwrap();
    assert_eq!(deleted, 1, "should delete the 100-day-old entry");

    let ids = changelog_ids(&conn);
    assert_eq!(ids, vec!["recent".to_string()]);
}

// -----------------------------------------------------------------------
// Policy-aware function tests
// -----------------------------------------------------------------------

#[test]
fn forever_retention_under_safeguard_keeps_all_rows() {
    let conn = test_db();

    insert_entry_days_ago(&conn, "a", 1);
    insert_entry_days_ago(&conn, "b", 5);
    insert_entry_days_ago(&conn, "c", 100);
    assert_eq!(count_changelog(&conn), 3);

    let deleted = gc_changelog_by_retention_days(&conn, None).unwrap();
    assert_eq!(
        deleted, 0,
        "three rows is far below the safeguard cap — nothing to prune"
    );
    assert_eq!(count_changelog(&conn), 3);
}

#[test]
fn forever_retention_enforces_safeguard_cap() {
    // Longevity regression: users who select "forever" retention must
    // not grow the table unbounded. The safeguard cap trims the
    // oldest rows once the table exceeds `AUDIT_MAX_ENTRIES_SAFEGUARD`.
    let conn = test_db();

    // Seed the table with cap+5 entries, oldest-first, using distinct
    // past timestamps so ordering is well-defined. A reused prepared
    // statement avoids re-parsing and re-planning the INSERT 10k
    // times — pre-batched form took ~2.7s, prepared form ~150ms.
    let total = AUDIT_MAX_ENTRIES_SAFEGUARD as i32 + 5;
    {
        let mut stmt = conn
            .prepare(
                "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by) \
                 VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?2), 'create', 'task', 'test summary', 'ai')",
            )
            .unwrap();
        for i in 0..total {
            let id = format!("entry-{i:05}");
            let modifier = format!("-{} days", total - i);
            stmt.execute(params![id, modifier]).unwrap();
        }
    }
    assert_eq!(count_changelog(&conn), total as u64);

    let deleted = gc_changelog_by_retention_days(&conn, None).unwrap();
    assert_eq!(deleted, 5u64, "5 oldest rows trimmed to reach the cap");
    assert_eq!(
        count_changelog(&conn),
        u64::from(AUDIT_MAX_ENTRIES_SAFEGUARD)
    );

    // A second run with no new inserts is a no-op.
    let deleted_again = gc_changelog_by_retention_days(&conn, None).unwrap();
    assert_eq!(deleted_again, 0u64);
}

#[test]
fn days7_retention_cleans_old_entries() {
    let conn = test_db();

    insert_entry_days_ago(&conn, "recent", 3);
    insert_entry_days_ago(&conn, "old", 10);

    let deleted = gc_changelog_by_retention_days(&conn, Some(7)).unwrap();
    assert_eq!(deleted, 1, "should delete the 10-day-old entry");
    let ids = changelog_ids(&conn);
    assert_eq!(ids, vec!["recent".to_string()]);
}

#[test]
fn gc_by_retention_on_empty_table() {
    let conn = test_db();

    let deleted = gc_changelog_by_retention_days(&conn, None).unwrap();
    assert_eq!(deleted, 0);

    let deleted = gc_changelog_by_retention_days(&conn, Some(14)).unwrap();
    assert_eq!(deleted, 0);
}

#[test]
fn days30_retention_retains_recent_deletes_old() {
    let conn = test_db();

    insert_entry_days_ago(&conn, "within", 15);
    insert_entry_days_ago(&conn, "outside", 45);

    let deleted = gc_changelog_by_retention_days(&conn, Some(30)).unwrap();
    assert_eq!(deleted, 1);

    let ids = changelog_ids(&conn);
    assert_eq!(ids, vec!["within".to_string()]);
}

#[test]
fn days90_retention_retains_wide_window() {
    let conn = test_db();

    insert_entry_days_ago(&conn, "a", 5);
    insert_entry_days_ago(&conn, "b", 50);
    insert_entry_days_ago(&conn, "c", 85);
    insert_entry_days_ago(&conn, "d", 100);

    let deleted = gc_changelog_by_retention_days(&conn, Some(90)).unwrap();
    assert_eq!(
        deleted, 1,
        "only the 100-day entry is outside 90-day window"
    );
    assert_eq!(count_changelog(&conn), 3);
}

/// `Some(0)` is unreachable via the canonical preference path
/// (`parse_positive_i64_preference` rejects non-positive values), but
/// the public GC API guards against it as defense-in-depth so a
/// future caller bypassing the preference reader cannot silently
/// vaporize the entire audit log under a "delete < now" cutoff.
#[test]
fn gc_changelog_with_zero_retention_is_no_op() {
    let conn = test_db();
    insert_entry_days_ago(&conn, "recent", 5);
    insert_entry_days_ago(&conn, "old", 100);
    assert_eq!(count_changelog(&conn), 2);

    let deleted = gc_changelog_by_retention_days(&conn, Some(0)).unwrap();
    assert_eq!(deleted, 0, "Some(0) must not delete anything");
    assert_eq!(count_changelog(&conn), 2);
}

/// Regression for the MCP AuditRetentionPolicy parse bug: the UI
/// offers 60/180/365-day retention options that the old enum
/// rejected. With the `Option<u32>` API, every positive integer is
/// accepted and cleanup works end-to-end.
#[test]
fn non_canonical_retention_days_work_end_to_end() {
    let conn = test_db();
    insert_entry_days_ago(&conn, "within-60", 30);
    insert_entry_days_ago(&conn, "outside-60", 90);
    insert_entry_days_ago(&conn, "within-180", 120);
    insert_entry_days_ago(&conn, "within-365", 300);
    insert_entry_days_ago(&conn, "outside-365", 400);

    let deleted = gc_changelog_by_retention_days(&conn, Some(60)).unwrap();
    assert_eq!(
        deleted, 4,
        "60-day cutoff removes the four rows older than 60 days"
    );
    let ids = changelog_ids(&conn);
    assert_eq!(ids, vec!["within-60".to_string()]);
}
