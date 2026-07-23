mod normalization;
mod status;

#[cfg(test)]
mod tests;

#[cfg(test)]
pub(crate) use normalization::normalize_due_date_input;
#[cfg(test)]
pub(crate) use normalization::recurrence_base_date_for_conn_at;
#[allow(unused_imports)]
pub(crate) use normalization::{
    normalize_due_date_input_for_conn, normalize_nullable_due_date_patch_for_conn,
    normalize_task_priority,
};
// `normalize_task_status` no longer has any callers
// because every status-bearing arg now uses the typed
// `TaskStatusValue` enum, which serde rejects at parse before the
// normalize gate would have run. The function's tests still live in
// `status.rs::tests` as a stability anchor for the canonical
// `naming::STATUS_*` constants.
pub(crate) use status::{status_filter_to_sql_value, task_status_value_to_str};
