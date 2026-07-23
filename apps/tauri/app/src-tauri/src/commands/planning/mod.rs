#![allow(unused_imports)] // facade re-exports Tauri command entry points

pub(super) use super::{
    enqueue_current_focus_upsert_for_date, enqueue_to_outbox_typed,
    fetch_ordered_active_tasks_by_ids, fetch_ordered_tasks_by_ids, validate_task_ids_active,
    with_immediate_transaction, CurrentFocusWithTasks, FocusScheduleWithTasks, OptionalExt,
    ScheduleBlock,
};
pub(super) use crate::{
    db::{get_conn, get_read_conn},
    error::AppError,
    event_bus,
};
pub(super) use rusqlite::params;
pub(super) use std::collections::HashSet;

pub(crate) mod current_focus;
pub(crate) mod focus_schedule;
pub(crate) mod reorder;

pub(crate) use current_focus::{get_current_focus, get_current_focus_with_conn};
pub use focus_schedule::{
    dismiss_focus_schedule, get_focus_schedule, update_focus_schedule_blocks,
};
pub use reorder::reorder_current_focus_open_tasks;
