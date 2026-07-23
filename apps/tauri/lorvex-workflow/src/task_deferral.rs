//! Shared task deferral operation.
//!
//! Both the MCP server and Tauri app delegate the core SQL mutation here.
//! Adapter-specific concerns (changelog, sync enqueue) remain in each boundary,
//! but `ai_notes` is folded into the atomic UPDATE via `TaskDeferralPatch`.

use lorvex_domain::TaskId;
use rusqlite::{Connection, OptionalExtension};

use lorvex_store::StoreError;

/// Parameters for a task deferral.
#[derive(Debug, Clone, Default)]
pub struct TaskDeferralPatch<'a> {
    /// New planned date. Some = set, None = leave unchanged.
    pub planned_date: Option<&'a str>,
    /// New ai_notes value. Some = overwrite, None = leave unchanged.
    pub ai_notes: Option<&'a str>,
    /// Structured defer reason. Some = set, None = leave unchanged.
    pub last_defer_reason: Option<&'a str>,
}

/// Result of applying a task deferral.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TaskDeferralResult {
    pub updated: bool,
    pub shifted_reminder_ids: Vec<String>,
}

#[derive(Debug, Clone)]
struct ReminderShiftContext {
    old_reference_date: String,
    new_planned_date: String,
}

/// Apply a single task deferral atomically.
///
/// Updates `planned_date` (if provided), `ai_notes` (if provided),
/// `last_defer_reason` (if provided), increments `defer_count`, stamps `last_deferred_at`, `version`,
/// and `updated_at` in a single UPDATE.
///
/// If the planned date changes, pending reminders anchored to the task's
/// previous planned/due date move by the same calendar-day delta. The caller
/// supplies reminder HLC stamps because each runtime owns its HLC state, while
/// the store owns the common SQL semantics.
pub fn defer_task<E>(
    conn: &Connection,
    task_id: &TaskId,
    patch: &TaskDeferralPatch<'_>,
    version: &str,
    now: &str,
    mut next_reminder_version: impl FnMut() -> Result<String, E>,
) -> Result<TaskDeferralResult, E>
where
    E: From<rusqlite::Error> + From<StoreError> + From<String> + std::fmt::Display,
{
    lorvex_store::transaction::with_savepoint(conn, "task_deferral", |conn| {
        defer_task_inner(
            conn,
            task_id,
            patch,
            version,
            now,
            &mut next_reminder_version,
        )
    })
}

fn defer_task_inner<E>(
    conn: &Connection,
    task_id: &TaskId,
    patch: &TaskDeferralPatch<'_>,
    version: &str,
    now: &str,
    next_reminder_version: &mut impl FnMut() -> Result<String, E>,
) -> Result<TaskDeferralResult, E>
where
    E: From<StoreError>,
{
    let reminder_shift = match patch.planned_date {
        Some(new_planned_date) => load_reminder_shift_context(conn, task_id, new_planned_date)?,
        None => None,
    };

    // Build dynamic SET clauses
    let mut set_clauses =
        vec!["defer_count = MIN(defer_count + 1, 9223372036854775807)".to_string()];
    let mut params: Vec<&dyn rusqlite::types::ToSql> = Vec::new();

    if let Some(ref date) = patch.planned_date {
        params.push(date);
        set_clauses.push(format!("planned_date = ?{}", params.len()));
    }
    if let Some(ref notes) = patch.ai_notes {
        params.push(notes);
        set_clauses.push(format!("ai_notes = ?{}", params.len()));
    }
    if let Some(ref reason) = patch.last_defer_reason {
        params.push(reason);
        set_clauses.push(format!("last_defer_reason = ?{}", params.len()));
    }

    // Always set these
    params.push(&now);
    let now_idx = params.len();
    set_clauses.push(format!("last_deferred_at = ?{now_idx}"));
    set_clauses.push(format!("updated_at = ?{now_idx}"));

    params.push(&version);
    let version_idx = params.len();
    set_clauses.push(format!("version = ?{version_idx}"));

    params.push(&task_id);
    let id_idx = params.len();

    // gate the UPDATE on `?version_idx > version` so a
    // stale local stamp loses to an in-flight peer write that already
    // landed a newer version. Returns `Ok(false)` so the boundary
    // layer can re-stamp HLC and retry — same shape as the existing
    // "task already terminal" no-op return.
    let sql = format!(
        "UPDATE tasks SET {} \
         WHERE id = ?{id_idx} AND status NOT IN ('completed', 'cancelled') \
         AND ?{version_idx} > version",
        set_clauses.join(", ")
    );

    let changes = conn
        .execute(&sql, params.as_slice())
        .map_err(StoreError::from)?;
    if changes == 0 {
        return Ok(TaskDeferralResult::default());
    }

    let shifted_reminder_ids = match reminder_shift {
        Some(context) => shift_pending_reminders_to_new_planned_date(
            conn,
            task_id,
            &context,
            now,
            next_reminder_version,
        )?,
        None => Vec::new(),
    };

    Ok(TaskDeferralResult {
        updated: true,
        shifted_reminder_ids,
    })
}

