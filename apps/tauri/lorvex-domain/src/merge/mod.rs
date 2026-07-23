//! Pure merge policy for LWW resolution, tag merge, and recurrence dedup.
//!
//! All functions in this module are pure — no IO, no database access. They
//! operate on domain types (`Hlc`, entity IDs) and return deterministic
//! outcomes.
//!
//! See spec Section 5: Root Sync Model & Merge Rules.

use crate::hlc::Hlc;

/// Result of comparing two HLC versions for LWW merge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MergeOutcome {
    /// Local version wins (is newer or equal).
    LocalWins,
    /// Remote version wins (is newer).
    RemoteWins,
}

/// Compare two HLC versions. Returns which one wins in LWW.
///
/// If the remote version is strictly greater than the local version, the
/// remote wins. Otherwise (local is newer or equal), local wins — this
/// ensures ties resolve to the local copy (idempotent no-op).
///
/// # Examples
///
/// ```
/// use lorvex_domain::hlc::Hlc;
/// use lorvex_domain::merge::{resolve_lww, MergeOutcome};
///
/// let older = Hlc::new(1_711_060_000_000, 0, "abcdef0123456789").unwrap();
/// let newer = Hlc::new(1_711_060_000_001, 0, "abcdef0123456789").unwrap();
///
/// // Strictly-newer remote wins.
/// assert_eq!(resolve_lww(&older, &newer), MergeOutcome::RemoteWins);
/// // Strictly-older remote loses.
/// assert_eq!(resolve_lww(&newer, &older), MergeOutcome::LocalWins);
/// // Tie resolves to local (idempotent re-apply must be a no-op).
/// assert_eq!(resolve_lww(&newer, &newer.clone()), MergeOutcome::LocalWins);
/// ```
pub fn resolve_lww(local_version: &Hlc, remote_version: &Hlc) -> MergeOutcome {
    if remote_version > local_version {
        MergeOutcome::RemoteWins
    } else {
        MergeOutcome::LocalWins
    }
}

/// For tag merge: determine winner by min(tag_id).
///
/// UUIDv7 ordering = chronological = first-created wins. The winner is the
/// tag with the lexicographically smaller ID; the loser gets tombstoned
/// with a redirect to the winner.
///
/// Returns `(winner_id, loser_id)`.
///
/// # Examples
///
/// ```
/// use lorvex_domain::merge::tag_merge_winner;
/// // UUIDv7 sorts chronologically — earlier creation wins.
/// let (winner, loser) = tag_merge_winner("01900000-aaaa", "01900000-bbbb");
/// assert_eq!(winner, "01900000-aaaa");
/// assert_eq!(loser, "01900000-bbbb");
///
/// // Argument order does not matter — the function returns the same
/// // (winner, loser) pair regardless of which side it received first.
/// let (winner, loser) = tag_merge_winner("01900000-bbbb", "01900000-aaaa");
/// assert_eq!(winner, "01900000-aaaa");
/// assert_eq!(loser, "01900000-bbbb");
/// ```
pub fn tag_merge_winner<'a>(id_a: &'a str, id_b: &'a str) -> (&'a str, &'a str) {
    if id_a <= id_b {
        (id_a, id_b)
    } else {
        (id_b, id_a)
    }
}

/// For recurrence dedup: same as tag merge — min(task_id) wins.
///
/// When two tasks share the same `recurrence_instance_key`, the one with
/// the smaller UUIDv7 ID wins. The loser gets tombstoned with a redirect.
///
/// Returns `(winner_id, loser_id)`.
pub fn recurrence_dedup_winner<'a>(id_a: &'a str, id_b: &'a str) -> (&'a str, &'a str) {
    tag_merge_winner(id_a, id_b)
}

#[cfg(test)]
mod tests;
