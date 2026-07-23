//! Tombstone operations — create, query, and garbage-collect delete markers.
//!
//! The `sync_tombstones` table records that an entity has been deleted. This is
//! used by the sync pipeline to:
//! - Prevent re-applying an upsert for a deleted entity (unless the upsert has
//!   a strictly newer version)
//! - Redirect references from merged entities (tag merge, recurrence dedup)
//!
//! ## Module layout
//!
//! - [`read`] — read-side helpers: [`get_tombstone`], [`is_tombstoned`].
//! - [`write`] — write-side primitives: [`create_tombstone`],
//!   [`remove_tombstone`], [`upsert_device_cursor`],
//!   [`upsert_device_cursor_with_version`].
//! - [`gc`] — garbage-collection sweeps: [`gc_tombstones_watermark`] (primary
//!   API) and the test-only fixed-retention fallback.
//!
//! ## Garbage Collection
//!
//! The primary GC mechanism is watermark-based ([`gc_tombstones_watermark`]):
//! tombstones are only removed when ALL active devices have synced past them.
//! Devices inactive for `DEVICE_INACTIVE_THRESHOLD_DAYS` are excluded from
//! the watermark calculation. Tombstones older than `TOMBSTONE_MAX_RETENTION_DAYS`
//! are unconditionally removed as an absolute safety net.
//!
//! A simpler fixed-retention fallback is also available (test-only).
//!
//! See spec Section 7: Timestamp, Version, and Delete Semantics.

use serde::{Deserialize, Serialize};

pub mod gc;
pub mod read;
pub mod write;

#[cfg(test)]
mod tests;

// ---------------------------------------------------------------------------
// Intentional public API hub for tombstone operations.
//
// Sync callers use `lorvex_sync::tombstone::*` as the stable delete-marker
// boundary; the sibling modules below remain implementation folders for read,
// write, and garbage-collection concerns.
// ---------------------------------------------------------------------------

pub use gc::gc_tombstones_watermark;
pub use read::get_tombstone;
#[cfg(test)]
pub(crate) use read::is_tombstoned;
pub use write::{
    create_tombstone, remove_tombstone, upsert_device_cursor, upsert_device_cursor_with_version,
};

/// A tombstone record for a deleted entity.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Tombstone {
    /// Canonical entity type name.
    pub entity_type: String,
    /// Stable entity identity (UUIDv7 or natural key).
    pub entity_id: String,
    /// HLC version of the delete operation.
    pub version: String,
    /// RFC 3339 timestamp of the delete.
    pub deleted_at: String,
    /// Non-NULL for merge losers: the entity that absorbed this one.
    pub redirect_entity_id: Option<String>,
    /// Non-NULL for cross-type redirects (uncommon but safe).
    pub redirect_entity_type: Option<String>,
}
