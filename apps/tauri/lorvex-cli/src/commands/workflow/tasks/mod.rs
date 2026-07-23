//! Structured task writes — `task.create` plus the three batch verbs
//! (`task.batch_create`, `task.batch_update`, `task.batch_cancel_in_list`).
//!
//! Each verb owns its own sibling module so the per-verb plumbing
//! (request canonicalization, idempotency lookup, dry-run preview vs
//! commit, per-effect flusher, audit changelog row) stays paged-in
//! together. The verbs share three families of helpers:
//!
//! * [`shared_flush`] — per-category outbox enqueue primitives the
//!   four per-verb flushers compose. Per-verb sequencers keep their
//!   original ordering so HLC version stamps remain identical to the
//!   pre-extraction code.
//! * [`idempotency`] — CLI-side idempotency lookup + record helpers
//!   the create verb consults around its workflow call.
//! * [`dry_run`] — shared `stamp_dry_run_flag` helper the three batch
//!   verbs apply to their preview payloads.

mod batch_cancel;
mod batch_create;
mod batch_update;
mod create;
mod dry_run;
mod idempotency;
mod shared_flush;

pub(crate) use batch_cancel::run_batch_cancel_in_list;
pub(crate) use batch_create::run_batch_create;
pub(crate) use batch_update::run_batch_update;
pub(crate) use create::{run_task_create, TaskCreateInputs};
