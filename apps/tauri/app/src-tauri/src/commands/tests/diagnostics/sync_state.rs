use super::support::*;

#[test]
fn read_sync_conflict_log_returns_newest_first_with_limit() {
    let conn = setup_sync_test_conn();
    insert_conflict_row(&conn, "task-a", "2026-04-01T00:00:00.000Z", "lww");
    insert_conflict_row(&conn, "task-b", "2026-04-02T00:00:00.000Z", "tag_merge");
    insert_conflict_row(&conn, "task-c", "2026-04-03T00:00:00.000Z", "lww");

    // No filter: newest row (highest id) comes first.
    let rows = read_sync_conflict_log(&conn, Some(50), None, None).expect("read conflict log");
    assert_eq!(rows.len(), 3);
    assert_eq!(rows[0].entity_id, "task-c");
    assert_eq!(rows[0].kind, "lww");
    assert_eq!(rows[0].local_version, "1711234567891_0000_aaaaaaaaaaaaaaaa");
    assert_eq!(
        rows[0].remote_version,
        "1711234567890_0000_bbbbbbbbbbbbbbbb"
    );
    assert_eq!(rows[2].entity_id, "task-a");

    // Limit clamps the returned slice without altering order.
    let limited =
        read_sync_conflict_log(&conn, Some(2), None, None).expect("read conflict log with limit");
    assert_eq!(limited.len(), 2);
    assert_eq!(limited[0].entity_id, "task-c");
    assert_eq!(limited[1].entity_id, "task-b");

    // Time-window filter: only rows with resolved_at >= since_iso.
    let filtered = read_sync_conflict_log(&conn, Some(50), Some("2026-04-02T00:00:00.000Z"), None)
        .expect("read conflict log with since filter");
    let ids: Vec<&str> = filtered.iter().map(|r| r.entity_id.as_str()).collect();
    assert_eq!(ids, vec!["task-c", "task-b"]);

    let device_filtered = read_sync_conflict_log(&conn, Some(50), None, Some("device-remote"))
        .expect("read conflict log with device filter");
    assert_eq!(device_filtered.len(), 3);

    let missing_device_filtered =
        read_sync_conflict_log(&conn, Some(50), None, Some("device-missing"))
            .expect("read conflict log with missing device filter");
    assert!(missing_device_filtered.is_empty());

    // Empty / whitespace since_iso is treated as "no filter".
    let unfiltered = read_sync_conflict_log(&conn, Some(50), Some("   "), None)
        .expect("read conflict log with empty since");
    assert_eq!(unfiltered.len(), 3);
}
