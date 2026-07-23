//! Full-resync (reseed) workflow.
//!
//! When `reseed_required` is set in sync_checkpoints, the device must
//! perform a complete canonical data replacement rather than incremental
//! sync. This module implements the data-clearing side of that workflow.
//!
//! The transport adapter is responsible for pulling the full snapshot;
//! this module handles clearing canonical tables and resetting state.

use rusqlite::{Connection, OptionalExtension};

/// Tables that hold canonical synced truth — cleared during reseed.
/// Order: children first (FK cascade handles most), then edges, then roots.
const CANONICAL_TABLES_TO_CLEAR: &[&str] = &[
    // Independent children
    "task_reminders",
    "task_checklist_items",
    "habit_reminder_policies",
    // Edges
    "task_tags",
    "task_dependencies",
    "task_calendar_event_links",
    "habit_completions",
    // Parent-owned materializations
    "current_focus_items",
    "focus_schedule_blocks",
    "calendar_event_attendees",
    "daily_review_task_links",
    "daily_review_list_links",
    // Aggregate roots (order matters for FK)
    "tasks",
    // `lists` is cleared via a custom statement below
    // (`DELETE FROM lists WHERE id != 'inbox'`) so the inbox sentinel
    // — seeded once by migration 001 and protected by the
    // `trg_lists_before_delete` trigger — survives the wipe. A bare
    // `DELETE FROM lists` would trip that trigger; deleting only
    // non-inbox rows side-steps the RAISE and the trigger's
    // re-home-to-inbox UPDATE is a no-op because `tasks` has
    // already been cleared above.
    "habits",
    "tags",
    "calendar_events",
    "calendar_subscriptions",
    "daily_reviews",
    "current_focus",
    "focus_schedule",
    // Audit
    "ai_changelog",
    // Sync infrastructure
    "sync_tombstones",
    "sync_pending_inbox",
    "sync_conflict_log",
    "sync_device_cursors",
    "sync_payload_shadow",
    // Projections / references
];

/// Result of the reseed clear operation.
pub struct ReseedClearResult {
    /// Number of tables cleared.
    pub tables_cleared: usize,
}

/// Clear all canonical synced tables in preparation for a full reseed.
///
/// This is step 3 of the reseed workflow (doc 03):
/// "Within a transaction: clear all local canonical tables."
///
/// Local-only state (device_state, task_reminder_delivery_state,
/// provider_calendar_events, task_provider_event_links) is preserved.
///
/// The caller must wrap this in a transaction and follow with applying
/// the full snapshot from the remote.
pub fn clear_canonical_tables_for_reseed(
    conn: &Connection,
) -> Result<ReseedClearResult, rusqlite::Error> {
    // the docstring above tells callers to wrap
    // this in a transaction, but nothing enforces it. A bug that
    // skips the wrapping would issue 30+ DELETEs in autocommit
    // mode, leaving the DB partially cleared on any mid-loop
    // failure. Trip a `debug_assert` in tests / debug builds so
    // misuse surfaces during development; release builds still
    // execute (since stripping the contract retroactively would
    // be worse than the half-clear risk).
    debug_assert!(
        !conn.is_autocommit(),
        "clear_canonical_tables_for_reseed must be called inside a transaction; \
         the caller is responsible for the BEGIN/COMMIT."
    );

    let mut cleared = 0;

    for table in CANONICAL_TABLES_TO_CLEAR {
        // Defense-in-depth: `CANONICAL_TABLES_TO_CLEAR` is a closed
        // `&'static str` set authored in this crate, but interpolating
        // into a `DELETE FROM …` still warrants an explicit guard so a
        // future edit to the list with a typo (quote, semicolon,
        // comment delimiter) panics here instead of executing
        // malformed SQL against a production DB.
        debug_assert!(
            {
                lorvex_domain::assert_safe_sql_identifier(table);
                true
            },
            "reseed table name must be a safe SQL identifier"
        );
        conn.execute(&format!("DELETE FROM {table}"), [])?;
        cleared += 1;
    }

    // Clear every list except the well-known `inbox` sentinel.
    // The trigger `trg_lists_before_delete` reroutes orphaned tasks
    // to inbox; with `tasks` already cleared above the UPDATE in the
    // trigger body is a zero-row no-op. The sentinel itself is
    // preserved because (a) it's seeded once by migration 001 and
    // not re-seeded after reseed, and (b) every task created after
    // the snapshot apply needs a valid `list_id` default to land on.
    conn.execute("DELETE FROM lists WHERE id != 'inbox'", [])?;

    // Clear preferences, memories, and memory_revisions (all synced entities)
    conn.execute("DELETE FROM preferences", [])?;
    conn.execute("DELETE FROM memory_revisions", [])?;
    conn.execute("DELETE FROM memories", [])?;

    Ok(ReseedClearResult {
        // +3 for the three `DELETE FROM` calls below the loop
        // (preferences, memory_revisions, memories).
        // +1 for the `lists` clear (excluded from the loop because
        // the inbox sentinel must survive the wipe).
        tables_cleared: cleared + 3 + 1,
    })
}

/// Remove the reseed_required flag and reset sync cursors.
///
/// This is steps 5-6 of the reseed workflow (doc 03).
pub fn complete_reseed(conn: &Connection) -> Result<(), rusqlite::Error> {
    // Reset all transport cursors and flags (but preserve device_id).
    // This also removes the reseed_required flag.
    conn.execute("DELETE FROM sync_checkpoints WHERE key != 'device_id'", [])?;

    // Clear outbox (unsynced local changes are lost during reseed)
    conn.execute("DELETE FROM sync_outbox", [])?;

    Ok(())
}

/// Check if reseed is required for any transport.
pub fn is_reseed_required(conn: &Connection) -> Result<bool, rusqlite::Error> {
    conn.query_row(
        "SELECT 1 FROM sync_checkpoints WHERE key = 'reseed_required' AND value = 'true'",
        [],
        |_| Ok(true),
    )
    .optional()
    .map(|value| value.is_some())
}

#[cfg(test)]
mod tests;
