use crate::contract::{TaskStatusFilter, TaskStatusValue};
use lorvex_domain::naming::{STATUS_CANCELLED, STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY};

pub(crate) const fn status_filter_to_sql_value(status: TaskStatusFilter) -> Option<&'static str> {
    match status {
        TaskStatusFilter::Open => Some(STATUS_OPEN),
        TaskStatusFilter::Completed => Some(STATUS_COMPLETED),
        TaskStatusFilter::Cancelled => Some(STATUS_CANCELLED),
        TaskStatusFilter::Someday => Some(STATUS_SOMEDAY),
        TaskStatusFilter::All => None,
    }
}

pub(crate) const fn task_status_value_to_str(status: TaskStatusValue) -> &'static str {
    match status {
        TaskStatusValue::Open => STATUS_OPEN,
        TaskStatusValue::Completed => STATUS_COMPLETED,
        TaskStatusValue::Cancelled => STATUS_CANCELLED,
        TaskStatusValue::Someday => STATUS_SOMEDAY,
    }
}

// `normalize_task_status` was deleted because every
// caller now hands us a typed `TaskStatusValue` (from
// `UpdateTaskArgs.status`, `BatchUpdateTaskPatch.status`, and
// `BatchCancelTasksInListArgs.statuses`). serde rejects invalid
// strings at parse so the legacy normalize gate became unreachable.
// See `server::tests::tasks::read_and_mutation_validation::update_task_args_rejects_status_outside_allowed_enum_at_parse`
// for the replacement contract test.
