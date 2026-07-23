#![allow(unused_imports)] // facade re-exports Tauri command entry points

use lorvex_domain::time::format_sync_timestamp;

use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use rusqlite::params;

use crate::commands::{
    clamp_limit, enqueue_task_reminder_delete, enqueue_task_reminder_upsert, fetch_task_by_id,
    fetch_tasks_by_ids, sync_timestamp_now, with_immediate_transaction, Task, TaskReminder,
    MAX_REMINDER_QUERY_WINDOW_SECONDS,
};

pub(crate) mod create;
pub(crate) mod delivery;
mod model;
pub(crate) mod read;
pub(crate) mod remove;
#[cfg(test)]
mod tests;

pub use create::add_task_reminder;
pub(crate) use create::snooze_reminder_for_task_internal;
#[cfg(test)]
use create::{
    add_task_reminder_in_transaction, add_task_reminder_with_conn, DEFAULT_REMINDER_SNOOZE_MINUTES,
    MAX_REMINDERS_PER_TASK,
};
pub use delivery::mark_reminder_notified;
#[cfg(test)]
use delivery::mark_reminder_notified_with_conn;
#[cfg(test)]
use model::hydrate_due_reminder_entries;
pub use model::DueReminderEntry;
#[cfg(test)]
use read::get_task_reminders_with_conn;
pub use read::{get_due_reminders, get_task_reminders, get_upcoming_reminders};
pub use remove::remove_task_reminder;
