use super::*;
use crate::test_support::test_conn;

#[test]
fn set_preference_inserts_new_key() {
    let conn = test_conn();
    let wrote =
        set_preference(&conn, "theme", "\"dark\"", "v1", "2026-03-27T00:00:00.000Z").unwrap();
    assert!(wrote, "fresh insert should report wrote=true");

    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            ["theme"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(value, "\"dark\"");
}

#[test]
fn set_preference_upserts_existing_key() {
    let conn = test_conn();
    set_preference(&conn, "theme", "\"dark\"", "v1", "2026-03-27T00:00:00.000Z").unwrap();
    let wrote = set_preference(
        &conn,
        "theme",
        "\"light\"",
        "v2",
        "2026-03-27T01:00:00.000Z",
    )
    .unwrap();
    assert!(wrote, "newer-version upsert should report wrote=true");

    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            ["theme"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(value, "\"light\"");
}

/// a stale-version write must NOT clobber a newer
/// row. Cross-device LWW correctness depends on this gate.
#[test]
fn set_preference_rejects_stale_version_write() {
    let conn = test_conn();
    set_preference(&conn, "theme", "\"dark\"", "v2", "2026-03-27T00:00:00.000Z").unwrap();
    // Stale write tries to overwrite v2 with v1.
    let wrote = set_preference(
        &conn,
        "theme",
        "\"light\"",
        "v1",
        "2026-03-26T00:00:00.000Z",
    )
    .unwrap();
    assert!(!wrote, "stale-version upsert must report wrote=false");

    // The row must still hold the v2 value.
    let (value, version): (String, String) = conn
        .query_row(
            "SELECT value, version FROM preferences WHERE key = ?1",
            ["theme"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(value, "\"dark\"");
    assert_eq!(version, "v2");
}

#[test]
fn clear_preference_deletes_existing_when_version_strictly_newer() {
    let conn = test_conn();
    set_preference(&conn, "key1", "val1", "v1", "2026-03-27T00:00:00.000Z").unwrap();
    // v2 > v1 → clear succeeds, reports one row deleted.
    assert_eq!(clear_preference(&conn, "key1", "v2").unwrap(), 1);
}

#[test]
fn clear_preference_returns_zero_for_missing() {
    let conn = test_conn();
    assert_eq!(clear_preference(&conn, "nonexistent", "v9").unwrap(), 0);
}

/// stale-version clear must NOT clobber a newer write.
#[test]
fn clear_preference_rejects_stale_version() {
    let conn = test_conn();
    set_preference(&conn, "theme", "\"dark\"", "v3", "2026-03-27T00:00:00.000Z").unwrap();
    // Stale clear with v2 < v3 must be a no-op (0 rows changed).
    assert_eq!(clear_preference(&conn, "theme", "v2").unwrap(), 0);

    // Row must still exist, untouched.
    let value: String = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            ["theme"],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(value, "\"dark\"");
}

/// equal-version clear is also rejected (strict-greater).
#[test]
fn clear_preference_rejects_equal_version() {
    let conn = test_conn();
    set_preference(&conn, "theme", "\"dark\"", "v2", "2026-03-27T00:00:00.000Z").unwrap();
    assert_eq!(clear_preference(&conn, "theme", "v2").unwrap(), 0);
}
