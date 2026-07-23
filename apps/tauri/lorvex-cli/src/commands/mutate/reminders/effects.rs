//! Per-task reminder mutations.
//!
//! Reminders are timestamped pings attached to a task. The CLI
//! surface offers three operations: bulk-set the active set
//! (`set_task_reminders_with_conn`), append a single
//! (`add_task_reminder_with_conn`), and remove one
//! (`remove_task_reminder_with_conn`). Each mutation pairs an
//! `entity_upsert` on the parent task with the per-reminder
//! upsert/delete so peers see a single coherent change.
//!
//! `resolve_reminder_local_anchor` snapshots the user's wall-clock
//! interpretation at write time so DST shifts and tz changes don't
//! retroactively move the reminder.

use chrono::{TimeZone, Utc};
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_REMINDER, OP_DELETE};
use lorvex_domain::{ReminderId, TaskId};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_delete};
use rusqlite::{Connection, OptionalExtension};

use crate::commands::shared::{load_task_row, log_cli_changelog_with_state};
use crate::models::{TaskReminderMutationResult, TaskReminderRow};

// re-export the canonical cap from
// `lorvex_domain::validation` so CLI / MCP / Tauri never drift on
// the same number under different names.
pub(super) use lorvex_domain::validation::MAX_REMINDERS_PER_TASK as MAX_TASK_REMINDERS_PER_TASK;

fn resolve_reminder_local_anchor(
    conn: &Connection,
    reminder_at_rfc3339: &str,
) -> Result<(Option<String>, Option<String>), crate::error::CliError> {
    let Some(tz_name) = lorvex_workflow::timezone::active_timezone_name(conn)? else {
        return Ok((None, None));
    };
    let Some(tz) = lorvex_domain::parse_timezone_name(&tz_name) else {
        return Ok((None, None));
    };
    let Ok(reminder_utc) = chrono::DateTime::parse_from_rfc3339(reminder_at_rfc3339) else {
        return Ok((None, None));
    };
    let local = tz.from_utc_datetime(&reminder_utc.with_timezone(&Utc).naive_utc());
    Ok((Some(local.format("%H:%M").to_string()), Some(tz_name)))
}

fn validate_task_reminder_timestamps(reminders: &[String]) -> Result<(), crate::error::CliError> {
    if reminders.len() > MAX_TASK_REMINDERS_PER_TASK {
        return Err(crate::error::CliError::Validation(format!(
            "reminders has {} entries (limit {})",
            reminders.len(),
            MAX_TASK_REMINDERS_PER_TASK
        )));
    }
    for reminder_at in reminders {
        chrono::DateTime::parse_from_rfc3339(reminder_at).map_err(|_| {
            crate::error::CliError::Validation(format!(
                "invalid reminder timestamp '{reminder_at}'; expected RFC 3339 datetime"
            ))
        })?;
    }
    Ok(())
}

