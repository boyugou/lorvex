#![allow(unused_imports)] // facade re-exports Tauri command entry points

pub(crate) mod archive;
pub(crate) mod deferral;
pub(in crate::commands::tasks) mod effects;
pub(crate) mod removal;
pub(crate) mod reopen;

pub(crate) use archive::run_startup_trash_purge;
pub use archive::{
    archive_task, empty_trash, get_archived_tasks, restore_task_from_trash, ArchivedTasksResult,
    EmptyTrashResult,
};
pub use deferral::{defer_task, defer_task_until, reset_task_deferral, restore_task_deferral};
pub(in crate::commands::tasks) use removal::cancel_task_inner;
pub(in crate::commands::tasks) use removal::enqueue_cascaded_task_child_deletes;
pub use removal::{cancel_task, permanent_delete_task, purge_cancelled_tasks};
pub use reopen::reopen_task;
