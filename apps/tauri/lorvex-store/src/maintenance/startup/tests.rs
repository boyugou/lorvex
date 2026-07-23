use super::run_startup_preferences_integrity;

#[test]
fn startup_preferences_integrity_flags_non_json_rows_without_touching_valid_ones() {
    let conn = crate::test_support::test_conn();
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) \
         VALUES ('corrupt.key', 'not-a-json-value', '0000000000000_0000_a0a0a0a0a0a0a0', '2026-04-18T09:00:00Z')",
        [],
    )
    .expect("seed corrupt pref");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) \
         VALUES ('ok.key', '\"valid-string\"', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-18T09:00:00Z')",
        [],
    )
    .expect("seed valid pref");

    let flagged = run_startup_preferences_integrity(&conn).expect("integrity pass ok");
    assert_eq!(flagged, 1, "only the corrupt row should be flagged");

    let log_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM error_logs WHERE source = 'preferences.corruption'",
            [],
            |row| row.get(0),
        )
        .expect("count error_logs");
    assert_eq!(log_count, 1, "one error_logs row per corrupt preference");

    let logged_msg: String = conn
        .query_row(
            "SELECT message FROM error_logs WHERE source = 'preferences.corruption'",
            [],
            |row| row.get(0),
        )
        .expect("read logged message");
    assert!(
        logged_msg.contains("corrupt.key"),
        "logged message must name the bad key: {logged_msg}"
    );
}
