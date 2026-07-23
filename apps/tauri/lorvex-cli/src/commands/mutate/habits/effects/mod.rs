//! Habit definitions, completions, and reminder policies.
//!
//! Habits are recurring intentions ("meditate daily", "10 pages of
//! reading"). Completions are timestamped checkmarks per habit, and
//! reminder policies attach a per-day local time to a habit so the
//! agent can nudge the user. The CLI surface owns:
//!
//! - habit CRUD (create, update, delete with cascade)
//! - completions (`complete_habit_with_conn`,
//!   `uncomplete_habit_with_conn`)
//! - reminder policy CRUD
//!
//! `delete_habit_with_conn` cascades to completions + reminder
//! policies and emits a separate sync delete + changelog row for each
//! cascaded child so peers reconstruct the same end state.
//!
//! The submodule split mirrors the three sub-domains:
//!
//! - [`habit_crud`] — `create_habit_with_conn`, `update_habit_with_conn`,
//!   `delete_habit_with_conn` (with cascade). Further split into
//!   per-verb sibling files (`create.rs`, `update.rs`, `delete.rs`).
//! - [`reminder_policy`] — list/upsert/delete reminder policies.
//! - [`completions`] — completion + uncompletion plus the
//!   `complete_habit_in_tx` reusable variant for batched callers.
//!
//! This module file collects the shared utility surface (row loaders,
//! payload helpers, outbox enqueue wrappers, lookup-key collision check,
//! and completion-note validation) so each submodule can reach them via
//! `super::`.

mod completions;
mod habit_crud;
mod reminder_policy;
mod types;

use lorvex_domain::habits::WeekDay;
use lorvex_domain::naming::ENTITY_HABIT;
use lorvex_sync::outbox_enqueue::enqueue_payload_delete;
use lorvex_workflow::habit_reminder_ops;
use rusqlite::{Connection, OptionalExtension};

pub(crate) use completions::{
    complete_habit_in_tx, complete_habit_with_conn, uncomplete_habit_with_conn,
};
pub(crate) use habit_crud::{
    create_habit_with_conn, delete_habit_with_conn, update_habit_with_conn,
};
pub(crate) use reminder_policy::{
    delete_habit_reminder_policy_with_conn, list_habit_reminder_policies_with_conn,
    upsert_habit_reminder_policy_with_conn,
};
pub(crate) use types::{
    HabitCompletionRow, HabitDeleteResult, HabitReminderPolicyDeleteResult, HabitRow,
    HabitUncompleteResult, HabitUpdateFields,
};

pub(super) fn load_habit_row(
    conn: &Connection,
    habit_id: &lorvex_domain::HabitId,
) -> Result<HabitRow, crate::error::CliError> {
    conn.query_row(
        "SELECT id, name, icon, color, cue, frequency_type, per_period_target, day_of_month,
                target_count, archived, created_at, updated_at, version,
                (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays
                    WHERE habit_id = habits.id ORDER BY weekday)) AS weekdays
         FROM habits WHERE id = ?1",
        rusqlite::params![habit_id.as_str()],
        |row| {
            let weekdays_json: String = row.get(13)?;
            let weekdays: Vec<i64> = serde_json::from_str(&weekdays_json).map_err(|error| {
                rusqlite::Error::FromSqlConversionFailure(
                    13,
                    rusqlite::types::Type::Text,
                    Box::new(error),
                )
            })?;
            Ok(HabitRow {
                id: row.get(0)?,
                name: row.get(1)?,
                icon: row.get(2)?,
                color: row.get(3)?,
                cue: row.get(4)?,
                frequency_type: row.get(5)?,
                per_period_target: row.get(6)?,
                day_of_month: row.get(7)?,
                target_count: row.get(8)?,
                archived: row.get(9)?,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
                version: row.get(12)?,
                weekdays,
            })
        },
    )
    .optional()?
    .ok_or_else(|| {
        crate::error::CliError::NotFound(format!("habit '{}' not found", habit_id.as_str()))
    })
}

/// Delete-then-insert the `habit_weekdays` rows for one habit from a
/// weekday set — the parent-owned materialization rebuilt on every habit
/// create/update. An empty set leaves the habit with no weekday rows
/// ("every day" for a weekly cadence).
pub(super) fn rebuild_habit_weekdays(
    conn: &Connection,
    habit_id: &str,
    weekdays: &[WeekDay],
) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM habit_weekdays WHERE habit_id = ?1", [habit_id])?;
    for day in weekdays {
        conn.execute(
            "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?1, ?2)",
            rusqlite::params![habit_id, day.as_index()],
        )?;
    }
    Ok(())
}

