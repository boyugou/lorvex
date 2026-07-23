//! Shared fixtures and helpers for lifecycle tests.
//!
//! Centralized here (rather than duplicated across primitives + transition
//! test modules) so a schema or seed change touches one place. The two
//! categories are:
//!
//! 1. **Direct seeders** ([`insert_task`], [`insert_recurring_task`],
//!    [`seed_status_task`]) — write a single row via raw SQL or
//!    [`lorvex_store::test_support::TaskBuilder`] for primitive-level tests
//!    that don't need transition machinery.
//!
//! 2. **Transition runners** ([`run_completion_in_tx`],
//!    [`run_cancel_in_tx`], [`run_reopen_in_tx`]) — wrap the orchestrator
//!    entry points in [`with_immediate_transaction`] so the
//!    `debug_assert!(!conn.is_autocommit())` guard inside each transition
//!    is honored just like the production callers (MCP `with_conn`,
//!    Tauri command writer) do.

use rusqlite::{params, Connection};

use super::super::*;
use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::TaskStatus;
pub(super) use lorvex_store::test_support::test_conn;
use lorvex_store::transaction::with_immediate_transaction;
use lorvex_store::StoreError;

/// Convenience converter for tests: wrap a `&str` literal as a typed
/// `TaskId` without going through the trust-boundary `parse(...)` path.
/// Tests pass synthetic `"t1"` fixture ids that don't have UUID shape,
/// so `parse` would reject them; `from_trusted` is the right shape for
/// test fixtures.
pub(super) fn tid(s: &str) -> lorvex_domain::TaskId {
    lorvex_domain::TaskId::from_trusted(s.to_string())
}

/// HLC stamp used by primitive-level tests that don't care which
/// version string flows through the writer, only that it lex-compares
/// strictly greater than the seed value
/// (`'0000000000000_0000_0000000000000000'`) every direct seeder uses.
pub(super) const TEST_VERSION: &str = "1711234567890_0001_a1b2c3d4a1b2c3d4";

/// Seed a minimal `tasks` row with raw SQL — body, list, recurrence are
/// all NULL. Used by primitive tests that exercise a single mutator
/// (status, reminders, dependencies, body) without the surrounding
/// orchestration.
pub(super) fn insert_task(conn: &Connection, id: &str, status: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at)
         VALUES (?1, ?1, ?2, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        params![id, status],
    ).unwrap();
}

/// Seed a recurring `tasks` row carrying canonical_occurrence_date,
/// recurrence (`{"FREQ":"DAILY"}`), and recurrence_group_id. Used by the
/// recurrence-aware primitive tests.
pub(super) fn insert_recurring_task(
    conn: &Connection,
    id: &str,
    status: &str,
    group_id: &str,
    due: &str,
) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, recurrence,
            recurrence_group_id, version, created_at, updated_at)
         VALUES (?1, ?1, ?2, ?3, ?3, '{\"FREQ\":\"DAILY\"}', ?4,
            '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        params![id, status, due, group_id],
    )
    .unwrap();
}

/// Seed a task via `TaskBuilder` with a fixed `created_at` so the
/// transition-level tests get predictable HLC ordering relative to the
/// `now` strings they pass to the orchestrator.
pub(super) fn seed_status_task(conn: &Connection, task_id: &str, status: &str) {
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title(task_id)
        .status(status)
        .created_at("2026-04-20T00:00:00Z")
        .insert(conn);
}

// the lifecycle entry points debug_assert that they
// run inside a transaction. Tests therefore wrap each call through
// these tiny helpers so the same transactional discipline production
// callers (MCP `with_conn`, Tauri command writer) provide is honored
// in the test harness too. Keeping the helpers in one place avoids
// rewriting every assertion when the discipline is widened later.
pub(super) fn run_completion_in_tx(
    conn: &Connection,
    task_id: &str,
    now: &str,
    reminder_version: &str,
) -> Result<CompletionLifecycleTransitionResult, StoreError> {
    let task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    with_immediate_transaction(conn, |c| {
        apply_completion_transition(c, &task_id, now, reminder_version)
    })
}

pub(super) fn run_cancel_in_tx(
    conn: &Connection,
    task_id: &str,
    now: &str,
    reminder_version: &str,
    cancel_series: bool,
) -> Result<CancelLifecycleTransitionResult, StoreError> {
    let task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let series_clear_version =
        cancel_series.then(|| test_series_clear_version_after(reminder_version));
    with_immediate_transaction(conn, |c| {
        apply_cancel_transition(
            c,
            &task_id,
            now,
            reminder_version,
            cancel_series,
            series_clear_version.as_deref(),
        )
    })
}

fn test_series_clear_version_after(reminder_version: &str) -> String {
    if let Ok(prior) = Hlc::parse(reminder_version) {
        if let Ok(next) = Hlc::new(
            prior.physical_ms(),
            prior.counter().saturating_add(1),
            prior.device_suffix(),
        ) {
            return next.to_string();
        }
    }

    "9999999999999_0000_ffffffffffffffff".to_string()
}

pub(super) fn run_reopen_in_tx(
    conn: &Connection,
    task_id: &str,
    old_status: &str,
    now: &str,
    reminder_version: &str,
) -> Result<ReopenLifecycleTransitionResult, StoreError> {
    let task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let old_status = TaskStatus::parse(old_status).expect("test old_status must be canonical");
    with_immediate_transaction(conn, |c| {
        apply_reopen_transition(c, &task_id, old_status, now, reminder_version)
    })
}
