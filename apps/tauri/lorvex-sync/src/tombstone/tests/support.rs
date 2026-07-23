//! Shared fixtures for the tombstone test suite.
//!
//! Re-exports the production primitives every split file relies on so
//! the per-domain modules can `use super::support::*;` and stay
//! focused on a single concern.

pub(super) use crate::test_db;
pub(super) use lorvex_domain::naming;
pub(super) use rusqlite::{params, Connection};

pub(super) use super::super::gc::{gc_tombstones_fixed, gc_tombstones_watermark};
pub(super) use super::super::read::{get_tombstone, is_tombstoned};
pub(super) use super::super::write::{
    create_tombstone, remove_tombstone, upsert_device_cursor, upsert_device_cursor_with_version,
};

/// Insert a device cursor at a high HLC so it is "past" most
/// tombstones in tests.
pub(super) fn insert_device_cursor(conn: &Connection, device_id: &str, last_sync_at: &str) {
    let version = "9999999999999_0000_decafdec00000000";
    upsert_device_cursor_with_version(conn, device_id, last_sync_at, Some(version)).unwrap();
}

pub(super) fn insert_device_cursor_with_version(
    conn: &Connection,
    device_id: &str,
    last_sync_at: &str,
    version: &str,
) {
    upsert_device_cursor_with_version(conn, device_id, last_sync_at, Some(version)).unwrap();
}