fn load_task_reminder_rows(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<TaskReminderRow>, crate::error::CliError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, task_id, reminder_at, dismissed_at, cancelled_at, created_at,
                original_local_time, original_tz
         FROM task_reminders
         WHERE task_id = ?1
         ORDER BY reminder_at ASC, id ASC",
    )?;
    let rows = stmt
        .query_map([task_id.as_str()], |row| {
            Ok(TaskReminderRow {
                id: row.get(0)?,
                task_id: row.get(1)?,
                reminder_at: row.get(2)?,
                dismissed_at: row.get(3)?,
                cancelled_at: row.get(4)?,
                created_at: row.get(5)?,
                original_local_time: row.get(6)?,
                original_tz: row.get(7)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub(crate) fn set_task_reminders_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    reminders: &[String],
) -> Result<TaskReminderMutationResult, crate::error::CliError> {
    validate_task_reminder_timestamps(reminders)?;

    let task_id_str = task_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let task = load_task_row(&tx, task_id)?;
    let now = lorvex_domain::sync_timestamp_now();
    // capture FULL pre-delete reminder rows (not just
    // ids) so each per-reminder DELETE envelope below carries the
    // row as a snapshot. The previous shape used \`enqueue_entity_delete\`
    // which writes an empty `{}` payload — same #2818 sync
    // correctness loss class.
    let old_reminders: Vec<(String, serde_json::Value)> = {
        let mut stmt = tx.prepare(
            "SELECT id, task_id, reminder_at, dismissed_at, cancelled_at,
                    created_at, original_local_time, original_tz, version
             FROM task_reminders
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL
             ORDER BY reminder_at ASC, id ASC",
        )?;
        let rows = stmt.query_map([task_id_str], |row| {
            let id: String = row.get(0)?;
            let payload = serde_json::json!({
                "id": id,
                "task_id": row.get::<_, String>(1)?,
                "reminder_at": row.get::<_, String>(2)?,
                "dismissed_at": row.get::<_, Option<String>>(3)?,
                "cancelled_at": row.get::<_, Option<String>>(4)?,
                "created_at": row.get::<_, String>(5)?,
                "original_local_time": row.get::<_, Option<String>>(6)?,
                "original_tz": row.get::<_, Option<String>>(7)?,
                "version": row.get::<_, String>(8)?,
            });
            Ok((id, payload))
        })?;
        rows.collect::<Result<Vec<_>, _>>()?
    };

    tx.execute(
        "DELETE FROM task_reminders
         WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
        [task_id_str],
    )?;

    // hoist a single HLC guard across BOTH the per-row
    // INSERT loop and the outbox enqueue + changelog block.
    // INSERT loop minted each row's `version` via `next_hlc_version`,
    // which re-locked the process-wide HLC mutex on every iteration —
    // an N-reminder rebuild took 2N+2 lock/unlock pairs (N in the
    // INSERT loop, N+1 in the outbox block, 1 in the changelog). One
    // shared guard scoped to the whole tx mints every version off a
    // single counter run.
    let mut hlc_guard = crate::hlc_guard::lock_shared(&tx)?;
    let mut new_reminder_ids = Vec::with_capacity(reminders.len());
    if !reminders.is_empty() {
        let mut stmt = tx.prepare_cached(
            "INSERT INTO task_reminders
               (id, task_id, reminder_at, original_local_time, original_tz, version, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        )?;
        for reminder_at in reminders {
            let reminder_id = lorvex_domain::new_entity_id_string();
            let version = hlc_guard.generate().to_string();
            let (original_local_time, original_tz) =
                resolve_reminder_local_anchor(&tx, reminder_at)?;
            stmt.execute(rusqlite::params![
                reminder_id,
                task_id_str,
                reminder_at,
                original_local_time,
                original_tz,
                version,
                now,
            ])?;
            new_reminder_ids.push(reminder_id);
        }
    }

    {
        let hlc_state = &mut *hlc_guard;
        enqueue_entity_upsert(&tx, ENTITY_TASK, task_id_str, hlc_state, &device_id)?;
        // each per-reminder DELETE carries the row's
        // pre-delete snapshot via `enqueue_payload_delete`.
        for (old_id, old_payload) in &old_reminders {
            let delete_version = hlc_state.generate().to_string();
            enqueue_payload_delete(
                &tx,
                ENTITY_TASK_REMINDER,
                old_id,
                old_payload,
                crate::commands::shared::bare_outbox_ctx(&delete_version, &device_id),
            )?;
        }
        for new_id in &new_reminder_ids {
            enqueue_entity_upsert(&tx, ENTITY_TASK_REMINDER, new_id, hlc_state, &device_id)?;
        }
    }

    let summary = if reminders.is_empty() {
        format!("Cleared all reminders for '{}'", task.core().title())
    } else {
        format!(
            "Set {} reminder{} for '{}'",
            reminders.len(),
            if reminders.len() == 1 { "" } else { "s" },
            task.core().title()
        )
    };
    // ship the parent task's pre/post snapshots so the
    // changelog row that summarizes a reminder set rebuild has the
    // task state on both sides.
    let after_task = load_task_row(&tx, task_id)?;
    let before_json = Some(serde_json::to_value(&task)?);
    let after_json = Some(serde_json::to_value(&after_task)?);
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "set_reminders",
            entity_type: ENTITY_TASK,
            entity_id: task_id_str,
            summary: &summary,
            before_json,
            after_json,
        },
    )?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;

    let reminders = load_task_reminder_rows(&tx, task_id)?;
    tx.commit()?;
    Ok(TaskReminderMutationResult {
        task: after_task,
        reminders,
    })
}

pub(crate) fn add_task_reminder_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    reminder_at: &str,
) -> Result<TaskReminderMutationResult, crate::error::CliError> {
    validate_task_reminder_timestamps(&[reminder_at.to_string()])?;

    let task_id_str = task_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let task = load_task_row(&tx, task_id)?;
    let existing_count: i64 = tx.query_row(
        "SELECT COUNT(*) FROM task_reminders
         WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
        [task_id_str],
        |row| row.get(0),
    )?;
    if existing_count >= MAX_TASK_REMINDERS_PER_TASK as i64 {
        return Err(crate::error::CliError::Conflict(format!(
            "task already has {existing_count} active reminders (limit {MAX_TASK_REMINDERS_PER_TASK})"
        )));
    }

    let reminder_id = lorvex_domain::new_entity_id_string();
    let now = lorvex_domain::sync_timestamp_now();
    let (original_local_time, original_tz) = resolve_reminder_local_anchor(&tx, reminder_at)?;
    // single HLC guard across the row insert, the two
    // outbox enqueues, and the changelog so all four versions advance
    // off the same counter run.
    let mut hlc_guard = crate::hlc_guard::lock_shared(&tx)?;
    let version = hlc_guard.generate().to_string();
    tx.execute(
        "INSERT INTO task_reminders
           (id, task_id, reminder_at, original_local_time, original_tz, version, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            reminder_id,
            task_id_str,
            reminder_at,
            original_local_time,
            original_tz,
            version,
            now,
        ],
    )?;

    {
        let hlc_state = &mut *hlc_guard;
        enqueue_entity_upsert(&tx, ENTITY_TASK, task_id_str, hlc_state, &device_id)?;
        enqueue_entity_upsert(
            &tx,
            ENTITY_TASK_REMINDER,
            &reminder_id,
            hlc_state,
            &device_id,
        )?;
    }
    // capture the parent task before/after the reminder
    // append so the audit row carries both states.
    let after_task = load_task_row(&tx, task_id)?;
    let before_task_json = Some(serde_json::to_value(&task)?);
    let after_task_json = Some(serde_json::to_value(&after_task)?);
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "set_reminders",
            entity_type: ENTITY_TASK,
            entity_id: task_id_str,
            summary: &format!(
                "Added reminder for '{}' at {reminder_at}",
                task.core().title()
            ),
            before_json: before_task_json,
            after_json: after_task_json,
        },
    )?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;

    let reminders = load_task_reminder_rows(&tx, task_id)?;
    tx.commit()?;
    Ok(TaskReminderMutationResult {
        task: after_task,
        reminders,
    })
}

