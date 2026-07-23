//! Task-domain Tauri commands: CRUD, batch operations, queries, and the
//! ancillary edges (checklists, reminders, dependencies, calendar /
//! provider event links, attribution, recurrence). The `pub use` /
//! `pub(crate) use` lines below re-export the public IPC entry points
//! by name; the `pub(crate)` and `pub(in crate::commands::tasks)`
//! items here stay scoped so they don't leak past the task domain.
//!
//! Source: refactor for #3277 — task_*.rs flat files at the
//! `commands/` root were folded under this single `tasks/` namespace.
//! Each submodule below corresponds to one of the original sibling
//! files (or sibling-pair when both `task_X.rs` + `task_X/` existed).
//! #3371 phase 1: dropped the redundant `tasks/commands/` middle
//! layer — direct submodules now live one level shallower.

#![allow(unused_imports)] // task facade re-exports Tauri command entry points

pub(super) use crate::{db::get_conn, error::AppError, event_bus, invariants};
use rusqlite::Connection;

pub(super) use crate::commands::{
    cleanup_task_dependency_refs_after_removal, enqueue_affected_dependents,
    enqueue_current_focus_upsert_for_date, enqueue_dependency_edge_upsert,
    enqueue_focus_schedule_upsert_for_date, enqueue_lifecycle_sync_plan,
    enqueue_task_reminder_upsert, enqueue_task_upsert, fetch_ordered_tasks_by_ids,
    fetch_task_by_id, fetch_tasks_by_ids, link_tag_to_task, normalize_date_input_for_conn,
    sync_timestamp_now, task_from_row, with_immediate_transaction, OptionalExt, Task, TASK_COLS,
};

pub(crate) mod attribution;
pub(crate) mod calendar_event_links;
pub(crate) mod checklists;
pub(crate) mod dependencies;
pub(crate) mod provider_event_links;
pub(crate) mod queries;
pub(crate) mod recurrence;
pub(crate) mod reminders;

pub(crate) mod batch;
pub(crate) mod capture;
pub(crate) mod completion;
mod exceptions;
pub(crate) mod lifecycle;
mod privacy;
pub(crate) mod undo;
pub(crate) mod updates;

pub use capture::{duplicate_task, quick_capture};
#[cfg(test)]
pub(crate) use capture::{quick_capture_with_conn, QuickCaptureRequest};
pub use completion::complete_task;
pub(crate) use completion::complete_task_internal;
#[cfg(test)]
pub(crate) use completion::complete_task_with_conn_inner;
pub(crate) use lifecycle::run_startup_trash_purge;
pub use lifecycle::{
    cancel_task, defer_task, defer_task_until, permanent_delete_task, purge_cancelled_tasks,
    reopen_task, reset_task_deferral, restore_task_deferral,
};
// `undo_task_lifecycle_with_conn_for_tests` is consumed only via the
// direct super-path (`super::super::undo::...`) from
// `updates/tests.rs`, so the `crate::commands::tasks::*` re-export is
// unnecessary. `apply_single_undo_for_tests` + `UndoToken` are
// reached through the crate path from `tests/task_commands.rs`,
// `tests/task_runtime/lifecycle_flow.rs`, and
// `lifecycle/removal/tests.rs`, so they stay.
pub use undo::undo_task_lifecycle;
#[cfg(test)]
pub(crate) use undo::{apply_single_undo_for_tests, UndoToken};
// Exposed to the `undo` sibling so `apply_update_undo` can replay
// the canonical update path when restoring a pre-mutation snapshot.
#[rustfmt::skip]
pub use updates::{update_task};
#[cfg(test)]
pub(crate) use updates::update_task_inner_with_conn;
pub(crate) use updates::update_task_internal;

/// Post-mutation epilogue core: enqueue the task row for sync and
/// return the post-stamp snapshot.
///
/// Spotlight indexing is deliberately **not** performed here — callers
/// must collect task IDs and dispatch `SpotlightAction::ReindexTaskIds`
/// after the enclosing transaction commits. This keeps Spotlight I/O
/// out of write transactions to avoid potential deadlocks and long
/// lock durations.
///
/// Event emission is controlled by the caller so batch flows can emit
/// once after all mutations complete instead of spamming per-row task
/// events inside a single transaction.
///
/// The Tauri surface intentionally does not write to `ai_changelog`
/// (AI/MCP-only), so this function takes no `action` /
/// `describe(&Task) -> String` audit parameters — those would have
/// no consumer.
pub(super) fn finalize_task_mutation_without_emitting(
    conn: &Connection,
    id: &str,
) -> Result<Task, AppError> {
    let task_for_summary = fetch_task_by_id(conn, id)?;
    enqueue_task_upsert(conn, &task_for_summary)?;

    // Re-fetch AFTER enqueue to get the post-stamp version
    // (write_to_outbox stamps the entity's version column via HLC).
    fetch_task_by_id(conn, id)
}

/// Post-mutation epilogue wrapper for single-task mutation paths.
///
/// This intentionally does **not** emit task data-changed inside the write
/// transaction. Callers must emit after commit so failed transactions never
/// publish stale UI invalidations.
pub(crate) fn finalize_task_mutation(conn: &Connection, id: &str) -> Result<Task, AppError> {
    finalize_task_mutation_without_emitting(conn, id)
}
