use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK_REMINDER, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use serde_json::Value;

use crate::commands::shared::effects::execute_ipc_entity_mutation;

use super::*;

/// Maximum reminders per task. Cast from
/// `lorvex_domain::validation::MAX_REMINDERS_PER_TASK` (a `usize`) so
/// CLI / MCP / Tauri share a single source of truth. The local `i64`
/// alias bridges the type — every comparison in this file is against
/// `existing_count: i64`.
pub(super) const MAX_REMINDERS_PER_TASK: i64 =
    lorvex_domain::validation::MAX_REMINDERS_PER_TASK as i64;

fn resolve_reminder_local_anchor(
    conn: &rusqlite::Connection,
    reminder_utc: &chrono::DateTime<chrono::Utc>,
) -> AppResult<(Option<String>, Option<String>)> {
    Ok(
        lorvex_workflow::reminder_anchor::resolve_task_reminder_local_anchor_for_utc(
            conn,
            reminder_utc,
        )?,
    )
}

/// Add a reminder for a task.
/// Also creates a `task_reminder_delivery_state` row with `delivery_state = 'pending'`.
pub(super) fn add_task_reminder_with_conn(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    reminder_at: &str,
    now: &str,
) -> AppResult<TaskReminder> {
    let reminder_at =
        lorvex_domain::canonicalize_rfc3339_instant(reminder_at).ok_or_else(|| {
            AppError::Validation(
                "reminder_at must be a valid RFC 3339 timestamp (e.g. 2025-12-01T09:00:00Z)"
                    .to_string(),
            )
        })?;
    let reminder_dt = chrono::DateTime::parse_from_rfc3339(&reminder_at)
        .expect("canonicalized reminder timestamp must parse");
    fetch_task_by_id(conn, task_id.as_str()).map(|_| ())?;

    // Enforce active per-task reminder count limit. Cancelled/dismissed
    // history must not permanently consume a task's reminder budget.
    let existing_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminders
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
            params![task_id.as_str()],
            |row| row.get(0),
        )
        .map_err(AppError::from)?;
    if existing_count >= MAX_REMINDERS_PER_TASK {
        return Err(AppError::Validation(format!(
            "Task already has {existing_count} active reminders (limit {MAX_REMINDERS_PER_TASK})"
        )));
    }

    // capture the reminder's intended local wall-clock
    // anchor (HH:MM + IANA tz) at creation time. Later timezone changes
    // re-materialize `reminder_at` from this anchor to preserve the
    // user's semantic intent ("remind me at 9 AM") across zone moves.
    // If PREF_TIMEZONE is unset (fresh install, MCP-only boot) we
    // leave both anchor columns NULL and the reminder keeps the old
    // absolute-UTC semantics — the re-anchor sweep skips rows without
    // an anchor.
    let (original_local_time, original_tz) =
        resolve_reminder_local_anchor(conn, &reminder_dt.with_timezone(&chrono::Utc))?;

    let id = lorvex_domain::new_entity_id_string();

    let mutation = AddTaskReminderMutation {
        id: &id,
        task_id,
        reminder_at: &reminder_at,
        original_local_time: original_local_time.as_deref(),
        original_tz: original_tz.as_deref(),
        now,
    };
    execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
        enqueue_task_reminder_upsert(conn, &id)?;
        Ok(())
    })?;

    Ok(TaskReminder {
        id,
        task_id: task_id.as_str().to_string(),
        reminder_at,
        dismissed_at: None,
        cancelled_at: None,
        created_at: now.to_string(),
        delivery_state: Some("pending".to_string()),
    })
}

/// Descriptor for inserting a single task reminder. Owns both the
/// `task_reminders` INSERT (synced) and the device-local
/// `task_reminder_delivery_state` companion row — the executor's
/// HLC session stamps the reminder version once for the pair.
struct AddTaskReminderMutation<'a> {
    id: &'a str,
    task_id: &'a lorvex_domain::TaskId,
    reminder_at: &'a str,
    original_local_time: Option<&'a str>,
    original_tz: Option<&'a str>,
    now: &'a str,
}

