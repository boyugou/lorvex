//! Row, result, and patch shapes returned by the habit write surface.
//!
//! Every struct here is `pub(crate)` and serializable. They mirror the
//! columns of `habits`, `habit_completions`, and
//! `habit_reminder_policies`, plus the cascade-summary payloads used by
//! delete results.

use lorvex_workflow::habit_reminder_ops;
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct HabitRow {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) icon: Option<String>,
    pub(crate) color: Option<String>,
    pub(crate) cue: Option<String>,
    pub(crate) frequency_type: String,
    /// Weekly weekday set, Monday-first (0=Mon … 6=Sun). Empty for every
    /// non-weekly cadence and for weekly-every-day.
    pub(crate) weekdays: Vec<i64>,
    pub(crate) per_period_target: i64,
    pub(crate) day_of_month: Option<i64>,
    pub(crate) target_count: i64,
    pub(crate) archived: bool,
    pub(crate) created_at: String,
    pub(crate) updated_at: String,
    pub(crate) version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct HabitDeleteResult {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) completions_destroyed: usize,
    pub(crate) reminder_policies_destroyed: usize,
    pub(crate) previous: HabitRow,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct HabitCompletionRow {
    pub(crate) habit_id: String,
    pub(crate) completed_date: String,
    pub(crate) value: i64,
    pub(crate) note: Option<String>,
    pub(crate) created_at: String,
    pub(crate) updated_at: String,
    pub(crate) version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct HabitUncompleteResult {
    pub(crate) deleted: bool,
    pub(crate) habit_id: String,
    pub(crate) habit_name: String,
    pub(crate) completed_date: String,
    pub(crate) previous: HabitCompletionRow,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct HabitReminderPolicyDeleteResult {
    pub(crate) deleted: bool,
    pub(crate) id: String,
    pub(crate) before: Option<habit_reminder_ops::HabitReminderPolicyRow>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct HabitUpdateFields<'a> {
    pub(crate) name: Option<&'a str>,
    pub(crate) icon: lorvex_domain::Patch<&'a str>,
    pub(crate) color: lorvex_domain::Patch<&'a str>,
    pub(crate) cue: lorvex_domain::Patch<&'a str>,
    /// Replacement cadence; `Some` replaces the whole cadence atomically,
    /// `None` leaves it alone.
    pub(crate) frequency: Option<lorvex_domain::habits::HabitCadence>,
    pub(crate) target_count: Option<i64>,
    pub(crate) archived: Option<bool>,
}
