//! Tombstone version monotonicity (LWW): newer wins, older never
//! overwrites — including the redirect variant.

use super::support::*;

#[test]
fn tombstone_monotonicity_old_does_not_overwrite_new() {
    let conn = test_db();
    // Write a newer tombstone first.
    create_tombstone(
        &conn,
        "task",
        "t1",
        "1711234567899_0000_a1b2c3d4a1b2c3d4",
        "2026-03-25T00:00:00Z",
        None,
        None,
    )
    .unwrap();
    // Attempt to overwrite with an older version.
    create_tombstone(
        &conn,
        "task",
        "t1",
        "1711234567800_0000_a1b2c3d4a1b2c3d4",
        "2026-03-20T00:00:00Z",
        None,
        None,
    )
    .unwrap();
    let ts = get_tombstone(&conn, "task", "t1").unwrap().unwrap();
    assert_eq!(
        ts.version, "1711234567899_0000_a1b2c3d4a1b2c3d4",
        "newer tombstone must survive"
    );
}

#[test]
fn tombstone_monotonicity_newer_overwrites_old() {
    let conn = test_db();
    create_tombstone(
        &conn,
        "task",
        "t1",
        "1711234567800_0000_a1b2c3d4a1b2c3d4",
        "2026-03-20T00:00:00Z",
        None,
        None,
    )
    .unwrap();
    create_tombstone(
        &conn,
        "task",
        "t1",
        "1711234567899_0000_a1b2c3d4a1b2c3d4",
        "2026-03-25T00:00:00Z",
        None,
        None,
    )
    .unwrap();
    let ts = get_tombstone(&conn, "task", "t1").unwrap().unwrap();
    assert_eq!(ts.version, "1711234567899_0000_a1b2c3d4a1b2c3d4");
}

#[test]
fn tombstone_monotonicity_redirect_also_versioned() {
    let conn = test_db();
    create_tombstone(
        &conn,
        "tag",
        "t1",
        "1711234567899_0000_a1b2c3d4a1b2c3d4",
        "2026-03-25T00:00:00Z",
        Some("t2"),
        Some("tag"),
    )
    .unwrap();
    // Older non-redirect tombstone must not overwrite.
    create_tombstone(
        &conn,
        "tag",
        "t1",
        "1711234567800_0000_a1b2c3d4a1b2c3d4",
        "2026-03-20T00:00:00Z",
        None,
        None,
    )
    .unwrap();
    let ts = get_tombstone(&conn, "tag", "t1").unwrap().unwrap();
    assert_eq!(
        ts.redirect_entity_id.as_deref(),
        Some("t2"),
        "redirect must survive"
    );
}
