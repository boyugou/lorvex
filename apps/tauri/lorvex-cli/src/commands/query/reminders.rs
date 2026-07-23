use crate::startup_maintenance::open_db_at_path;
use chrono::{Duration, SecondsFormat, Utc};
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::task::reminders;

use crate::cli::OutputFormat;
use crate::models::{TaskReminderSnapshot, TaskReminderSummary};
use crate::render::render_task_reminder_snapshot;

const TASK_REMINDERS_LIMIT_DEFAULT: u32 = 50;
const TASK_REMINDERS_LIMIT_CAP: u32 = 200;
const TASK_REMINDERS_UPCOMING_HOURS_DEFAULT: u32 = 24;
const TASK_REMINDERS_UPCOMING_HOURS_CAP: u32 = 168;

pub(crate) fn run_due_task_reminders(
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let limit = bounded_task_reminder_limit(limit);
    let now = Utc::now().to_rfc3339_opts(SecondsFormat::Micros, true);
    let result = reminders::get_due_task_reminders(&conn, &now, limit)?;
    let snapshot = task_reminder_snapshot(None, limit, result);
    render_task_reminder_snapshot("Due Task", &db_path, &snapshot, format)
}

pub(crate) fn run_upcoming_task_reminders(
    hours: u32,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let hours = match hours {
        0 => TASK_REMINDERS_UPCOMING_HOURS_DEFAULT,
        value => value.min(TASK_REMINDERS_UPCOMING_HOURS_CAP),
    };
    let limit = bounded_task_reminder_limit(limit);
    let now = Utc::now();
    let horizon = now + Duration::hours(i64::from(hours));
    let result = reminders::get_upcoming_task_reminders_until(
        &conn,
        &now.to_rfc3339_opts(SecondsFormat::Micros, true),
        &horizon.to_rfc3339_opts(SecondsFormat::Micros, true),
        limit,
    )?;
    let snapshot = task_reminder_snapshot(Some(hours), limit, result);
    render_task_reminder_snapshot("Upcoming Task", &db_path, &snapshot, format)
}

fn bounded_task_reminder_limit(limit: u32) -> u32 {
    match limit {
        0 => TASK_REMINDERS_LIMIT_DEFAULT,
        value => value.min(TASK_REMINDERS_LIMIT_CAP),
    }
}

pub(super) fn task_reminder_snapshot(
    hours_window: Option<u32>,
    limit: u32,
    result: reminders::ReminderQueryResult,
) -> TaskReminderSnapshot {
    let reminders = result
        .rows
        .into_iter()
        .map(|row| TaskReminderSummary {
            id: row.id,
            task_id: row.task_id,
            reminder_at: row.reminder_at,
            dismissed_at: row.dismissed_at,
            cancelled_at: row.cancelled_at,
            created_at: row.created_at,
            delivery_state: row.delivery_state,
            task_title: row.task_title,
            task_status: row.task_status,
            task_due_date: row.task_due_date,
            task_priority: row.task_priority,
        })
        .collect::<Vec<_>>();
    let returned = reminders.len();
    TaskReminderSnapshot {
        hours_window,
        limit,
        returned,
        total_matching: result.total_matching,
        truncated: result.total_matching < 0 || result.total_matching > returned as i64,
        reminders,
    }
}
