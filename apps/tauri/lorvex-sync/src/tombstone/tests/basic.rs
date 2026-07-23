//! Basic CRUD: create, read, replace, and remove a tombstone.

use super::support::*;

#[test]
fn create_and_get_tombstone() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let ts = get_tombstone(&conn, naming::ENTITY_TASK, "task-001")
        .unwrap()
        .expect("tombstone should exist");

    assert_eq!(ts.entity_type, naming::ENTITY_TASK);
    assert_eq!(ts.entity_id, "task-001");
    assert_eq!(ts.version, "1711234567890_0000_a1b2c3d4a1b2c3d4");
    assert_eq!(ts.deleted_at, "2026-03-23T12:00:00.000Z");
    assert!(ts.redirect_entity_id.is_none());
    assert!(ts.redirect_entity_type.is_none());
}

#[test]
fn get_tombstone_returns_none_for_missing() {
    let conn = test_db();

    let result = get_tombstone(&conn, naming::ENTITY_TASK, "nonexistent").unwrap();
    assert!(result.is_none());
}

#[test]
fn is_tombstoned_true() {
    let conn = test_db();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-001").unwrap());
}

#[test]
fn is_tombstoned_false() {
    let conn = test_db();
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-001").unwrap());
}

#[test]
fn replace_on_re_tombstone() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Re-tombstone with a newer version.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567999_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T13:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let ts = get_tombstone(&conn, naming::ENTITY_TASK, "task-001")
        .unwrap()
        .expect("tombstone should exist");
    assert_eq!(ts.version, "1711234567999_0000_a1b2c3d4a1b2c3d4");
    assert_eq!(ts.deleted_at, "2026-03-23T13:00:00.000Z");

    // Should still be exactly one row.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = ?2",
            params![naming::ENTITY_TASK, "task-001"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn remove_tombstone_success() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let removed = remove_tombstone(&conn, naming::ENTITY_TASK, "task-001").unwrap();
    assert!(removed);
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-001").unwrap());
}

#[test]
fn remove_tombstone_returns_false_for_missing() {
    let conn = test_db();
    let removed = remove_tombstone(&conn, naming::ENTITY_TASK, "nonexistent").unwrap();
    assert!(!removed);
}

#[test]
fn tombstones_for_different_entity_types_are_independent() {
    let conn = test_db();

    // Same entity_id, different entity_type.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "shared-id",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T12:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    create_tombstone(
        &conn,
        naming::ENTITY_LIST,
        "shared-id",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
        "2026-03-23T13:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "shared-id").unwrap());
    assert!(is_tombstoned(&conn, naming::ENTITY_LIST, "shared-id").unwrap());

    let task_ts = get_tombstone(&conn, naming::ENTITY_TASK, "shared-id")
        .unwrap()
        .unwrap();
    let list_ts = get_tombstone(&conn, naming::ENTITY_LIST, "shared-id")
        .unwrap()
        .unwrap();

    assert_eq!(task_ts.version, "1711234567890_0000_a1b2c3d4a1b2c3d4");
    assert_eq!(list_ts.version, "1711234567891_0000_a1b2c3d4a1b2c3d4");
}
