//! Habit definition CRUD: create, update, and cascading delete.
//!
//! Delete cascades to completions + reminder policies and emits a
//! separate sync delete + changelog row for each cascaded child so
//! peers reconstruct the same end state.
//!
//! The three top-level entry points live in sibling submodules; this
//! `mod.rs` collects only the re-exports they expose to the rest of the
//! `habits::effects` surface.

mod create;
mod delete;
mod update;

pub(crate) use create::create_habit_with_conn;
pub(crate) use delete::delete_habit_with_conn;
pub(crate) use update::update_habit_with_conn;
