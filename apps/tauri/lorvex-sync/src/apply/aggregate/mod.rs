//! Apply handlers for aggregate root entities.
//!
//! Each handler parses the JSON payload and performs an idempotent
//! INSERT ... ON CONFLICT DO UPDATE against the corresponding table.
//!
//! The task handler includes recurrence instance key dedup: if two tasks
//! share the same `recurrence_instance_key` (offline-spawned duplicates),
//! the one with the smaller ID wins and the loser is tombstoned with a
//! redirect. See spec Section 13.

use super::ApplyError;

/// shared outcome type for aggregate-root delete
/// handlers that gate via the in-handler LWW guard.
///
/// `apply_task_delete`, `apply_habit_delete`, and
/// `apply_calendar_event_delete` were each defined with
/// their own byte-isomorphic enum (`TaskDeleteOutcome`,
/// `HabitDeleteOutcome`, `CalendarEventDeleteOutcome`). The dispatch
/// site then matched three identical arms to translate them into a
/// single `EntityApplyOutcome::LwwRejected`. Collapsing the three
/// enums into this single shape lets the dispatcher treat all three
/// handlers as a fn-pointer table — see
/// the `lww_gated` row factor in `apply::dispatch`
/// (`EntityHandler::lww_gated`).
#[derive(Debug, Clone)]
pub(crate) enum LwwGatedDeleteOutcome {
    Applied,
    /// LWW guard refused the in-handler DELETE because the local
    /// row's version strictly dominates the envelope's. The dispatcher
    /// destructures `detail.local_version` to surface the conflict
    /// through `EntityApplyOutcome::LwwRejected { local_version }` so
    /// the envelope-level caller can render a typed `Hlc` for the
    /// conflict-log row without paying a second SELECT.
    LwwRejected(super::LwwRejectedDetail),
}

/// Shared outcome type for aggregate-root delete handlers that gate
/// via BOTH an aggregate-level invariant (e.g. "at least one list")
/// AND the in-handler LWW guard. `apply_list_delete` is the sole
/// handler on this shape today; it is kept generic (same pattern as
/// [`LwwGatedDeleteOutcome`] above) so the dispatcher treats an
/// invariant-gated handler as a fn-pointer returning this outcome.
#[derive(Debug, Clone)]
pub(crate) enum InvariantGatedDeleteOutcome {
    /// The SQL DELETE ran (or the row was already absent). The
    /// caller writes the tombstone.
    Applied,
    /// An aggregate-level invariant guard refused the in-handler
    /// DELETE while leaving the row alive. The caller in
    /// `apply_envelope` defers the envelope to `sync_pending_inbox`
    /// instead of minting a tombstone over a row the local device
    /// knows is still live.
    SkippedByInvariant { invariant: &'static str },
    /// the in-handler LWW gate refused the DELETE
    /// because the local row's version strictly dominates the
    /// envelope's. The dispatcher destructures `detail.local_version`
    /// and re-exposes it through `EntityApplyOutcome::LwwRejected`
    /// so the envelope-level caller renders the conflict-log row
    /// without a second SELECT.
    LwwRejected(super::LwwRejectedDetail),
}

mod calendar_event;
mod calendar_subscription;
mod habit;
mod helpers;
mod list;
mod memory;
mod preference;
mod recurrence;
mod task;

#[cfg(test)]
mod tests;

pub(crate) use calendar_event::{apply_calendar_event_delete, apply_calendar_event_upsert};
pub(crate) use calendar_subscription::{
    apply_calendar_subscription_delete, apply_calendar_subscription_upsert,
};
pub(crate) use habit::{apply_habit_delete, apply_habit_upsert};
pub(crate) use list::{apply_list_delete, apply_list_upsert};
pub(crate) use memory::{apply_memory_delete, apply_memory_upsert};
pub(crate) use preference::{apply_preference_delete, apply_preference_upsert};
pub(crate) use task::{apply_task_delete, apply_task_upsert};
