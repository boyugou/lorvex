//! Fixed-retention GC fallback (test-only): `gc_tombstones_fixed`.

use super::support::*;

#[test]
fn gc_tombstones_fixed_deletes_old() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-old",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z", // very old
        None,
        None,
    )
    .unwrap();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-recent",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
        "2099-01-01T00:00:00.000Z", // far in the future
        None,
        None,
    )
    .unwrap();

    let deleted = gc_tombstones_fixed(&conn, 90).unwrap();
    assert_eq!(deleted, 1);

    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-old").unwrap());
    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-recent").unwrap());
}

#[test]
fn gc_tombstones_fixed_with_zero_retention_deletes_all_past() {
    let conn = test_db();

    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-001",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let deleted = gc_tombstones_fixed(&conn, 0).unwrap();
    assert_eq!(deleted, 1);
}
