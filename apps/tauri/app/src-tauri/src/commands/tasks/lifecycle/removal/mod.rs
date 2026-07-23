//! Task removal lifecycle paths: cancel (soft-stop), permanent
//! delete (hard-delete from Trash), and the bulk `purge_cancelled`
//! sweep. Plus the cascade-delete bookkeeping (`cleanup_plan_refs_*`,
//! `enqueue_cascaded_task_child_deletes`) shared with the
//! sibling archive path so every removal site produces the same
//! peer-visible tombstone shape.
//!
//! #3303 P1 split — the previous 665-LOC `removal.rs` file mixed
//! all three command paths and the cascade helpers into a single
//! module. Each command now lives in its own sibling, and the
//! cascade helpers — used by both this module and `lifecycle/archive`
//! — sit in a dedicated `cascade` module that re-exports up to the
//! `lifecycle` parent so the existing `super::super::removal::*`
//! callsites inside `archive_commands.rs` keep compiling.

pub(crate) mod cancel;
mod cascade;
pub(crate) mod permanent;
pub(crate) mod purge;

#[cfg(test)]
mod tests;

pub use cancel::cancel_task;
pub(in crate::commands::tasks) use cancel::cancel_task_inner;
#[cfg(test)]
pub(crate) use cancel::cancel_task_with_conn;

pub use permanent::permanent_delete_task;
#[cfg(test)]
pub(crate) use permanent::permanent_delete_task_with_conn;

pub use purge::purge_cancelled_tasks;
#[cfg(test)]
pub(crate) use purge::purge_cancelled_tasks_with_conn;

pub(in crate::commands::tasks::lifecycle) use cascade::cleanup_plan_refs_after_removal;
pub(in crate::commands::tasks) use cascade::enqueue_cascaded_task_child_deletes;
