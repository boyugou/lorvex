//! Current-focus mutations and view loaders.
//!
//! Submodules:
//! - `context` — `FocusUpdateContext` shared state + `CurrentFocusMutation`
//!   variants + `CURRENT_FOCUS_TASK_IDS_MAX`.
//! - `queries` — view loaders (`load_current_focus_view`,
//!   `load_current_focus_view_for_date`) and task-id existence validator.
//! - `dispatcher` — `apply_current_focus_update` orchestrator + the
//!   `pub(crate)` entry points for set/add/remove.
//! - `clear` — `clear_current_focus_with_conn` + the dedicated
//!   `apply_current_focus_clear` path that captures pre-state inside the tx.
//! - `set` / `add` / `remove` — per-mutation `apply_*` helpers.

mod add;
mod clear;
mod context;
mod dispatcher;
mod queries;
mod remove;
mod set;

pub(crate) use clear::clear_current_focus_with_conn;
pub(crate) use dispatcher::{
    add_to_current_focus_with_conn, remove_from_current_focus_with_conn,
    set_current_focus_with_conn,
};
pub(crate) use queries::{load_current_focus_view, load_current_focus_view_for_date};
