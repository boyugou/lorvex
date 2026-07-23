//! Shared task write operations — CREATE, UPDATE, and DUPLICATE.
//!
//! Both the MCP server and Tauri app delegate to these functions instead of
//! maintaining their own INSERT/UPDATE SQL. This ensures a single source of
//! truth for task column semantics.
//!
//! Layout (mirrors the e9597d28c / d87080722 / a7429c139 split pattern —
//! thin re-export hub plus per-concern siblings):
//!
//! | File | Owns |
//! |---|---|
//! | `create.rs`    | `TaskCreateParams`, `TaskCreateParamsBuilder`, `create_task`, `INBOX_LIST_ID` |
//! | `update.rs`    | `TaskUpdatePatch`, `apply_task_update` |
//! | `duplicate.rs` | `duplicate_task` |
//! | `delete.rs`    | `hard_delete_task_lww` (LWW-gated single-row physical DELETE) |
//! | `tests.rs`     | unit tests for all three concerns (still consumes `super::*`) |

mod create;
mod delete;
mod duplicate;
mod update;

pub use create::{create_task, TaskCreateParams, TaskCreateParamsBuilder, INBOX_LIST_ID};
pub use delete::hard_delete_task_lww;
pub use duplicate::duplicate_task;
pub use update::{apply_task_update, parse_task_status_for_update, TaskUpdatePatch};

// `tests.rs` uses `super::*` and relies on this re-import to keep
// the existing `fn setup() -> Connection` signature working without
// reaching for a `rusqlite::Connection` import in every test.
#[cfg(test)]
use rusqlite::Connection;

#[cfg(test)]
mod tests;
