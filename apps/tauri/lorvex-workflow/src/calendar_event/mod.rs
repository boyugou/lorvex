//! Canonical calendar event create + update operations.
//!
//! Owns the row-level write contract every surface (MCP, CLI, Tauri
//! app) shares for `calendar_events`: input normalization (via
//! [`crate::calendar_normalization`]), the SQL INSERT / UPDATE
//! through `lorvex_store::repositories::calendar_event_write`,
//! attendee sub-table materialization, and the EXDATE
//! skeleton-preserve policy that decides whether a recurrence patch
//! drops the stored exception list.
//!
//! Per-surface concerns — sync outbox enqueue, audit logging,
//! `local_change_seq` bump, IPC envelope shape, idempotency caches,
//! event-bus refresh — stay in each surface's adapter and run inside
//! the per-surface `Mutation` finalizer. The descriptor types here
//! ([`CreateCalendarEventMutation`], [`UpdateCalendarEventMutation`])
//! implement [`crate::mutation::Mutation`] so each surface plugs
//! them into its own executor.
//!
//! # Module layout
//!
//! - [`create`] — [`CreateCalendarEventMutation`] descriptor + apply.
//! - [`update`] — [`UpdateCalendarEventMutation`] descriptor + apply +
//!   EXDATE skeleton-preserve decision.
//! - [`attendees`] — [`materialize_attendees`], the canonical
//!   attendee sub-table replace-set every surface routes through.
//! - [`recurrence_skeleton`] — [`recurrence_skeleton_matches`] used
//!   by the update path's EXDATE preserve policy.
//! - [`load`] — [`load_calendar_event_json`], the row reader that
//!   enriches the event with its attendees sub-table for the
//!   post-mutation `after` snapshot.
//!
//! # Wire shape
//!
//! Every nullable field on the update input is `Patch<T>`
//! (three-state: `Unset` = leave as-is, `Clear` = nullify, `Set(v)` =
//! write). Surfaces translate their respective wire-level "absent /
//! present / null" shapes at the IPC / JSON boundary before
//! constructing [`CalendarEventUpdateInput`]; the operation itself
//! never sees a `clear_fields` array.
//!
//! Three input fields stay `Option<T>` because they have no third
//! "clear" state at the row level:
//!
//! - `title` — `NOT NULL` in the schema; the only choices are "keep
//!   the existing title" (`None`) or "set a new one" (`Some(value)`).
//! - `start_date` — the canonical anchor; required for every event,
//!   never nullable.
//! - `all_day` — a `bool` with no third value.
//!
//! Every other patchable field (including `event_type`, which is
//! nullable in the schema, and `attendees`, which is a sub-table that
//! can be cleared en masse) carries `Patch<T>`.

mod attendees;
mod create;
mod load;
mod recurrence_skeleton;
mod update;

#[cfg(test)]
mod tests;

pub use attendees::materialize_attendees;
pub use create::CreateCalendarEventMutation;
pub use load::load_calendar_event_json;
pub use recurrence_skeleton::recurrence_skeleton_matches;
pub use update::UpdateCalendarEventMutation;

// Re-export the DST guard so call sites can type
// `super::calendar_event::CalendarDstGuard` without depending on
// `calendar_normalization` directly.
pub use crate::calendar_normalization::CalendarDstGuard;

use lorvex_domain::{AttendeeStatus, CanonicalCalendarEventType, Patch};
use lorvex_store::StoreError;

/// Surface-agnostic attendee input — the canonical shape every
/// surface translates its wire-level attendee struct into before
/// feeding it to [`CreateCalendarEventMutation`] /
/// [`UpdateCalendarEventMutation`].
///
/// `status` is the typed RFC 5545 PARTSTAT subset; surfaces that
/// accept it as a string (MCP tool args, IPC JSON, sync apply) must
/// parse-strict into [`AttendeeStatus`] at their trust boundary so
/// the canonical hyphen form (`needs-action`) is the only spelling
/// that ever reaches the materializer.
#[derive(Debug, Clone)]
pub struct AttendeeShadowInput {
    pub email: String,
    pub name: Option<String>,
    pub status: Option<AttendeeStatus>,
}

/// Typed input for [`CreateCalendarEventMutation`]. Mirrors
/// [`crate::calendar_normalization::CalendarCreateInput`] plus the
/// optional attendee list.
#[derive(Debug, Clone)]
pub struct CalendarEventCreateInput {
    pub title: String,
    pub recurrence: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: Option<bool>,
    pub description: Option<String>,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    pub event_type: Option<CanonicalCalendarEventType>,
    pub person_name: Option<String>,
    pub attendees: Option<Vec<AttendeeShadowInput>>,
}

/// Typed input for [`UpdateCalendarEventMutation`]. Every nullable
/// field carries `Patch<T>` so surfaces can express the canonical
/// three-state "leave as-is / clear / set" contract without a side
/// channel like `clear_fields[]`.
///
/// `id`, `title`, and `all_day` stay `Option<T>` (or the raw type
/// for `id`) because they have no row-level "clear" state — see the
/// module-level docs for the per-field reasoning.
///
/// `start_date` uses `Patch<String>` for surface symmetry with its
/// siblings (`start_time`, `end_date`, `end_time`), but
/// [`UpdateCalendarEventMutation::new`] rejects `Patch::Clear` with a
/// `Validation` error because `start_date` is a required row column.
/// The accepted values are `Patch::Unset` (leave as-is) and
/// `Patch::Set(value)` (re-anchor).
///
/// `attendees: Patch<Vec<AttendeeShadowInput>>` carries the replace-
/// set semantics for the per-event attendee sub-table:
///
/// - `Patch::Unset` — leave the existing attendee rows alone.
/// - `Patch::Clear` — delete every attendee row for the event.
/// - `Patch::Set(list)` — replace the attendee rows with `list`
///   (empty `list` collapses to the same effect as `Clear`).
#[derive(Debug, Clone)]
pub struct CalendarEventUpdateInput {
    pub id: String,
    pub title: Option<String>,
    pub recurrence: Patch<String>,
    pub timezone: Patch<String>,
    pub start_date: Patch<String>,
    pub start_time: Patch<String>,
    pub end_date: Patch<String>,
    pub end_time: Patch<String>,
    pub all_day: Option<bool>,
    pub description: Patch<String>,
    pub location: Patch<String>,
    pub url: Patch<String>,
    pub color: Patch<String>,
    pub event_type: Patch<CanonicalCalendarEventType>,
    pub person_name: Patch<String>,
    pub attendees: Patch<Vec<AttendeeShadowInput>>,
}

/// Errors the calendar-event ops can raise. Maps onto each
/// surface's typed error at the adapter boundary; the workflow
/// crate stays unaware of `McpError` / `CliError` / `AppError`.
#[derive(Debug)]
pub enum CalendarEventOpError {
    Validation(String),
    Store(StoreError),
}

impl std::fmt::Display for CalendarEventOpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Validation(m) => write!(f, "{m}"),
            Self::Store(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for CalendarEventOpError {}

impl From<StoreError> for CalendarEventOpError {
    fn from(value: StoreError) -> Self {
        Self::Store(value)
    }
}

impl From<rusqlite::Error> for CalendarEventOpError {
    fn from(value: rusqlite::Error) -> Self {
        Self::Store(StoreError::from(value))
    }
}
