//! Task-create workflow surface.
//!
//! Submodules:
//! - [`wire`] — CLI batch-create JSON wire shape ([`TaskCreateInputWire`]).
//! - [`input`] — pure input/result data types ([`TaskCreateInput`],
//!   [`CreateTaskInput`], [`CreateTaskResult`], spawned-successor +
//!   focus-rewire audit records).
//! - [`effects`] — sync-effect accumulators ([`CreateTaskSyncEffects`],
//!   [`TaskTagSyncEffects`]) every downstream surface drives into
//!   outbox enqueue.
//! - [`date_parse`] — flexible `due_date` / `planned_date` normalization.
//! - [`prepared`] — input validation + INSERT-row materialization
//!   ([`PreparedTaskInsert`]) plus shared validators reused by
//!   `task_update` and `task_batch_create`.
//! - [`child_inserts`] — reminder / dependency-edge / tag-edge fan-outs.
//! - [`advice`] — task-intake nudge generator.
//! - [`orchestrator`] — the canonical `create_task` entry point.
//!
//! Every public name the broader workspace consumes is re-exported from
//! this module so external paths (`lorvex_workflow::task_create::*`) stay
//! stable.

pub mod advice;
pub mod child_inserts;
pub mod date_parse;
pub mod effects;
pub mod input;
pub mod orchestrator;
pub mod prepared;
pub mod wire;

pub use advice::build_task_intake_advice;
pub use child_inserts::{insert_dependency_edges, insert_task_reminders, insert_task_tags};
pub use effects::{CreateTaskSyncEffects, TaskTagSyncEffects};
pub use input::{
    CreateTaskFocusRewireAudit, CreateTaskInput, CreateTaskResult, CreateTaskSpawnedSuccessor,
    TaskCreateInput,
};
pub use orchestrator::{create_task, should_store_raw_input};
pub use prepared::{prepare_task_insert, PreparedTaskInsert};
pub use wire::TaskCreateInputWire;

// Crate-internal helpers shared with `task_update` / `task_batch_create`.
pub(crate) use date_parse::normalize_due_date_input_for_conn;
pub(crate) use prepared::{normalize_task_priority, validate_task_ids_exist};
