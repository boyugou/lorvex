//! Focus schedule CRUD, proposal, and apply-to-current-focus mirror.
//!
//! Submodules:
//! - `types` — `FocusScheduleBlockInput` JSON input shape.
//! - `queries` — view loaders + calendar-AI-access-mode reader.
//! - `parse` — `parse_focus_schedule_blocks_json` validator.
//! - `propose` — `propose_focus_schedule_with_conn` thin entry.
//! - `save` — `save_focus_schedule_with_conn` plus its colocated helpers
//!   (apply-to-current-focus mirror, task-id filter, dashboard layout
//!   bootstrap).

mod parse;
mod propose;
mod queries;
mod save;
mod types;

pub(crate) use propose::propose_focus_schedule_with_conn;
pub(crate) use queries::get_focus_schedule_with_conn;
pub(crate) use save::save_focus_schedule_with_conn;
