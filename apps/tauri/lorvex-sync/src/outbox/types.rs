use serde::{Deserialize, Serialize};

use crate::envelope::SyncEnvelope;

/// A row from the `sync_outbox` table: wraps a `SyncEnvelope` with outbox
/// metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEntry {
    /// Outbox row ID (autoincrement).
    pub id: i64,
    /// The sync envelope for this entry.
    pub envelope: SyncEnvelope,
    /// RFC 3339 timestamp when this entry was created.
    pub created_at: String,
    /// RFC 3339 timestamp when this entry was successfully pushed to remote.
    pub synced_at: Option<String>,
    /// Number of push retries attempted.
    pub retry_count: i64,
    /// RFC 3339 timestamp of the last retry attempt.
    pub last_retry_at: Option<String>,
}
/// Outcome of a `record_retry` call.
///
/// Callers need to know when a row JUST crossed `MAX_RETRIES` so
/// they can surface the event to the user via
/// `persist_sync_issue`. Without this signal, rows would silently
/// die after 10 retries and be GC'd 30 days later without ever
/// appearing in the user's diagnostic surface — the `last_error`
/// checkpoint would show whatever the newest failure was, not the
/// one that exhausted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordRetryOutcome {
    /// The new retry_count after increment.
    pub new_retry_count: i64,
    /// True iff this call is the one that brought retry_count up to
    /// `MAX_RETRIES` (crossed the threshold for the first time).
    /// Callers should treat this as the "just exhausted" signal and
    /// emit a persistent sync issue.
    pub exhausted_now: bool,
}
