mod chrono_helpers;
mod constants;
mod db_error_sanitize;
pub(crate) mod effects;
mod id_validation;
mod json_helpers;
mod limits;
mod list_rows;
mod models;
mod numeric;
mod path_validation;
mod spotlight_dispatch;
mod task_rows;

pub(crate) use limits::TASK_LIST_RESULT_LIMIT;

pub(crate) use spotlight_dispatch::{
    reindex_list_after_metadata_change, reindex_task_after_mutation,
};

pub(crate) use id_validation::{validate_list_id, validate_uuid_id};
pub(crate) use path_validation::{reject_symlinked_path, reject_traversing_or_relative_path};

#[cfg(test)]
pub(crate) use chrono_helpers::{date_plus_days_ymd_local_for_test, today_ymd_local_for_test};
pub(crate) use chrono_helpers::{parse_rfc3339_utc, sync_timestamp_now};
pub(crate) use constants::{
    ai_changelog_where_clause, ai_changelog_where_clause_for_alias, is_syncable_entity_type,
    FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_CAP_MULTIPLIER, FILESYSTEM_BRIDGE_CURSOR_LOOKBACK_SECONDS,
    LIST_COLS, MAX_CHANGELOG_LIMIT, MAX_ERROR_LOG_LIMIT, MAX_IPC_BATCH_ITEMS,
    MAX_REMINDER_QUERY_WINDOW_SECONDS, MAX_SYNC_EVENTS_LIMIT, MAX_UPCOMING_DAYS,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
    SYNC_GC_RETENTION_DAYS, TASK_COLS,
};
pub(crate) use db_error_sanitize::sanitize_db_error;
pub(crate) use json_helpers::{parse_canonical_json_value, to_json_value};
pub(crate) use list_rows::{fetch_list_by_id, list_from_row, task_list_from_list_row};
pub use models::{
    CurrentFocusSummary, CurrentFocusWithTasks, DeleteListResult, FocusScheduleWithTasks,
    ListWithCount, Overview, ScheduleBlock, Stats, Task, TaskChecklistItem, TaskList, TaskReminder,
};
pub(crate) use numeric::clamp_limit;
pub(crate) use task_rows::{
    fetch_ordered_active_tasks_by_ids, fetch_ordered_tasks_by_ids, fetch_task_by_id,
    fetch_task_row_unenriched, fetch_tasks_by_ids, link_tag_to_task, rows_from_query,
    task_from_row, tasks_from_query, tasks_from_task_rows, validate_task_ids_active,
    with_immediate_transaction, OptionalExt,
};
