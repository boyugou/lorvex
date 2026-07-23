//! centralized post-commit Spotlight dispatch.
//!
//! This module owns the single mapping from "what just changed" to
//! "what Spotlight action to fire" — keeping the Spotlight (macOS) /
//! Jump-List (Windows) index in sync across every IPC mutation that
//! visibly changes a task or list. Without one canonical mapping, every
//! write site would have to remember to call
//! `crate::platform::spotlight::apply_actions(conn, &[...])` itself,
//! and a new write surface that forgot the wiring would silently drift
//! between "data changed" and "search index updated".
//!
//! Each public helper corresponds to one logical operation shape:
//!
//! * [`reindex_task_after_mutation`] — a single task was created or
//!   mutated (capture, update, lifecycle transition that left the task
//!   visible). The Spotlight item is rebuilt from the latest row.
//! * [`reindex_list_after_metadata_change`] — list metadata (name,
//!   color, icon, description) changed. Every task in the list must be
//!   reindexed so the description copy stays current.
//! * [`remove_task_after_archive_or_delete`] — a task became invisible
//!   (archived, hard-deleted, completed-and-purged). Drop its
//!   Spotlight item.
//!
//! IPC sites call the helper that names their intent rather than
//! constructing `SpotlightAction` directly. Future lifecycle
//! transitions get mapped through this module by extending the helper
//! set, so the "which Spotlight action fires for this transition"
//! decision lives in exactly one place.

use crate::platform::spotlight::{apply_actions, SpotlightAction};

/// Reindex a single task after a mutation that may have changed any
/// indexed field (title, body snippet, list name, due date, status).
///
/// Idempotent: calling this for an unchanged task is a no-op cost-wise
/// (Core Spotlight diffs internally) but cheap enough to fire on every
/// mutation rather than try to detect "indexed columns changed".
pub(crate) fn reindex_task_after_mutation(conn: &rusqlite::Connection, task_id: String) {
    apply_actions(conn, &[SpotlightAction::ReindexTaskIds(vec![task_id])]);
}

/// Reindex every task that belongs to a list whose metadata just
/// changed. The list name is rendered into each task's Spotlight
/// description, so a rename has to walk every task in the list and
/// rebuild its item.
pub(crate) fn reindex_list_after_metadata_change(conn: &rusqlite::Connection, list_id: String) {
    apply_actions(conn, &[SpotlightAction::ReindexList(list_id)]);
}