pub(crate) fn remove_task_reminder_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    reminder_id: &ReminderId,
) -> Result<TaskReminderMutationResult, crate::error::CliError> {
    let task_id_str = task_id.as_str();
    let reminder_id_str = reminder_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let task = load_task_row(&tx, task_id)?;
    // capture the FULL pre-delete reminder row (not just
    // reminder_at) so the per-reminder DELETE envelope below carries
    // the row's full state. The previous shape used
    // `enqueue_entity_delete` with an empty `{}` payload.
    let reminder_payload: serde_json::Value = tx
        .query_row(
            "SELECT id, task_id, reminder_at, dismissed_at, cancelled_at,
                    created_at, original_local_time, original_tz, version
             FROM task_reminders WHERE id = ?1 AND task_id = ?2",
            rusqlite::params![reminder_id_str, task_id_str],
            |row| {
                Ok(serde_json::json!({
                    "id": row.get::<_, String>(0)?,
                    "task_id": row.get::<_, String>(1)?,
                    "reminder_at": row.get::<_, String>(2)?,
                    "dismissed_at": row.get::<_, Option<String>>(3)?,
                    "cancelled_at": row.get::<_, Option<String>>(4)?,
                    "created_at": row.get::<_, String>(5)?,
                    "original_local_time": row.get::<_, Option<String>>(6)?,
                    "original_tz": row.get::<_, Option<String>>(7)?,
                    "version": row.get::<_, String>(8)?,
                }))
            },
        )
        .optional()?
        .ok_or_else(|| {
            crate::error::CliError::NotFound(format!(
                "reminder '{reminder_id_str}' not found for task '{task_id_str}'"
            ))
        })?;
    let reminder_at = reminder_payload
        .get("reminder_at")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    tx.execute(
        "DELETE FROM task_reminders WHERE id = ?1 AND task_id = ?2",
        rusqlite::params![reminder_id_str, task_id_str],
    )?;
    let now = lorvex_domain::sync_timestamp_now();

    // single HLC guard around the parent-task touch + outbox +
    // both changelog emits so all stamps sort off one counter run.
    let mut hlc_guard = crate::hlc_guard::lock_shared(&tx)?;
    // mint and stamp a fresh `version` on the parent
    // task row.
    // `updated_at` — peer caches kept the stale reminder set because
    // the parent row's enqueued upsert lex-sorted below any peer's
    // recent stamp and LWW silently dropped it.
    let parent_version = hlc_guard.generate().to_string();
    lorvex_workflow::task_reminders::touch_parent_task_op(&tx, task_id, &parent_version, &now)?;
    {
        let hlc_state = &mut *hlc_guard;
        enqueue_entity_upsert(&tx, ENTITY_TASK, task_id_str, hlc_state, &device_id)?;
        // ship the captured pre-delete snapshot.
        let delete_version = hlc_state.generate().to_string();
        enqueue_payload_delete(
            &tx,
            ENTITY_TASK_REMINDER,
            reminder_id_str,
            &reminder_payload,
            crate::commands::shared::bare_outbox_ctx(&delete_version, &device_id),
        )?;
    }
    // capture the parent task pre/post and the
    // reminder row's pre-delete snapshot so both audit rows carry
    // restorable state.
    let after_task = load_task_row(&tx, task_id)?;
    let before_task_json = Some(serde_json::to_value(&task)?);
    let after_task_json = Some(serde_json::to_value(&after_task)?);
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: "set_reminders",
            entity_type: ENTITY_TASK,
            entity_id: task_id_str,
            summary: &format!(
                "Removed reminder at {reminder_at} for '{}'",
                task.core().title()
            ),
            before_json: before_task_json,
            after_json: after_task_json,
        },
    )?;
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        crate::commands::shared::CliChangelogParams {
            operation: OP_DELETE,
            entity_type: ENTITY_TASK_REMINDER,
            entity_id: reminder_id_str,
            summary: &format!("Removed reminder at {reminder_at}"),
            before_json: Some(reminder_payload),
            after_json: None,
        },
    )?;
    drop(hlc_guard);
    bump_local_change_seq(&tx)?;

    let reminders = load_task_reminder_rows(&tx, task_id)?;
    tx.commit()?;
    Ok(TaskReminderMutationResult {
        task: after_task,
        reminders,
    })
}
