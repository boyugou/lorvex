use super::*;
use crate::test_db;

/// Insert a memory_revisions row with a relative `created_at` of
/// `"-N days"`. The `memories` row the FK points at must already
/// exist — the test_db fixture seeds at least one.
fn insert_rev(conn: &Connection, id: &str, key: &str, days_ago: i64) {
    conn.execute(
        "INSERT OR IGNORE INTO memories (id, key, content, version, updated_at) \
         VALUES (?1, ?2, 'seed', '0000000000000_0000_0000000000000000', \
         strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
        rusqlite::params![lorvex_domain::new_entity_id_string(), key],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO memory_revisions \
         (id, memory_key, content, operation, actor, version, created_at) \
         VALUES (?1, ?2, 'v', 'upsert', 'ai', \
                 '1000000000000_0000_deadbeefdeadbeef', \
                 strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?3))",
        rusqlite::params![id, key, format!("-{days_ago} days")],
    )
    .unwrap();
}

fn count(conn: &Connection) -> u64 {
    let n: i64 = conn
        .query_row("SELECT COUNT(*) FROM memory_revisions", [], |row| {
            row.get(0)
        })
        .unwrap();
    n as u64
}

#[test]
fn gc_returns_zero_for_forever_retention() {
    let conn = test_db();
    insert_rev(&conn, "r-old", "k1", 365);
    assert_eq!(
        gc_memory_revisions_by_retention_days(&conn, None).unwrap(),
        0,
        "None retention must not delete anything"
    );
    assert_eq!(count(&conn), 1);
}

#[test]
fn gc_deletes_entries_past_retention_window() {
    let conn = test_db();
    // Seed more than keep-last-N so the per-key safeguard doesn't
    // protect the ancient rows from deletion.
    for i in 0..40 {
        insert_rev(&conn, &format!("old-{i}"), "k1", 365);
    }
    insert_rev(&conn, "fresh", "k1", 0);

    let deleted = gc_memory_revisions_by_retention_days(&conn, Some(30)).unwrap();
    assert!(
        deleted >= 20,
        "at least half of the old rows should be past-retention once keep-last-N is subtracted"
    );
    assert!(
        count(&conn) <= 21,
        "fresh row + keep-last-N survivors remain"
    );
}

#[test]
fn gc_respects_keep_last_n_safeguard_per_key() {
    let conn = test_db();
    // Write 25 revisions all 365 days old. With retention=30, every
    // row is past the window, but the keep-last-N safeguard must
    // preserve the most recent 20.
    for i in 0..25 {
        insert_rev(&conn, &format!("r-{i:02}"), "k1", 365 - i64::from(i));
    }

    let before = count(&conn);
    assert_eq!(before, 25);
    gc_memory_revisions_by_retention_days(&conn, Some(30)).unwrap();
    let after = count(&conn);
    assert_eq!(
        after,
        u64::from(MEMORY_REVISION_KEEP_LAST_N_PER_KEY),
        "per-key keep-last-N must be preserved even when all rows are past the window"
    );
}

#[test]
fn gc_preserves_recent_rows() {
    let conn = test_db();
    insert_rev(&conn, "fresh", "k1", 0);
    let deleted = gc_memory_revisions_by_retention_days(&conn, Some(30)).unwrap();
    assert_eq!(deleted, 0);
    assert_eq!(count(&conn), 1);
}

/// The GC SQL is
/// `AND created_at < strftime('now', '-N days')`, so:
/// - `created_at = cutoff` → kept (equality fails `<`).
/// - `created_at = cutoff - 1ms` (1 ms older) → deleted.
/// - `created_at = cutoff + 1ms` (1 ms younger) → kept.
///
/// Each boundary test seeds MORE than KEEP_LAST_N_PER_KEY revisions
/// for the same key so the keep-last safeguard doesn't mask the
/// cutoff behavior we're probing.
///
const TEST_RETENTION_CUTOFF_ISO: &str = "2026-01-08T00:00:00.000Z";
const TEST_ONE_MS_BEFORE_CUTOFF_ISO: &str = "2026-01-07T23:59:59.999Z";
const TEST_ONE_MS_AFTER_CUTOFF_ISO: &str = "2026-01-08T00:00:00.001Z";

