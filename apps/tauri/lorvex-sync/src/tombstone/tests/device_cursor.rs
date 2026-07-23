//! Device-cursor primitive: forward-only `last_sync_at` updates.

use super::support::*;

#[test]
fn upsert_device_cursor_updates_forward_only() {
    let conn = test_db();

    upsert_device_cursor(&conn, "dev-1", "2026-03-20T00:00:00.000Z").unwrap();

    // Try to set an older timestamp -- should NOT regress.
    upsert_device_cursor(&conn, "dev-1", "2026-03-10T00:00:00.000Z").unwrap();

    let ts: String = conn
        .query_row(
            "SELECT last_sync_at FROM sync_device_cursors WHERE device_id = 'dev-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(ts, "2026-03-20T00:00:00.000Z");
}
