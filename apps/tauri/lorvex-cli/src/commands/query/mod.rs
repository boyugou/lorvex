pub(crate) mod calendar;
pub(crate) mod changelog;
pub(crate) mod error_logs;
pub(crate) mod focus;
pub(crate) mod habits;
pub(crate) mod lists;
pub(crate) mod memory;
pub(crate) mod preferences;
pub(crate) mod reminders;
pub(crate) mod reviews;
pub(crate) mod setup_status;
pub(crate) mod sync;
pub(crate) mod tags;
pub(crate) mod tasks;

#[cfg(test)]
mod tests;

pub(crate) use calendar::{
    run_calendar_export_ics, run_calendar_list, run_calendar_search, run_calendar_show,
    run_calendar_today,
};
pub(crate) use changelog::run_changelog;
pub(crate) use error_logs::run_error_logs;
pub(crate) use focus::{run_focus_schedule_get, run_focus_schedule_propose, run_focus_show};
pub(crate) use habits::{run_habit_reminder_policies, run_habit_stats, run_habits};
pub(crate) use lists::{run_list_health, run_list_show, run_lists};
pub(crate) use memory::{run_memory_history, run_memory_list, run_memory_show};
pub(crate) use preferences::{run_preference_get, run_preferences};
pub(crate) use reminders::{run_due_task_reminders, run_upcoming_task_reminders};
pub(crate) use reviews::{run_review_brief, run_review_get, run_review_history, run_review_weekly};
pub(crate) use setup_status::run_setup_status;
pub(crate) use sync::{run_sync_outbox, run_sync_status};
pub(crate) use tags::{run_tag_tasks, run_tags};
pub(crate) use tasks::{
    run_deferred, run_dependency_graph, run_overdue, run_search, run_show, run_tasks, run_today,
    run_upcoming, DependencyGraphCliQuery, TaskListCliQuery,
};
