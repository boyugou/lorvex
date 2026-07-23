// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-sync` — Sync protocol implementation for Lorvex.
//!
//! This crate contains the sync outbox, envelope format, merge pipeline, tombstone
//! system, conflict log, pending inbox, payload canonicalization, and changelog
//! budget/retention logic. Transport adapters (file bridge, future providers) call into
//! this crate for envelope production and consumption.
//!
//! Depends on `lorvex-domain` (pure merge policy, HLC, naming) and `lorvex-store`
//! (DB access for entity snapshots, migrations).

pub mod apply;
pub mod audit_retention;
pub mod canonicalize;
mod composite_edge;
pub mod conflict_log;
pub mod connectivity;
pub mod envelope;
pub mod error;
mod error_log;
pub mod hlc;
pub(crate) mod memory_revision_retention;
pub mod outbox;
pub mod outbox_enqueue;
pub mod payload_build;
pub mod pending_inbox;
pub mod retention_sweep;
pub mod snapshot_import;
pub mod startup_maintenance;
pub mod startup_trash_purge;
pub mod task_payload;
pub mod tombstone;
pub mod version_stamp;

/// Create an in-memory database with all migrations applied.
/// Useful for testing sync modules against the full schema.
///
/// the connection is opened with an outer
/// `BEGIN IMMEDIATE` transaction already in flight so the
/// `apply_envelope` invariant assertion (production callers wrap via
/// `with_immediate_transaction`) holds in unit tests too. SAVEPOINTs
/// nest cleanly inside the outer txn, so apply pipeline savepoints
/// (`apply/edge/dependency.rs`, `apply/aggregate/recurrence.rs`, `apply/tag.rs`,
/// `outbox_enqueue.rs::SAVEPOINT enqueue_payload`) work the same way
/// they do under the production wrapper. The outer txn is never
/// committed — the connection is dropped at end-of-test and the
/// in-memory DB goes with it.
#[cfg(test)]
pub(crate) fn test_db() -> rusqlite::Connection {
    // open via the canonical
    // `lorvex_store::test_support::test_conn` helper so the
    // panic-message wording (`"open in-memory test DB"`) and the
    // connection-open path stay aligned with every other test site
    // in the workspace. The `BEGIN IMMEDIATE` wrapper below is
    // unique to sync apply tests (see M2 above) and
    // therefore stays local.
    let conn = lorvex_store::test_support::test_conn();
    conn.execute_batch("BEGIN IMMEDIATE")
        .expect("test_db: BEGIN IMMEDIATE must succeed on a fresh connection");
    conn
}
