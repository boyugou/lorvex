//! Batch task lifecycle commands: complete / cancel / reopen
//! (test-only) / defer / move. Each per-operation file owns its
//! `BatchXResult` payload, the `#[tauri::command]` entry point (where
//! one exists), the `_inner` wrapper that applies post-commit side
//! effects, and the `_with_conn` testable variant that runs the same
//! transactional body against a caller-supplied connection.
//!
//! The `shared` submodule holds the IPC-boundary id validator
//! (`validate_batch_task_ids`). Lifecycle related-entity sync fan-out
//! flows through the shared `LifecycleSyncPlan` flusher rather than
//! per-command spawned-successor helpers.

#[cfg(test)]
pub(super) use super::*;

pub(crate) mod cancel;
pub(crate) mod complete;
pub(crate) mod defer;
pub(crate) mod move_op;
mod reopen;
mod shared;

// Re-expose shared scaffolding to tests under the same `super::super::*`
// glob the pre-split monolith provided so test files don't need to
// know which submodule owns each helper.
#[cfg(test)]
pub(super) use shared::{validate_batch_task_ids, MAX_BATCH_TASK_IDS};

#[cfg(test)]
mod tests;

#[cfg(test)]
pub(crate) use cancel::batch_cancel_tasks_with_conn;
#[cfg(test)]
pub(crate) use complete::batch_complete_tasks_with_conn_inner;
#[cfg(test)]
pub(crate) use defer::batch_defer_tasks_with_conn;
#[cfg(test)]
pub(crate) use move_op::batch_move_tasks_with_conn;
#[cfg(test)]
pub(crate) use reopen::batch_reopen_tasks_with_conn;
