//! Trash + permanent-delete cascade for tasks.
//!
//! Split into per-concern siblings:
//!
//! - [`archive`] — move a live task to the Trash (`archived_at = now`).
//! - [`restore`] — pull a task back out of the Trash (`archived_at = NULL`).
//! - [`permanent_delete`] — final-delete a trashed task plus its child cascade.
//! - [`focus_dates`] — shared helper for collecting + re-emitting the
//!   `current_focus` / `focus_schedule` parent aggregates that referenced the
//!   trashed/deleted task before its cascade detached the child rows.

mod archive;
mod focus_dates;
mod permanent_delete;
mod restore;

pub(crate) use archive::archive_task_in_tx;
#[cfg(test)]
pub(crate) use archive::archive_task_with_conn;
#[cfg(test)]
pub(crate) use permanent_delete::permanent_delete_task_with_conn;
pub(crate) use permanent_delete::{permanent_delete_task_in_tx, PermanentDeleteTaskResult};
pub(crate) use restore::restore_task_from_trash_in_tx;
#[cfg(test)]
pub(crate) use restore::restore_task_from_trash_with_conn;
