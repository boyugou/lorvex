#![allow(unused_imports)] // facade re-exports Tauri command entry points

pub(crate) mod delivery;
pub(crate) mod due;
mod model;
pub(crate) mod policy_commands;
mod sync;
#[cfg(test)]
mod tests;

pub use delivery::mark_habit_reminder_fired;
pub use due::get_due_habit_reminders;
pub use model::{DueHabitReminder, HabitReminderPolicy};
pub use policy_commands::{
    delete_habit_reminder_policy, get_habit_reminder_policies, upsert_habit_reminder_policy,
};

#[cfg(test)]
use delivery::mark_habit_reminder_fired_with_conn;
#[cfg(test)]
use due::{
    due_habit_reminder_clock_at, get_due_habit_reminders_with_conn_at,
    reminder_was_sent_on_local_day,
};
#[cfg(test)]
use policy_commands::upsert_habit_reminder_policy_with_conn;
