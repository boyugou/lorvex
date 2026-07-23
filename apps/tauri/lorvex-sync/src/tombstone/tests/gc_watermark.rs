//! Watermark-based GC: `gc_tombstones_watermark`. Covers the
//! all-active-synced case, the one-device-behind block, inactive
//! exclusion, the unconditional ancient-tombstone safety net, the
//! NULL-version active-device suppression, and the no-watermark
//! fallback to the doubled-inactive-threshold horizon.

use super::support::*;

#[test]
fn watermark_all_active_devices_synced_past_tombstone() {
    let conn = test_db();

    // Tombstone from 2020.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-old",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Two active devices, both synced well past the tombstone.
    insert_device_cursor(&conn, "device-A", "2026-03-20T00:00:00.000Z");
    insert_device_cursor(&conn, "device-B", "2026-03-22T00:00:00.000Z");

    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 1);
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-old").unwrap());
}

#[test]
fn watermark_one_active_device_behind_prevents_gc() {
    let conn = test_db();

    // Tombstone from a recent date.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-recent",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-15T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Device A synced past the tombstone (high HLC), device B has NOT (low HLC).
    insert_device_cursor_with_version(
        &conn,
        "device-A",
        "2026-03-20T00:00:00.000Z",
        "9999999999999_0000_decafdec00000000",
    );
    insert_device_cursor_with_version(
        &conn,
        "device-B",
        "2026-06-01T00:00:00.000Z",
        "0000000000001_0000_decafdec00000000",
    );

    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 0);
    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-recent").unwrap());
}

#[test]
fn watermark_inactive_device_excluded_from_watermark() {
    let conn = test_db();

    // Tombstone from 2025.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-mid",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2025-06-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Device A is active (recent sync), synced past the tombstone.
    insert_device_cursor(&conn, "device-A", "2026-03-20T00:00:00.000Z");
    // Device B is INACTIVE (last synced 2+ years ago -- well beyond 90 days).
    insert_device_cursor(&conn, "device-B", "2024-01-01T00:00:00.000Z");

    // The watermark should be device-A's cursor only (device-B is inactive).
    // Tombstone from 2025-06-01 < watermark 2026-03-20 => GC'd.
    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 1);
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-mid").unwrap());
}

#[test]
fn watermark_unconditional_gc_for_very_old_tombstones() {
    let conn = test_db();

    // Tombstone from 2020 -- older than 365 days.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-ancient",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // No devices at all.
    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 1);
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-ancient").unwrap());
}

#[test]
fn watermark_no_devices_only_max_retention_applies() {
    let conn = test_db();

    // Recent tombstone (should NOT be GC'd).
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-recent",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        "2026-03-15T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Ancient tombstone (should be GC'd by max retention).
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-ancient",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
        "2020-01-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // No devices registered.
    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 1);

    // Recent tombstone is preserved.
    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-recent").unwrap());
    // Ancient tombstone was GC'd.
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-ancient").unwrap());
}

/// an active device with NULL
/// `last_applied_version` MUST suppress the version-based GC step
/// entirely. The previous shape filtered the NULL out of the MIN
/// and silently used a fabricated watermark from the non-NULL
/// subset, GC'ing tombstones that the NULL device may not have
/// observed. The fallback (180-day) horizon still runs, but a
/// tombstone within that window must survive.
#[test]
fn watermark_active_device_with_null_version_suppresses_version_gc() {
    let conn = test_db();

    // Tombstone at a HIGH HLC version. If a fabricated watermark
    // were used (MIN over the non-NULL subset = the high version),
    // this tombstone would be GC'd. With the fix it must survive.
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-recent",
        "5000000000000_0000_a1b2c3d4a1b2c3d4",
        "2026-04-01T00:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    // Device A has applied a high version.
    insert_device_cursor_with_version(
        &conn,
        "device-A",
        "2026-04-20T00:00:00.000Z",
        "9999999999999_0000_decafdec00000000",
    );
    // Device B is active but has NULL last_applied_version (fresh
    // cursor, never applied a remote envelope) — must suppress
    // the watermark step.
    upsert_device_cursor_with_version(&conn, "device-B", "2026-04-20T00:00:00.000Z", None).unwrap();

    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 0, "NULL active device must suppress version GC");
    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-recent").unwrap());
}

/// with no usable watermark
/// (single-device install, or every active device is NULL),
/// tombstones older than `DEVICE_INACTIVE_THRESHOLD_DAYS × 2`
/// (180 days) must be reaped by the fallback horizon — not
/// stuck behind the 365-day absolute safety net.
#[test]
fn watermark_no_watermark_falls_back_to_double_inactive_threshold() {
    let conn = test_db();

    // Tombstone from 200 days ago — past the 180-day fallback
    // horizon, but well within the 365-day absolute safety net.
    // Pre-fix this would survive; with M2 it's reaped.
    let two_hundred_days_ago: String = conn
        .query_row(
            "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-200 days')",
            [],
            |r| r.get(0),
        )
        .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-200d",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
        &two_hundred_days_ago,
        None,
        None,
    )
    .unwrap();

    // Tombstone from 30 days ago — well within the fallback
    // horizon. Must survive.
    let thirty_days_ago: String = conn
        .query_row(
            "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-30 days')",
            [],
            |r| r.get(0),
        )
        .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "task-30d",
        "1711234567891_0000_a1b2c3d4a1b2c3d4",
        &thirty_days_ago,
        None,
        None,
    )
    .unwrap();

    // No devices at all — the no-watermark path.
    let deleted = gc_tombstones_watermark(&conn).unwrap();
    assert_eq!(deleted, 1);
    assert!(!is_tombstoned(&conn, naming::ENTITY_TASK, "task-200d").unwrap());
    assert!(is_tombstoned(&conn, naming::ENTITY_TASK, "task-30d").unwrap());
}
