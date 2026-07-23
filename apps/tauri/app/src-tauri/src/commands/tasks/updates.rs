//! Task update IPC adapter — the public Tauri commands that mutate a
//! single task row. Each submodule owns a single mutation:
//!
//!   * `command` — the generic `update_task` patch flow (routes through
//!     `lorvex_workflow::task_update::update_task` and mints the
//!     snapshot-based undo token).
//!   * `body` — append-only `body` mutation helper.
//!   * `flush` — Tauri-side `TaskUpdateFlushBackend` adapter consumed
//!     by `command`.
//!
//! Re-exports below pin the public IPC entry points; helper-only
//! modules stay scoped to the subtree that owns them.

#![allow(unused_imports)] // facade re-exports Tauri command entry points

use rusqlite::{params, Connection};

use super::undo::{build_update_undo_token, compute_undo_expiry, TaskWithUndo};
use super::{
    enqueue_task_upsert, fetch_task_by_id, finalize_task_mutation, get_conn, sync_timestamp_now,
    with_immediate_transaction, AppError, Task,
};

pub(crate) mod body;
pub(crate) mod command;
mod flush;

#[cfg(test)]
mod tests;

#[cfg(test)]
use body::append_to_task_body_with_conn;
pub use command::update_task;
pub(crate) use command::{update_task_inner_with_conn, update_task_internal};
