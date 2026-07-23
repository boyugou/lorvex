//! Habit-domain Tauri commands: habit CRUD + completion tracking
//! (`queries`) and the per-habit reminder policy CRUD (`reminders`).
//!
//! Source: refactor for #3277 — flat `commands/habit_reminders.rs`
//! plus `habit_queries/` and `habit_reminders/` dirs were folded
//! under this single `habits/` namespace.

pub(crate) mod queries;
pub(crate) mod reminders;
