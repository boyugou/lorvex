//! Apply handlers for the `calendar_event` aggregate root.
//!
//! Per-concern siblings:
//!
//! * `upsert.rs` — `apply_calendar_event_upsert`: RFC-5545-shaped
//!   payload validator, SQL upsert, attendee materialization rebuild,
//!   email-collision dedupe.
//! * `delete.rs` — `apply_calendar_event_delete`: LWW-gated parent
//!   delete plus `task_calendar_event_links` cascade.
//! * `attendee.rs` — `NormalizedAttendee` + `normalize_attendee`: the
//!   per-attendee validator and canonical-JSON tiebreaker used by
//!   upsert's email-collision resolution (issue #2878).

mod attendee;
mod delete;
mod merge;
mod upsert;

pub(crate) use delete::apply_calendar_event_delete;
pub(crate) use upsert::apply_calendar_event_upsert;

#[cfg(test)]
mod tests;