fn insert_rev_at_iso(conn: &Connection, id: &str, key: &str, created_at: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO memories (id, key, content, version, updated_at) \
         VALUES (?1, ?2, 'seed', '0000000000000_0000_0000000000000000', \
         strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
        rusqlite::params![lorvex_domain::new_entity_id_string(), key],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO memory_revisions \
         (id, memory_key, content, operation, actor, version, created_at) \
         VALUES (?1, ?2, 'v', 'upsert', 'ai', \
                 '1000000000000_0000_deadbeefdeadbeef', \
                 ?3)",
        rusqlite::params![id, key, created_at],
    )
    .unwrap();
}

#[test]
fn gc_deletes_memory_revision_one_ms_before_cutoff() {
    let conn = test_db();
    // KEEP_LAST_N+1 older siblings on the same key so keep-last
    // doesn't protect the probe row.
    for i in 0..=MEMORY_REVISION_KEEP_LAST_N_PER_KEY {
        insert_rev(&conn, &format!("newer-{i:02}"), "kprobe", 1);
    }
    insert_rev_at_iso(
        &conn,
        "one-ms-before-cutoff",
        "kprobe",
        TEST_ONE_MS_BEFORE_CUTOFF_ISO,
    );

    let deleted = gc_memory_revisions_before_cutoff_iso(&conn, TEST_RETENTION_CUTOFF_ISO).unwrap();
    assert!(deleted >= 1, "the 1ms-older probe row must be deleted");
    let probe_alive: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE id = 'one-ms-before-cutoff'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(probe_alive, 0);
}

#[test]
fn gc_preserves_memory_revision_one_ms_after_cutoff() {
    let conn = test_db();
    insert_rev_at_iso(
        &conn,
        "one-ms-after-cutoff",
        "kprobe",
        TEST_ONE_MS_AFTER_CUTOFF_ISO,
    );

    let deleted = gc_memory_revisions_before_cutoff_iso(&conn, TEST_RETENTION_CUTOFF_ISO).unwrap();
    assert_eq!(deleted, 0, "row 1 ms younger than cutoff must survive GC");
    assert_eq!(count(&conn), 1);
}

#[test]
fn gc_preserves_memory_revision_exactly_at_cutoff() {
    let conn = test_db();
    insert_rev_at_iso(
        &conn,
        "exactly-at-cutoff",
        "kprobe",
        TEST_RETENTION_CUTOFF_ISO,
    );

    let deleted = gc_memory_revisions_before_cutoff_iso(&conn, TEST_RETENTION_CUTOFF_ISO).unwrap();
    assert_eq!(deleted, 0, "equality must not be treated as past cutoff");
    assert_eq!(count(&conn), 1);
}

#[test]
fn gc_isolates_keys_so_one_key_does_not_protect_another() {
    let conn = test_db();
    // Key A: 25 ancient rows (keep-last-N will protect 20).
    for i in 0..25 {
        insert_rev(&conn, &format!("a-{i:02}"), "kA", 365 - i64::from(i));
    }
    // Key B: 5 ancient rows (all 5 protected by keep-last-N).
    for i in 0..5 {
        insert_rev(&conn, &format!("b-{i:02}"), "kB", 365 - i64::from(i));
    }

    gc_memory_revisions_by_retention_days(&conn, Some(30)).unwrap();
    let a_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'kA'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    let b_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM memory_revisions WHERE memory_key = 'kB'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(a_count, i64::from(MEMORY_REVISION_KEEP_LAST_N_PER_KEY));
    assert_eq!(b_count, 5, "key B must retain all 5 of its rows");
}