fn load_reminder_shift_context(
    conn: &Connection,
    task_id: &TaskId,
    new_planned_date: &str,
) -> Result<Option<ReminderShiftContext>, StoreError> {
    let old_reference_date: Option<String> = conn
        .query_row(
            "SELECT COALESCE(planned_date, due_date) FROM tasks WHERE id = ?1",
            rusqlite::params![task_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();
    Ok(
        old_reference_date.map(|old_reference_date| ReminderShiftContext {
            old_reference_date,
            new_planned_date: new_planned_date.to_string(),
        }),
    )
}

fn shift_pending_reminders_to_new_planned_date<E>(
    conn: &Connection,
    task_id: &TaskId,
    context: &ReminderShiftContext,
    now: &str,
    next_reminder_version: &mut impl FnMut() -> Result<String, E>,
) -> Result<Vec<String>, E>
where
    E: From<StoreError>,
{
    // Audit (silent-failure-hunter):
    // here returned empty / continued silently, so a corrupt stored
    // date string would defer the task without shifting reminders and
    // the user got no signal. Both reference dates came from validated
    // write paths, so a parse failure implies on-disk corruption —
    // surface as `StoreError::Validation` so the deferral fails loudly
    // rather than silently leaving stale reminders.
    let old_date = chrono::NaiveDate::parse_from_str(&context.old_reference_date, "%Y-%m-%d")
        .map_err(|e| {
            StoreError::Validation(format!(
                "shift_pending_reminders: corrupt old_reference_date {:?}: {e}",
                context.old_reference_date
            ))
        })?;
    let new_date = chrono::NaiveDate::parse_from_str(&context.new_planned_date, "%Y-%m-%d")
        .map_err(|e| {
            StoreError::Validation(format!(
                "shift_pending_reminders: corrupt new_planned_date {:?}: {e}",
                context.new_planned_date
            ))
        })?;
    let delta_days = (new_date - old_date).num_days();
    if delta_days == 0 {
        return Ok(Vec::new());
    }

    let pending_reminders = {
        let mut stmt = conn
            .prepare_cached(
                "SELECT id, reminder_at FROM task_reminders \
                 WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL \
                   AND reminder_at > ?2",
            )
            .map_err(StoreError::from)?;
        let rows = stmt
            .query_map(rusqlite::params![task_id, now], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(StoreError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(StoreError::from)?;
        rows
    };

    let mut shifted_ids = Vec::new();
    for (reminder_id, reminder_at_str) in pending_reminders {
        let parsed = chrono::DateTime::parse_from_rfc3339(&reminder_at_str).map_err(|e| {
            StoreError::Validation(format!(
                "shift_pending_reminders: corrupt stored reminder_at {reminder_at_str:?} for reminder {reminder_id}: {e}"
            ))
        })?;
        let shifted = parsed + chrono::Duration::days(delta_days);
        let new_reminder_at =
            lorvex_domain::format_sync_timestamp(shifted.with_timezone(&chrono::Utc));
        let reminder_version = next_reminder_version()?;
        let changes = conn
            .execute(
                "UPDATE task_reminders SET reminder_at = ?1, version = ?2 \
                 WHERE id = ?3 AND ?2 > version",
                rusqlite::params![new_reminder_at, reminder_version, reminder_id],
            )
            .map_err(StoreError::from)?;
        if changes > 0 {
            shifted_ids.push(reminder_id);
        }
    }
    Ok(shifted_ids)
}

/// Reset task deferral state: clear planned_date, last_deferred_at,
/// last_defer_reason, and reset defer_count to 0.
///
/// gated by `?1 > version`. A stale local stamp
/// returns `Ok(false)` so the caller can re-stamp HLC and retry.
pub fn reset_task_deferral(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    now: &str,
) -> Result<bool, StoreError> {
    let changes = conn
        .prepare_cached(
            "UPDATE tasks SET \
             planned_date = NULL, \
             last_deferred_at = NULL, \
             last_defer_reason = NULL, \
             defer_count = 0, \
             version = ?1, \
             updated_at = ?2 \
             WHERE id = ?3 AND status NOT IN ('completed', 'cancelled') \
             AND ?1 > version",
        )?
        .execute(rusqlite::params![version, now, task_id])?;
    Ok(changes > 0)
}

#[derive(Debug, Clone)]
pub struct TaskDeferralSnapshot<'a> {
    pub planned_date: Option<&'a str>,
    pub defer_count: i64,
    pub last_deferred_at: Option<&'a str>,
    pub last_defer_reason: Option<&'a str>,
}

/// Restore the exact pre-defer deferral state captured in `snapshot`.
/// Used by the single-action "Undo" toast path.
///
/// gated by `?5 > version`. A stale local stamp
/// returns `Ok(false)` so the caller can re-stamp HLC and retry
/// instead of clobbering a freshly-applied peer write.
pub fn restore_task_deferral(
    conn: &Connection,
    task_id: &TaskId,
    snapshot: &TaskDeferralSnapshot<'_>,
    version: &str,
    now: &str,
) -> Result<bool, StoreError> {
    let changes = conn
        .prepare_cached(
            "UPDATE tasks SET \
             planned_date = ?1, \
             defer_count = ?2, \
             last_deferred_at = ?3, \
             last_defer_reason = ?4, \
             version = ?5, \
             updated_at = ?6 \
             WHERE id = ?7 AND status NOT IN ('completed', 'cancelled') \
             AND ?5 > version",
        )?
        .execute(rusqlite::params![
            snapshot.planned_date,
            snapshot.defer_count,
            snapshot.last_deferred_at,
            snapshot.last_defer_reason,
            version,
            now,
            task_id,
        ])?;
    Ok(changes > 0)
}

#[cfg(test)]
mod tests;
