//! Shared post-commit finalization for snapshot imports.
//!
//! `lorvex-store` owns ZIP decoding and table upserts, but successful
//! non-dry-run imports also need cross-surface runtime bookkeeping:
//! bump the local invalidation counter, invalidate the full-sync seed
//! checkpoint, and either let the caller run an immediate seed or mark
//! a durable reseed requirement. Keeping that logic here prevents the
//! app, CLI, and MCP surfaces from drifting.

use rusqlite::Connection;

use crate::{error::SyncError, startup_maintenance};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotImportFinalizationReport {
    pub local_change_seq: u64,
    pub full_sync_seeded_cleared: bool,
    pub reseed_required_marked: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotImportReseedRequiredReport {
    pub full_sync_seeded_cleared: bool,
}

const SNAPSHOT_IMPORT_MARKER_ENTITY_TYPE: &str = "snapshot_import";

fn bump_local_change_seq(conn: &Connection) -> Result<u64, SyncError> {
    lorvex_runtime::bump_local_change_seq(conn)
        .map_err(lorvex_store::StoreError::from)
        .map_err(SyncError::from)
}

fn clear_full_sync_seeded(conn: &Connection) -> Result<bool, SyncError> {
    lorvex_runtime::sync_checkpoint_clear(conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
        .map_err(lorvex_store::StoreError::from)
        .map_err(SyncError::from)
}

/// Prepare a committed snapshot import for an immediate full-sync seed.
///
/// This bumps `local_change_seq` exactly once and clears
/// `full_sync_seeded`. The caller should then run its own seeding
/// implementation; if that seed is cancelled or fails, call
/// [`mark_snapshot_import_reseed_required`] so the next sync cycle can
/// retry durably.
pub fn prepare_snapshot_import_reseed(
    conn: &Connection,
) -> Result<SnapshotImportFinalizationReport, SyncError> {
    lorvex_store::with_immediate_transaction(conn, |conn| {
        let local_change_seq = bump_local_change_seq(conn)?;
        let full_sync_seeded_cleared = clear_full_sync_seeded(conn)?;
        Ok(SnapshotImportFinalizationReport {
            local_change_seq,
            full_sync_seeded_cleared,
            reseed_required_marked: false,
        })
    })
}

/// Finalize a committed snapshot import when the caller cannot run the
/// full seed itself.
///
/// CLI and MCP imports do not own a transport-specific seeder, so they
/// leave a durable `reseed_required` marker after clearing the existing
/// seed checkpoint. This prevents incremental sync from assuming the
/// restored rows have already been propagated.
pub fn finalize_snapshot_import_with_deferred_reseed(
    conn: &Connection,
    marker_entity_id: impl Into<String>,
) -> Result<SnapshotImportFinalizationReport, SyncError> {
    let marker_entity_id = marker_entity_id.into();
    lorvex_store::with_immediate_transaction(conn, |conn| {
        let local_change_seq = bump_local_change_seq(conn)?;
        let full_sync_seeded_cleared = clear_full_sync_seeded(conn)?;
        startup_maintenance::flag_reseed_required_in_transaction(
            conn,
            SNAPSHOT_IMPORT_MARKER_ENTITY_TYPE,
            marker_entity_id,
        )?;
        Ok(SnapshotImportFinalizationReport {
            local_change_seq,
            full_sync_seeded_cleared,
            reseed_required_marked: true,
        })
    })
}

/// Mark that a committed snapshot import still needs a full-sync seed.
///
/// This does not bump `local_change_seq`; callers use it after
/// [`prepare_snapshot_import_reseed`] already performed the successful
/// import finalization bump.
pub fn mark_snapshot_import_reseed_required(
    conn: &Connection,
    marker_entity_id: impl Into<String>,
) -> Result<SnapshotImportReseedRequiredReport, SyncError> {
    let marker_entity_id = marker_entity_id.into();
    lorvex_store::with_immediate_transaction(conn, |conn| {
        let full_sync_seeded_cleared = clear_full_sync_seeded(conn)?;
        startup_maintenance::flag_reseed_required_in_transaction(
            conn,
            SNAPSHOT_IMPORT_MARKER_ENTITY_TYPE,
            marker_entity_id,
        )?;
        Ok(SnapshotImportReseedRequiredReport {
            full_sync_seeded_cleared,
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_seq(conn: &Connection) -> u64 {
        lorvex_runtime::read_local_change_seq(conn).expect("read local_change_seq")
    }

    fn read_checkpoint(conn: &Connection, key: &str) -> Option<String> {
        lorvex_runtime::sync_checkpoint_get(conn, key).expect("read sync checkpoint")
    }

    #[test]
    fn prepare_snapshot_import_reseed_bumps_seq_once_and_clears_seed_checkpoint() {
        let conn = lorvex_store::test_support::test_conn();
        lorvex_runtime::sync_checkpoint_set(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
            .expect("seed full_sync checkpoint");

        let report = prepare_snapshot_import_reseed(&conn).expect("prepare reseed");

        assert_eq!(report.local_change_seq, 1);
        assert_eq!(read_seq(&conn), 1);
        assert!(report.full_sync_seeded_cleared);
        assert!(!report.reseed_required_marked);
        assert_eq!(
            read_checkpoint(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED),
            None
        );
        assert_eq!(
            read_checkpoint(&conn, lorvex_runtime::KEY_RESEED_REQUIRED),
            None
        );
    }

    #[test]
    fn deferred_reseed_finalization_bumps_seq_and_marks_reseed_required() {
        let conn = lorvex_store::test_support::test_conn();
        lorvex_runtime::sync_checkpoint_set(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
            .expect("seed full_sync checkpoint");

        let report = finalize_snapshot_import_with_deferred_reseed(&conn, "cli_import")
            .expect("finalize import");

        assert_eq!(report.local_change_seq, 1);
        assert_eq!(read_seq(&conn), 1);
        assert!(report.full_sync_seeded_cleared);
        assert!(report.reseed_required_marked);
        assert_eq!(
            read_checkpoint(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED),
            None
        );
        assert_eq!(
            read_checkpoint(&conn, lorvex_runtime::KEY_RESEED_REQUIRED).as_deref(),
            Some("true")
        );
    }

    #[test]
    fn mark_snapshot_import_reseed_required_does_not_bump_seq_after_prepare() {
        let conn = lorvex_store::test_support::test_conn();
        prepare_snapshot_import_reseed(&conn).expect("prepare reseed");

        let report = mark_snapshot_import_reseed_required(&conn, "post_import_seed_failed")
            .expect("mark reseed required");

        assert!(!report.full_sync_seeded_cleared);
        assert_eq!(read_seq(&conn), 1);
        assert_eq!(
            read_checkpoint(&conn, lorvex_runtime::KEY_RESEED_REQUIRED).as_deref(),
            Some("true")
        );
    }
}
