//! macOS Core Spotlight indexing for Lorvex tasks.
//!
//! #3303 P2 split — the previous 668-LOC `macos.rs` file mixed three
//! concerns (per-task FFI commands, bulk reindex orchestration with
//! its in-flight coordination state, and DB lookups). Each concern
//! now lives in its own sibling so the Spotlight read/index/delete
//! plumbing can be reasoned about independently:
//!
//!   * `attributes` — `CSSearchableItemAttributeSet` /
//!     `CSSearchableItem` builders + the deep-link URL helper +
//!     the shared `log_error_block` completion-block factory.
//!   * `query` — `read_spotlight_rows` / `query_spotlight_task_row`
//!     adapters routed through the parent module's
//!     `queries::read_indexable_rows` projection.
//!   * `per_task` — `index_task` / `remove_task` / `remove_all_tasks`
//!     single-task FFI entry points.
//!   * `reindex` — `reindex_tasks_for_list`, `reindex_tasks_by_ids`,
//!     and the two-phase domain-clear → index-batch
//!     `reindex_all_tasks` driver gated by the `REINDEX_*` state
//!     declared in this `mod.rs`.
//!
//! The reindex coordination state (`REINDEX_IN_FLIGHT`,
//! `REINDEX_RERUN_REQUESTED`, `REINDEX_STATE_LOCK`) and the test-only
//! IO gate (`spotlight_io_enabled`) live here so they're a single
//! lookup away from every caller, regardless of which sibling owns
//! the actual OS dispatch.

use std::sync::atomic::AtomicBool;
use std::sync::Mutex;

use super::SPOTLIGHT_DOMAIN;

mod attributes;
mod per_task;
mod query;
mod reindex;

#[cfg(test)]
mod tests;

pub use per_task::{remove_all_tasks, remove_task};
pub use reindex::{reindex_all_tasks, reindex_tasks_by_ids, reindex_tasks_for_list};

/// serialize concurrent `reindex_all_tasks`
/// invocations and request a follow-up rerun if a second call
/// arrives while the first is in flight.
///
/// The CoreSpotlight reindex is two nested async OS calls — a
/// `delete-by-domain` followed (inside the completion block) by a
/// `index-batch`. Without serialization, two rapid triggers (e.g.
/// manual sync + list refresh, or two list renames) could fire both
/// completion blocks concurrently: Block-A's clear could land after
/// Block-B's clear+insert had already populated the index, wiping
/// every task that was inserted between Block-B's clear and
/// Block-A's clear. The user would then open Spotlight and find
/// nothing until the next reindex_all_tasks run, which may never
/// arrive on a quiet day.
///
/// `REINDEX_IN_FLIGHT` is the gate — held from the call site
/// through the OUTER delete and INNER insert completion. While
/// it is true, the second caller flips
/// `REINDEX_RERUN_REQUESTED` and returns; when the first reindex
/// completes, the cleanup block re-checks the rerun flag and
/// re-enters the path with fresh data.
static REINDEX_IN_FLIGHT: AtomicBool = AtomicBool::new(false);
static REINDEX_RERUN_REQUESTED: AtomicBool = AtomicBool::new(false);
/// Coordinates the in-flight + rerun bits with a single
/// atomic-CAS-protected critical section so two callers can't
/// each conclude they are the "first" and race the OS calls.
static REINDEX_STATE_LOCK: Mutex<()> = Mutex::new(());

/// / test-hardening: Core Spotlight can
/// throw Objective-C exceptions under the unit-test host, which
/// aborts the whole Rust test binary before any assertion can run.
/// Keep query + shaping helpers testable, but short-circuit the
/// real OS indexing side effects in `cargo test`.
#[inline]
const fn spotlight_io_enabled() -> bool {
    !cfg!(test)
}

/// Shared row shape for the projection feeding every Spotlight
/// indexer. Lives at the parent level so `attributes` can build
/// items from rows produced by `query`.
#[derive(Debug, Clone, PartialEq, Eq)]
struct TaskRow {
    id: String,
    title: String,
    body: Option<String>,
    list_name: Option<String>,
    due_date: Option<String>,
}