pub(super) fn load_habit_completion_row(
    conn: &Connection,
    habit_id: &lorvex_domain::HabitId,
    completed_date: &str,
) -> Result<HabitCompletionRow, crate::error::CliError> {
    conn.query_row(
        "SELECT habit_id, completed_date, value, note, created_at, updated_at, version
         FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
        rusqlite::params![habit_id.as_str(), completed_date],
        |row| {
            Ok(HabitCompletionRow {
                habit_id: row.get(0)?,
                completed_date: row.get(1)?,
                value: row.get(2)?,
                note: row.get(3)?,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
                version: row.get(6)?,
            })
        },
    )
    .optional()?
    .ok_or_else(|| {
        crate::error::CliError::NotFound(format!(
            "no completion found for habit '{}' on {completed_date}",
            habit_id.as_str()
        ))
    })
}

pub(super) fn habit_completion_payload(completion: &HabitCompletionRow) -> serde_json::Value {
    let typed_habit_id = lorvex_domain::HabitId::from_trusted(completion.habit_id.clone());
    lorvex_store::payload_loaders::habit_completion_payload(
        &typed_habit_id,
        &completion.completed_date,
        completion.value,
        completion.note.as_deref(),
        &completion.version,
        &completion.created_at,
        &completion.updated_at,
    )
}

pub(super) fn habit_payload(
    conn: &Connection,
    habit_id: &lorvex_domain::HabitId,
) -> Result<serde_json::Value, crate::error::CliError> {
    lorvex_store::payload_loaders::load_habit_sync_payload(conn, habit_id)?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("habit '{}' not found", habit_id)))
}

pub(super) fn enqueue_habit_payload_delete_with_version(
    conn: &Connection,
    device_id: &str,
    habit_id: &lorvex_domain::HabitId,
    payload: &serde_json::Value,
    version: &str,
) -> Result<(), crate::error::CliError> {
    enqueue_payload_delete(
        conn,
        ENTITY_HABIT,
        habit_id.as_str(),
        payload,
        crate::commands::shared::bare_outbox_ctx(version, device_id),
    )?;
    Ok(())
}

pub(super) fn habit_reminder_policy_delete_payload(
    policy: &habit_reminder_ops::HabitReminderPolicyRow,
) -> serde_json::Value {
    // the changelog `before_json` was structurally narrower than the
    // sync envelope (which goes through spb). Routing through the spb
    // primitive closes the drift.
    let typed_policy_id = lorvex_domain::HabitReminderPolicyId::from_trusted(policy.id.clone());
    let typed_habit_id = lorvex_domain::HabitId::from_trusted(policy.habit_id.clone());
    lorvex_store::payload_loaders::habit_reminder_policy_payload(
        &typed_policy_id,
        &typed_habit_id,
        &policy.reminder_time,
        policy.enabled,
        &policy.version,
        &policy.created_at,
        &policy.updated_at,
    )
}

/// dedup via the persisted `lookup_key` column. The
/// partial UNIQUE index `idx_habits_lookup_key_active` is the
/// canonical schema-layer contract; this pre-check is just for
/// surfacing a typed Conflict error before SQLite raises a generic
/// `UNIQUE constraint failed` on the INSERT/UPDATE.
pub(super) fn active_habit_lookup_key_exists(
    conn: &Connection,
    lookup_key: &str,
    exclude_id: Option<&str>,
) -> Result<bool, crate::error::CliError> {
    let exists: i64 = match exclude_id {
        Some(id) => conn.query_row(
            "SELECT COUNT(*) FROM habits WHERE lookup_key = ?1 AND id != ?2 AND archived = 0",
            rusqlite::params![lookup_key, id],
            |row| row.get(0),
        )?,
        None => conn.query_row(
            "SELECT COUNT(*) FROM habits WHERE lookup_key = ?1 AND archived = 0",
            rusqlite::params![lookup_key],
            |row| row.get(0),
        )?,
    };
    Ok(exists > 0)
}

pub(super) fn validate_optional_completion_note(
    note: Option<&str>,
) -> Result<Option<String>, crate::error::CliError> {
    let Some(note) = note else {
        return Ok(None);
    };
    let sanitized = lorvex_domain::sanitize_user_text(note);
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    lorvex_domain::validation::validate_string_length(
        trimmed,
        "note",
        lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
    )?;
    Ok(Some(trimmed.to_string()))
}

#[cfg(test)]
mod tests;
