use rusqlite::Connection;

/// Migration 004 uses the SQLite table-rebuild idiom (CREATE _new /
/// INSERT SELECT / DROP old / RENAME). A future accidental column
/// drop in the INSERT SELECT would silently lose data — CI would
/// pass because schema existence checks don't look at row content.
/// This test seeds representative rows under the pre-004 schema and
/// asserts all rows + all fields survive the rebuild.
#[test]
fn migration_004_preserves_error_log_data_through_table_rebuild() {
    use rusqlite::params;

    let conn = Connection::open_in_memory().unwrap();

    // Apply migrations 1..=3 (just before 004).
    let up_to_three: Vec<_> = lorvex_store::schema::all_migrations()
        .into_iter()
        .filter(|m| m.version <= 3)
        .collect();
    lorvex_store::apply_migrations(&conn, &up_to_three).unwrap();

    // Seed error_logs with every column populated.
    conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at) \
         VALUES ('e1', 'sync.filesystem_bridge', 'error', 'boom', 'stack here', '2026-03-01T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at) \
         VALUES ('e2', 'platform.badge', 'warn', 'badge stalled', NULL, '2026-03-02T00:00:00Z')",
        params![],
    )
    .unwrap();

    // Apply migration 004 (and the rest).
    lorvex_store::apply_migrations(&conn, &lorvex_store::schema::all_migrations()).unwrap();

    // Both rows must survive with all fields intact.
    let rows: Vec<(String, String, String, String, Option<String>, String)> = conn
        .prepare(
            "SELECT id, source, level, message, details, created_at FROM error_logs ORDER BY id",
        )
        .unwrap()
        .query_map([], |r| {
            Ok((
                r.get(0)?,
                r.get(1)?,
                r.get(2)?,
                r.get(3)?,
                r.get(4)?,
                r.get(5)?,
            ))
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();

    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].0, "e1");
    assert_eq!(rows[0].1, "sync.filesystem_bridge");
    assert_eq!(rows[0].2, "error");
    assert_eq!(rows[0].3, "boom");
    assert_eq!(rows[0].4.as_deref(), Some("stack here"));
    assert_eq!(rows[1].0, "e2");
    assert_eq!(rows[1].4, None);

    // Also verify the CHECK constraint from 004 is in force now.
    let bad_level = conn.execute(
        "INSERT INTO error_logs (id, source, level, message, details, created_at) \
         VALUES ('e3', 'src', 'critical', 'bad', NULL, '2026-03-03T00:00:00Z')",
        [],
    );
    assert!(
        bad_level.is_err(),
        "migration 004 CHECK must reject levels outside debug|info|warn|error"
    );
}
