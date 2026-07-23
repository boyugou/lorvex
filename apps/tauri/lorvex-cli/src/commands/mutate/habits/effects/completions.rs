//! Habit completion + uncompletion writes.
//!
//! `complete_habit_with_conn` opens its own immediate-mode transaction;
//! `complete_habit_in_tx` exposes the same body for batched callers
//! (#3033-H2) so per-id completions ride a single outer BEGIN
//! IMMEDIATE transaction. The pre-flight gate's "all-or-nothing"
//! promise depends on this — a mid-loop failure must roll back the
//! prior ids in the same batch rather than leaving them permanently
//! completed.

use lorvex_domain::naming::{EDGE_HABIT_COMPLETION, OP_DELETE};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use rusqlite::Connection;

use super::{
    habit_completion_payload, load_habit_completion_row, load_habit_row,
    validate_optional_completion_note, HabitCompletionRow, HabitUncompleteResult,
};
use crate::commands::shared::log_cli_changelog_with_state;
use crate::hlc_guard::lock_shared;

pub(crate) fn complete_habit_with_conn(
    conn: &mut Connection,
    habit_id: &lorvex_domain::HabitId,
    date: Option<&str>,
    note: Option<&str>,
) -> Result<(String, HabitCompletionRow), crate::error::CliError> {
    let note = validate_optional_completion_note(note)?;
    if let Some(date) = date {
        lorvex_domain::validation::validate_date_format(date)?;
    }

    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let result = complete_habit_in_tx(&tx, habit_id, date, note.as_deref())?;
    bump_local_change_seq(&tx)?;
    tx.commit()?;
    Ok(result)
}

/// Execute the body of `complete_habit_with_conn` inside an already-open
/// transaction. Used by `run_habit_batch_complete` (#3033-H2) so the
/// per-id completions ride a single outer BEGIN IMMEDIATE rather than
/// committing per iteration; the batch contract requires that a
/// mid-loop failure rolls back every completion in the same batch,
/// matching the pre-flight gate's "all-or-nothing" promise.
///
/// The caller owns the transaction lifecycle (commit/rollback) and the
/// `bump_local_change_seq` bookkeeping; this body covers everything
/// from device-id resolution through the changelog write.
pub(crate) fn complete_habit_in_tx(
    tx: &Connection,
    habit_id: &lorvex_domain::HabitId,
    date: Option<&str>,
    note: Option<&str>,
) -> Result<(String, HabitCompletionRow), crate::error::CliError> {
    let habit_id_str = habit_id.as_str();
    let device_id = get_or_create_device_id(tx)?;

    let habit = load_habit_row(tx, habit_id)?;

    let tz = lorvex_workflow::timezone::active_timezone_name(tx)?;
    let completed_date = date.map_or_else(
        || lorvex_domain::today_ymd_for_timezone_name(chrono::Utc::now(), tz.as_deref()),
        str::to_string,
    );
    // capture the existing completion row (if any) before the upsert
    // so the audit row can show value bumps. Routes through the spb
    // loader so the audit's `before_json` matches the sync envelope's
    // wire shape byte-for-byte.
    let before_json = lorvex_store::payload_loaders::load_habit_completion_sync_payload(
        tx,
        habit_id,
        &completed_date,
    )?;
    let now = lorvex_domain::sync_timestamp_now();

    // Look up target_count to clamp the completion value (parity with Tauri app).
    let target_count: i64 = tx.query_row(
        "SELECT MAX(target_count, 1) FROM habits WHERE id = ?1",
        rusqlite::params![habit_id_str],
        |row| row.get(0),
    )?;

    // hold one HLC guard across the row write, the
    // outbox enqueue, and the changelog emit so the three writes mint
    // strictly-increasing versions from a single counter run instead
    // of re-locking the process-wide HLC mutex once per call.
    // this site rebuilt the lock three times (row at 850, envelope at
    // 880, changelog inside `log_cli_changelog`) — each lock/unlock
    // pair is a distinct counter generate, so a burst of concurrent
    // completions could interleave row, envelope, and changelog
    // versions in non-monotonic order.
    let mut hlc_guard = lock_shared(tx)?;
    let version = hlc_guard.generate().to_string();

    tx.execute(
        "INSERT INTO habit_completions (habit_id, completed_date, value, note, version, created_at, updated_at)
         VALUES (?1, ?2, 1, ?3, ?4, ?5, ?5)
         ON CONFLICT(habit_id, completed_date) DO UPDATE SET
            value = MIN(value + 1, ?6),
            note = COALESCE(excluded.note, note),
            version = excluded.version,
            updated_at = excluded.updated_at",
        rusqlite::params![
            habit_id_str,
            completed_date,
            note,
            version,
            now,
            target_count
        ],
    )?;

    let completion = load_habit_completion_row(tx, habit_id, &completed_date)?;

    let entity_id = format!("{habit_id_str}:{completed_date}");
    let sync_version = hlc_guard.generate().to_string();
    enqueue_payload_upsert(
        tx,
        EDGE_HABIT_COMPLETION,
        &entity_id,
        &habit_completion_payload(&completion),
        crate::commands::shared::bare_outbox_ctx(&sync_version, &device_id),
    )?;
    let after_json = Some(habit_completion_payload(&completion));
    log_cli_changelog_with_state(
        tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "complete",
            entity_type: EDGE_HABIT_COMPLETION,
            entity_id: &entity_id,
            summary: &format!(
                "Completed habit '{}' for {}",
                habit.name, completion.completed_date
            ),
            before_json,
            after_json,
        },
    )?;
    drop(hlc_guard);

    Ok((habit.name, completion))
}

pub(crate) fn uncomplete_habit_with_conn(
    conn: &mut Connection,
    habit_id: &lorvex_domain::HabitId,
    date: Option<&str>,
) -> Result<HabitUncompleteResult, crate::error::CliError> {
    if let Some(date) = date {
        lorvex_domain::validation::validate_date_format(date)?;
    }

    let habit_id_str = habit_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let habit = load_habit_row(&tx, habit_id)?;

    let tz = lorvex_workflow::timezone::active_timezone_name(&tx)?;
    let completed_date = date.map_or_else(
        || lorvex_domain::today_ymd_for_timezone_name(chrono::Utc::now(), tz.as_deref()),
        str::to_string,
    );
    let previous = load_habit_completion_row(&tx, habit_id, &completed_date)?;

    tx.execute(
        "DELETE FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
        rusqlite::params![habit_id_str, completed_date],
    )?;

    let entity_id = format!("{habit_id_str}:{completed_date}");
    // share one HLC guard across the tombstone enqueue
    // and the changelog emit so both versions advance off the same
    // counter run.
    let mut hlc_guard = lock_shared(&tx)?;
    let sync_version = hlc_guard.generate().to_string();
    enqueue_payload_delete(
        &tx,
        EDGE_HABIT_COMPLETION,
        &entity_id,
        &habit_completion_payload(&previous),
        crate::commands::shared::bare_outbox_ctx(&sync_version, &device_id),
    )?;
    let before_json = Some(habit_completion_payload(&previous));
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: OP_DELETE,
            entity_type: EDGE_HABIT_COMPLETION,
            entity_id: &entity_id,
            summary: &format!(
                "Removed completion for habit '{}' on {}",
                habit.name, completed_date
            ),
            before_json,
            after_json: None,
        },
    )?;
    drop(hlc_guard);

    bump_local_change_seq(&tx)?;
    tx.commit()?;

    Ok(HabitUncompleteResult {
        deleted: true,
        habit_id: habit.id,
        habit_name: habit.name,
        completed_date,
        previous,
    })
}
