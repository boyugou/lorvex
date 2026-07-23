//! Habit reminder policy MCP entry points — three narrow verbs, split
//! per file:
//!
//! - `load`   — read-only list of every habit reminder policy
//! - `upsert` — create-or-update a single policy slot (HH:MM + enabled
//!   flag, scoped by habit id). Validates the HH:MM shape +
//!   habit existence at the trust boundary.
//! - `delete` — tombstone-emitting deletion of a single slot.

mod delete;
mod load;
mod upsert;
mod validate;

#[cfg(test)]
mod tests;

pub(crate) use delete::delete_habit_reminder_policy;
pub(crate) use load::get_habit_reminder_policies;
pub(crate) use upsert::upsert_habit_reminder_policy;
