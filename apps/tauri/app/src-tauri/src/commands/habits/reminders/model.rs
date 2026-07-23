use lorvex_workflow::habit_reminder_ops;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct HabitReminderPolicy {
    pub id: String,
    pub habit_id: String,
    pub habit_name: String,
    pub reminder_time: String,
    pub enabled: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl From<habit_reminder_ops::HabitReminderPolicyRow> for HabitReminderPolicy {
    fn from(row: habit_reminder_ops::HabitReminderPolicyRow) -> Self {
        Self {
            id: row.id,
            habit_id: row.habit_id,
            habit_name: row.habit_name,
            reminder_time: row.reminder_time,
            enabled: row.enabled,
            created_at: row.created_at,
            updated_at: row.updated_at,
        }
    }
}

pub(super) fn policy_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<HabitReminderPolicy> {
    Ok(HabitReminderPolicy {
        id: row.get(0)?,
        habit_id: row.get(1)?,
        habit_name: row.get(2)?,
        reminder_time: row.get(3)?,
        enabled: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DueHabitReminder {
    pub policy: HabitReminderPolicy,
}

#[derive(Debug)]
pub(super) struct HabitReminderCandidate {
    pub(super) policy: HabitReminderPolicy,
    pub(super) frequency_type: String,
    /// `weekly` weekday set, Monday-first (0=Mon … 6=Sun).
    pub(super) weekdays: Vec<i64>,
    /// `times_per_week` completions-per-week target.
    pub(super) per_period_target: i64,
    /// `monthly` reminder day-of-month (1–31), or `None`.
    pub(super) day_of_month: Option<i64>,
    pub(super) target_count: i64,
}