impl<'a> Mutation for AddTaskReminderMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK_REMINDER
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &rusqlite::Connection) -> Result<Option<Value>, StoreError> {
        // No pre-row by definition (INSERT path) and no Tauri audit
        // funnel that would consume the snapshot.
        Ok(None)
    }

    fn apply(
        &self,
        conn: &rusqlite::Connection,
        hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        conn.execute(
            "INSERT INTO task_reminders (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                self.id,
                self.task_id.as_str(),
                self.reminder_at,
                self.original_local_time,
                self.original_tz,
                version,
                self.now,
            ],
        )?;
        // Device-local delivery state companion. Not synced, but kept
        // inside the same `apply` so a row never escapes without its
        // delivery-state shadow.
        conn.execute(
            "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at) \
             VALUES (?1, 'pending', ?2)",
            params![self.id, self.now],
        )?;
        Ok(MutationOutput::new(
            serde_json::json!({ "id": self.id, "task_id": self.task_id.as_str() }),
            format!("Added reminder {} for task {}", self.id, self.task_id),
        ))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn add_task_reminder_inner(
    task_id: lorvex_domain::TaskId,
    reminder_at: String,
) -> AppResult<TaskReminder> {
    let conn = get_conn()?;
    let now = sync_timestamp_now();
    // event_bus emit is handled by the
    // `execute_ipc_entity_mutation` finalizer (see `AddTaskReminderMutation`).
    add_task_reminder_in_transaction(&conn, &task_id, &reminder_at, &now)
}

pub(super) fn add_task_reminder_in_transaction(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    reminder_at: &str,
    now: &str,
) -> AppResult<TaskReminder> {
    with_immediate_transaction(conn, |conn| {
        add_task_reminder_with_conn(conn, task_id, reminder_at, now)
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_task_reminder(task_id: String, reminder_at: String) -> Result<TaskReminder, String> {
    // task ids are UUIDv7 — shape-check before the
    // writer transaction. `reminder_at` retains its RFC 3339 check
    // inside `add_task_reminder_with_conn`.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let task_id = lorvex_domain::TaskId::from_trusted(task_id_str);
    add_task_reminder_inner(task_id, reminder_at).map_err(String::from)
}

/// Default snooze duration, in minutes, when the user taps the "Snooze"
/// action on a reminder notification.
pub(super) const DEFAULT_REMINDER_SNOOZE_MINUTES: i64 = 60;

/// Create a new reminder for `task_id` scheduled for
/// `now + DEFAULT_REMINDER_SNOOZE_MINUTES`. Shared implementation behind the
/// TypeScript-side "Snooze" button and the macOS/Windows native notification
/// action handlers. Keeping a single call site ensures all three platforms
/// produce identical semantics (a new reminder on the same task rather than
/// a whole-task deferral).
///
/// Returns the newly-created `TaskReminder`. The original reminder's
/// `task_reminder_delivery_state` row is expected to already be marked
/// `delivered` by the notification fire pipeline, so there is no loop.
pub(crate) fn snooze_reminder_for_task_internal(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
) -> AppResult<TaskReminder> {
    let now_dt = chrono::Utc::now();
    let snooze_until = now_dt + chrono::Duration::minutes(DEFAULT_REMINDER_SNOOZE_MINUTES);
    // Every timestamp writer in the codebase routes through
    // `sync_timestamp_now` / `format_sync_timestamp`, which produce
    // millisecond-Z form (see
    // `lorvex-domain/src/time/sync_timestamp.rs`). Using
    // `SecondsFormat::Micros` here would stamp 6-digit fractions into
    // the same `task_reminders.reminder_at` / `created_at` columns
    // the notification poller lex-compares against
    // `sync_timestamp_now()` results — drifting reminders at the
    // fractional-second boundary.
    let reminder_at = format_sync_timestamp(snooze_until);
    let now = format_sync_timestamp(now_dt);
    add_task_reminder_in_transaction(conn, task_id, &reminder_at, &now)
}
