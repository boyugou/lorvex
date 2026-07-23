//! Snapshot-based undo for calendar-event and list deletion (#3392, #3420).
//!
//! Generalizes the task lifecycle undo-token pattern (#2536) to non-task
//! entities. The token is a self-contained JSON blob containing the
//! pre-delete row (and, for calendar events, every linked task id) plus
//! an `expires_at` TTL roughly aligned with the frontend toast hold
//! window (~5s).
//!
//! No persistent backend storage is involved — the token is opaque to
//! the frontend and round-trips through it. On undo we mint a fresh HLC
//! version (strictly newer than the delete tombstone, by virtue of HLC
//! monotonicity) and re-create the row + every link, emitting fresh
//! upsert envelopes so peers converge correctly under LWW.

pub mod command;
mod restore_event;
mod restore_list;
mod snapshot;
mod token;

#[cfg(test)]
mod tests;

pub(super) use snapshot::capture_calendar_event_snapshot;
pub(crate) use snapshot::capture_list_snapshot;
pub(crate) use token::build_undo_token;

// Test-only re-exports. The sibling `tests.rs` exercises the internal
// undo path directly (without the Tauri command boundary) so it can
// drive `undo_delete_entity_internal` against an in-memory connection
// and inspect the `RestoredEntity` discriminant. Gating the re-exports
// with `#[cfg(test)]` keeps the production import surface minimal while
// preserving the test's ability to reach into the private command
// module via `use super::{undo_delete_entity_internal, RestoredEntity}`.
#[cfg(test)]
pub(crate) use command::{undo_delete_entity_internal, RestoredEntity};
