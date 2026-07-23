//! user-facing Trash / undelete.
//!
//! The Trash flow makes deletion a two-step process so
//! `permanent_delete_task` is never instantly destructive — every
//! delete passes through an undoable soft-delete first:
//!
//!   * `archive_task` — soft-delete. Sets `archived_at`, bumps the HLC
//!     version, emits a sync upsert envelope, and logs to `ai_changelog`.
//!     The row stays in the DB but every user-facing read path filters
//!     `archived_at IS NULL` inline so the task disappears from lists,
//!     stats, search, and MCP queries.
//!   * `restore_task_from_trash` — inverse of archive. Clears
//!     `archived_at`, bumps version, re-emits an upsert, logs.
//!   * `permanent_delete_task` — still the hard-delete, but now rejects
//!     unless the row is already archived. The Trash view is the only
//!     place this is invoked from.
//!   * `empty_trash` — hard-deletes all archived rows whose
//!     `archived_at` is older than the retention cutoff (30 days).
//!     Invoked explicitly from the Trash view's "Empty trash" button and
//!     automatically on every app launch.
//!
//! Sync: archive is a normal task upsert carrying the new
//! `archived_at` field. Peers running `apply_task_upsert` absorb the
//! change and the row disappears from their UI the same way it did
//! locally. A hard-delete (expiry or manual) still emits a classic
//! task-delete envelope, so peers also tombstone the row.

pub(crate) mod archive_commands;
pub(crate) mod empty_trash;
pub(crate) mod query;
mod startup_purge;
#[cfg(test)]
mod tests;

/// Retention window for entries in the Trash. Entries older than this are
/// hard-deleted by `empty_trash` (both the manual invocation and the
/// boot-time auto-purge).
pub const TRASH_RETENTION_DAYS: i64 = lorvex_sync::startup_trash_purge::TRASH_RETENTION_DAYS;

pub use archive_commands::{archive_task, restore_task_from_trash};
pub use empty_trash::{empty_trash, EmptyTrashResult};
pub use query::{get_archived_tasks, ArchivedTasksResult};
pub use startup_purge::run_startup_trash_purge;

#[cfg(test)]
use archive_commands::{archive_task_with_conn, restore_task_from_trash_with_conn};
#[cfg(test)]
use empty_trash::empty_trash_with_conn;
#[cfg(test)]
use startup_purge::{log_startup_trash_purge_failure, log_startup_trash_purge_report};
