//! Per-task reminder query/write arms. Reminders are children of tasks
//! but get their own domain because the surface (due/upcoming queries +
//! set/clear/add/remove writes) is large enough to warrant separation.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum RemindersCommand {
    Due {
        limit: u32,
        format: OutputFormat,
    },
    Upcoming {
        hours: u32,
        limit: u32,
        format: OutputFormat,
    },
    Set {
        task_id: String,
        reminders: Vec<String>,
        format: OutputFormat,
    },
    Clear {
        task_id: String,
        format: OutputFormat,
    },
    Add {
        task_id: String,
        reminder_at: String,
        format: OutputFormat,
    },
    Remove {
        task_id: String,
        reminder_id: String,
        format: OutputFormat,
    },
}
