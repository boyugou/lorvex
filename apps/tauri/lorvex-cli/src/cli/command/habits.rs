//! Habit CRUD, completion, stats, and reminder-policy arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum HabitsCommand {
    List {
        format: OutputFormat,
    },
    Complete {
        habit_id: String,
        date: Option<String>,
        note: Option<String>,
        format: OutputFormat,
    },
    BatchComplete {
        habit_ids: Vec<String>,
        date: Option<String>,
        format: OutputFormat,
    },
    Create {
        name: String,
        icon: Option<String>,
        color: Option<String>,
        cue: Option<String>,
        frequency_type: Option<String>,
        weekdays: Vec<String>,
        per_period_target: Option<i64>,
        day_of_month: Option<i64>,
        target_count: Option<i64>,
        format: OutputFormat,
    },
    Update {
        habit_id: String,
        name: Option<String>,
        icon: lorvex_domain::Patch<String>,
        color: lorvex_domain::Patch<String>,
        cue: lorvex_domain::Patch<String>,
        // Cadence replacement is atomic — providing `frequency_type` (with
        // any detail) replaces the whole cadence; `None` leaves it alone.
        frequency_type: Option<String>,
        weekdays: Vec<String>,
        per_period_target: Option<i64>,
        day_of_month: Option<i64>,
        target_count: Option<i64>,
        archived: Option<bool>,
        format: OutputFormat,
    },
    Delete {
        habit_id: String,
        format: OutputFormat,
    },
    Uncomplete {
        habit_id: String,
        date: Option<String>,
        format: OutputFormat,
    },
    Stats {
        habit_id: String,
        days: Option<i64>,
        format: OutputFormat,
    },
    ReminderList {
        format: OutputFormat,
    },
    ReminderUpsert {
        policy_id: Option<String>,
        habit_id: String,
        reminder_time: String,
        enabled: bool,
        format: OutputFormat,
    },
    ReminderDelete {
        policy_id: String,
        format: OutputFormat,
    },
}
