use super::task::TaskStatusFilter;
use super::{
    CALENDAR_EVENTS_LIMIT_DEFAULT, DEFERRED_TASKS_LIMIT_DEFAULT,
    DEPENDENCY_GRAPH_LIMIT_EDGES_DEFAULT, DEPENDENCY_GRAPH_LIMIT_NODES_DEFAULT,
    DUE_REMINDERS_LIMIT_DEFAULT, GET_LIST_LIMIT_DEFAULT, GET_TODAYS_LIMIT_PER_BUCKET_DEFAULT,
    GET_UPCOMING_DAYS_DEFAULT, GET_UPCOMING_LIMIT_DEFAULT, LIST_HEALTH_LIMIT_DEFAULT,
    LIST_TASKS_LIMIT_DEFAULT, SEARCH_TASKS_LIMIT_DEFAULT, TASKS_BY_TAG_LIMIT_DEFAULT,
    UPCOMING_REMINDERS_HOURS_DEFAULT, UPCOMING_REMINDERS_LIMIT_DEFAULT,
    WEEKLY_BRIEF_COMPLETED_DEFAULT, WEEKLY_BRIEF_DEFERRED_DEFAULT, WEEKLY_BRIEF_SOMEDAY_DEFAULT,
    WEEKLY_BRIEF_STALLED_DEFAULT,
};

pub(crate) const fn default_status_open() -> TaskStatusFilter {
    TaskStatusFilter::Open
}

pub(crate) const fn default_status_all() -> TaskStatusFilter {
    TaskStatusFilter::All
}

pub(crate) const fn default_list_tasks_limit() -> u32 {
    LIST_TASKS_LIMIT_DEFAULT
}

pub(crate) const fn default_todays_limit_per_bucket() -> u32 {
    GET_TODAYS_LIMIT_PER_BUCKET_DEFAULT
}

pub(crate) const fn default_upcoming_days() -> u32 {
    GET_UPCOMING_DAYS_DEFAULT
}

pub(crate) const fn default_upcoming_limit() -> u32 {
    GET_UPCOMING_LIMIT_DEFAULT
}

pub(crate) const fn default_search_tasks_limit() -> u32 {
    SEARCH_TASKS_LIMIT_DEFAULT
}

pub(crate) const fn default_deferred_tasks_limit() -> u32 {
    DEFERRED_TASKS_LIMIT_DEFAULT
}

pub(crate) const fn default_get_list_limit() -> u32 {
    GET_LIST_LIMIT_DEFAULT
}

pub(crate) const fn default_list_health_limit() -> u32 {
    LIST_HEALTH_LIMIT_DEFAULT
}

pub(crate) const fn default_weekly_completed_limit() -> u32 {
    WEEKLY_BRIEF_COMPLETED_DEFAULT
}

pub(crate) const fn default_weekly_stalled_limit() -> u32 {
    WEEKLY_BRIEF_STALLED_DEFAULT
}

pub(crate) const fn default_weekly_deferred_limit() -> u32 {
    WEEKLY_BRIEF_DEFERRED_DEFAULT
}

pub(crate) const fn default_weekly_someday_limit() -> u32 {
    WEEKLY_BRIEF_SOMEDAY_DEFAULT
}

pub(crate) const fn default_tasks_by_tag_limit() -> u32 {
    TASKS_BY_TAG_LIMIT_DEFAULT
}

pub(crate) const fn default_calendar_events_limit() -> u32 {
    CALENDAR_EVENTS_LIMIT_DEFAULT
}

pub(crate) const fn default_include_provider() -> bool {
    true
}

pub(crate) const fn default_due_reminders_limit() -> u32 {
    DUE_REMINDERS_LIMIT_DEFAULT
}

pub(crate) const fn default_upcoming_reminders_hours() -> u32 {
    UPCOMING_REMINDERS_HOURS_DEFAULT
}

pub(crate) const fn default_upcoming_reminders_limit() -> u32 {
    UPCOMING_REMINDERS_LIMIT_DEFAULT
}

pub(crate) const fn default_dependency_graph_limit_nodes() -> u32 {
    DEPENDENCY_GRAPH_LIMIT_NODES_DEFAULT
}

pub(crate) const fn default_dependency_graph_limit_edges() -> u32 {
    DEPENDENCY_GRAPH_LIMIT_EDGES_DEFAULT
}
