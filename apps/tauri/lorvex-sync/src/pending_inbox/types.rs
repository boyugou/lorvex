//! Pending-inbox row and drain result shapes.

use lorvex_domain::naming::EntityKind;
use rusqlite::Row;
use serde::{Deserialize, Serialize};

use crate::envelope::SyncEnvelope;
use crate::error::SyncError;

/// A row from the `sync_pending_inbox` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingInboxEntry {
    /// Row ID (autoincrement).
    pub id: i64,
    /// The full serialized SyncEnvelope (JSON).
    pub envelope_json: String,
    /// Reason the envelope was stalled (e.g., "fk_unresolved").
    pub reason: String,
    /// Which FK target entity type is missing.
    pub missing_entity_type: Option<String>,
    /// Which FK target entity ID is missing.
    pub missing_entity_id: Option<String>,
    /// RFC 3339 timestamp of the first attempt.
    pub first_attempted_at: String,
    /// RFC 3339 timestamp of the most recent attempt.
    pub last_attempted_at: String,
    /// Number of apply attempts.
    pub attempt_count: i64,
}

impl PendingInboxEntry {
    pub(super) fn from_row(row: &Row<'_>) -> Result<Self, rusqlite::Error> {
        Ok(Self {
            id: row.get(0)?,
            envelope_json: row.get(1)?,
            reason: row.get(2)?,
            missing_entity_type: row.get(3)?,
            missing_entity_id: row.get(4)?,
            first_attempted_at: row.get(5)?,
            last_attempted_at: row.get(6)?,
            attempt_count: row.get(7)?,
        })
    }

    /// Deserialize the stored envelope JSON back into a `SyncEnvelope`.
    ///
    /// Routes the parse failure through `From<serde_json::Error>`
    /// (lands in `SyncError::SerializationCategorized`), preserving
    /// the typed `SerdeJsonCategory` discriminant so callers can
    /// distinguish syntactic corruption from EOF truncation.
    pub fn parse_envelope(&self) -> Result<SyncEnvelope, SyncError> {
        Ok(serde_json::from_str(&self.envelope_json)?)
    }
}

/// Summary of one drain pass over the pending inbox.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct PendingDrainSummary {
    pub replayed: u64,
    pub discarded: u64,
    pub remapped: u64,
    pub stalled_logged: u64,
    /// Entries that failed with a non-deferral error and were left in the inbox
    /// for a future drain attempt. These entries do not abort the drain.
    pub errors: u64,
    /// Entries the apply pipeline returned `ApplyResult::Skipped` for.
    pub skipped: u64,
    /// Distinct entity kinds of envelopes that were successfully applied during
    /// this drain pass.
    ///
    /// Carried as the typed [`EntityKind`] enum so downstream fan-out
    /// (`emit_data_changed_for_entity_types`) gets compile-time
    /// exhaustiveness on the kind switch instead of round-tripping the
    /// canonical string through a runtime parse seam.
    pub replayed_entity_types: Vec<EntityKind>,
}
