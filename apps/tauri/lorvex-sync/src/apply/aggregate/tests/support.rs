use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub(super) use crate::test_db;

/// Construct a monotonically increasing HLC string per call so
/// sequential upserts in the same test do not collide on the
/// version-compare gate.
pub(super) fn next_version() -> String {
    static COUNTER: AtomicUsize = AtomicUsize::new(0);
    let base = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(1_711_234_567_890, |d| d.as_millis() as u64);
    let n = COUNTER.fetch_add(1, Ordering::SeqCst) as u64;
    format!("{:013}_{:04}_aaaaaaaaaaaaaaaa", base.saturating_add(n), 0)
}

pub(super) fn seed_list(conn: &rusqlite::Connection, list_id: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, created_at, updated_at, version)
         VALUES (?1, 'Inbox', '2026-03-23T12:00:00.000Z', '2026-03-23T12:00:00.000Z', ?2)",
        rusqlite::params![list_id, next_version()],
    )
    .unwrap();
}
