use super::support::*;

#[test]
fn read_error_logs_since_iso_filter_narrows_the_window() {
    let conn = setup_sync_test_conn();

    // Three rows at different timestamps.
    let old_ts = "2026-03-20T00:00:00.000Z";
    let middle_ts = "2026-04-01T12:00:00.000Z";
    let fresh_ts = "2026-04-10T00:00:00.000Z";
    for (id, ts) in [
        ("old-1", old_ts),
        ("middle-1", middle_ts),
        ("fresh-1", fresh_ts),
    ] {
        conn.execute(
            "INSERT INTO error_logs (id, source, level, message, details, created_at)
             VALUES (?1, 'frontend.test', 'error', 'boom', NULL, ?2)",
            params![id, ts],
        )
        .expect("insert error_logs row");
    }

    // No filter: all rows.
    let all = read_error_logs(&conn, Some(50), None).expect("read all");
    assert_eq!(all.len(), 3);

    // since = middle timestamp: drops the old one.
    let recent = read_error_logs(&conn, Some(50), Some(middle_ts)).expect("read since middle");
    let ids: Vec<&str> = recent.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, vec!["fresh-1", "middle-1"]);

    // since > newest: empty.
    let none = read_error_logs(&conn, Some(50), Some("2099-01-01T00:00:00.000Z"))
        .expect("read since far future");
    assert!(none.is_empty());

    // Empty since: ignored (acts as no filter), preserves newest-first order.
    let ignore = read_error_logs(&conn, Some(50), Some("")).expect("empty since");
    assert_eq!(ignore.len(), 3);
    assert_eq!(ignore[0].id, "fresh-1");
}

#[test]
fn error_logs_command_does_not_advertise_ignored_source_device_filter() {
    let source = include_str!("../../diagnostics/error_logs.rs");
    assert!(
        !source.contains("source_device_id: Option<String>"),
        "get_error_logs must not expose an ignored source_device_id filter"
    );
    assert!(
        !source.contains("let _ = source_device_id"),
        "get_error_logs must not silently discard source_device_id"
    );
}

#[test]
fn read_diagnostics_device_ids_returns_distinct_ids_ordered_by_recency() {
    let conn = setup_sync_test_conn();
    let insert_changelog =
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id,
                                   summary, initiated_by, mcp_tool, source_device_id)
         VALUES (?1, ?2, 'update', 'task', NULL, ?3, 'codex', NULL, ?4)";
    // device-a: older
    conn.execute(
        insert_changelog,
        params!["cl-a1", "2026-04-01T00:00:00.000Z", "entry-a1", "device-a"],
    )
    .expect("insert changelog row a");
    // device-b: newer — should come first
    conn.execute(
        insert_changelog,
        params!["cl-b1", "2026-04-05T00:00:00.000Z", "entry-b1", "device-b"],
    )
    .expect("insert changelog row b");
    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id,
                                   summary, initiated_by, mcp_tool, source_device_id)
         VALUES (?1, ?2, 'update', 'task', NULL, ?3, 'human', NULL, ?4)",
        params![
            "cl-human",
            "2026-04-20T00:00:00.000Z",
            "human entry",
            "device-human",
        ],
    )
    .expect("insert human changelog row");
    // device-a again, much newer — now device-a moves ahead of device-b
    conn.execute(
        insert_changelog,
        params!["cl-a2", "2026-04-10T00:00:00.000Z", "entry-a2", "device-a"],
    )
    .expect("insert changelog row a2");
    // Null / empty device_id is ignored (wouldn't appear in dropdown).
    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id,
                                   summary, initiated_by, mcp_tool, source_device_id)
         VALUES (?1, ?2, 'update', 'task', NULL, ?3, 'codex', NULL, NULL)",
        params!["cl-null", "2026-04-11T00:00:00.000Z", "null-device"],
    )
    .expect("insert changelog row with null device id");
    conn.execute(
        "INSERT INTO sync_conflict_log
            (entity_type, entity_id, winner_version, loser_version,
             loser_device_id, loser_payload, resolved_at, resolution_type)
         VALUES ('task', 'task-c', ?1, ?2, 'device-conflict-only', NULL, ?3, 'lww')",
        params![
            "1711234567891_0000_aaaaaaaaaaaaaaaa",
            "1711234567890_0000_bbbbbbbbbbbbbbbb",
            "2026-04-12T00:00:00.000Z",
        ],
    )
    .expect("insert conflict-only device row");
    conn.execute(
        "INSERT INTO sync_conflict_log
            (entity_type, entity_id, winner_version, loser_version,
             loser_device_id, loser_payload, resolved_at, resolution_type)
         VALUES ('task', 'task-a', ?1, ?2, 'device-a', NULL, ?3, 'lww')",
        params![
            "1711234567891_0000_aaaaaaaaaaaaaaaa",
            "1711234567890_0000_bbbbbbbbbbbbbbbb",
            "2026-04-03T00:00:00.000Z",
        ],
    )
    .expect("insert older duplicate conflict device row");

    let ids = read_diagnostics_device_ids(&conn).expect("read device ids");
    assert_eq!(
        ids,
        vec![
            "device-conflict-only".to_string(),
            "device-a".to_string(),
            "device-b".to_string()
        ]
    );
    assert!(
        !ids.iter().any(|id| id == "device-human"),
        "human-originated ai_changelog devices must not appear in diagnostics device filters"
    );
}

#[test]
fn read_unseen_error_log_count_respects_last_viewed_marker() {
    // the sidebar Settings badge counts rows written
    // after the user last opened Settings → Data → Diagnostics on
    // this device. Before the marker is ever stored, every existing
    // row is unseen (badge surfaces a fresh install with
    // pre-populated errors); after marking, only strictly-later rows
    // count.
    let conn = setup_sync_test_conn();

    append_error_log_internal(
        &conn,
        "frontend.window",
        "old failure",
        None,
        Some("error".to_string()),
    )
    .expect("append old log");
    // Force the older row's timestamp to an earlier instant than the
    // mark-viewed clock will record, since sync_timestamp_now() has
    // millisecond resolution and two back-to-back writes can share a
    // timestamp on a fast machine.
    conn.execute(
        "UPDATE error_logs SET created_at = ?1 WHERE source = 'frontend.window'",
        params!["2026-04-18T00:00:00.000Z"],
    )
    .expect("backdate old log");

    assert_eq!(
        read_unseen_error_log_count(&conn).expect("count unseen"),
        1,
        "with no marker, the existing row counts as unseen"
    );

    // Mark viewed: write a canonical JSON-string timestamp after the
    // existing row, matching what mark_error_logs_viewed does in
    // production.
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = ?2",
        params![
            DEV_ERROR_LOGS_LAST_VIEWED_AT,
            "\"2026-04-19T00:00:00.000Z\""
        ],
    )
    .expect("seed last_viewed");

    assert_eq!(
        read_unseen_error_log_count(&conn).expect("count after mark"),
        0,
        "a row older than the marker is not unseen"
    );

    // New row after the marker: should count as unseen again.
    append_error_log_internal(
        &conn,
        "frontend.window",
        "new failure",
        None,
        Some("error".to_string()),
    )
    .expect("append new log");
    conn.execute(
        "UPDATE error_logs SET created_at = ?1 WHERE message = 'new failure'",
        params!["2026-04-20T00:00:00.000Z"],
    )
    .expect("set new log timestamp");

    assert_eq!(
        read_unseen_error_log_count(&conn).expect("count new unseen"),
        1,
        "a row newer than the marker is unseen again"
    );
}
