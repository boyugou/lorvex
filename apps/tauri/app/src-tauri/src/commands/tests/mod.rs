pub(super) use super::*;
pub(super) use chrono::{FixedOffset, TimeZone};
pub(super) use rusqlite::params;
pub(super) use rusqlite::Connection;
pub(super) use serde_json::json;
pub(super) use std::{
    collections::HashSet,
    fs,
    path::PathBuf,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

mod calendar;
mod day_context;
mod diagnostics;
mod lists;
mod overview;
mod planning;
mod provider_links;
mod reviews;
mod scale_smoke;
mod sync;
mod task_commands;
mod task_runtime;

fn unique_test_dir(prefix: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time should move forward")
        .as_nanos();
    std::env::temp_dir().join(format!("{prefix}-{nanos}"))
}

fn setup_sync_test_conn() -> Connection {
    crate::test_support::test_conn()
}

#[test]
fn get_runtime_paths_prefers_db_path_override() {
    let override_path = unique_test_dir("runtime-paths").join("override-db.sqlite");
    crate::db::with_db_path_env_for_test(&override_path.to_string_lossy(), || {
        let runtime_paths = get_runtime_paths().expect("resolve runtime paths");
        assert_eq!(
            runtime_paths.db_path,
            override_path.to_string_lossy(),
            "Expected runtime path command to surface DB_PATH override"
        );
    });
}

/// Regression: the Tauri-side `with_immediate_transaction` wrapper
/// wraps the closure in `catch_unwind` so that a panic unwinds through
/// the transaction boundary without leaving the DB in a half-open
/// state. Without this wrap, the BEGIN IMMEDIATE stays open, the
/// writer mutex guarded by `get_conn()` is poisoned, and every
/// subsequent writer call fails with `transaction within transaction`
/// until the process restarts.
#[test]
fn with_immediate_transaction_panic_rolls_back_and_reraises() {
    use std::panic::{catch_unwind, AssertUnwindSafe};

    let conn = setup_sync_test_conn();

    // Sanity: no transaction open at the start.
    conn.execute_batch("BEGIN IMMEDIATE; COMMIT;")
        .expect("starting connection must be out of any transaction");

    // Panic inside the closure. We wrap the call in `catch_unwind`
    // ourselves so the test process itself does not abort.
    let panic_result = catch_unwind(AssertUnwindSafe(|| {
        let _ = crate::commands::with_immediate_transaction(
            &conn,
            |_inner_conn| -> Result<(), crate::error::AppError> {
                panic!("simulated writer panic");
            },
        );
    }));
    assert!(
        panic_result.is_err(),
        "panic must propagate out of with_immediate_transaction"
    );

    // The rollback must have run — a fresh `BEGIN IMMEDIATE` should
    // succeed. Without the fix this fails because SQLite still thinks
    // a transaction is open.
    conn.execute_batch("BEGIN IMMEDIATE; COMMIT;").expect(
        "connection must be out of any transaction after a panic — \
         indicates ROLLBACK ran correctly under catch_unwind",
    );
}

/// Regression: the non-panic Err path still rolls back correctly.
/// This guards against accidentally breaking the normal-error flow
/// while adding the panic-safe wrap.
#[test]
fn with_immediate_transaction_normal_error_rolls_back() {
    let conn = setup_sync_test_conn();

    let result = crate::commands::with_immediate_transaction(
        &conn,
        |_inner_conn| -> Result<(), crate::error::AppError> {
            Err(crate::error::AppError::Validation("test error".to_string()))
        },
    );
    assert!(result.is_err(), "Err path should propagate");

    // Connection must be out of the transaction.
    conn.execute_batch("BEGIN IMMEDIATE; COMMIT;")
        .expect("connection must be out of any transaction after Err");
}

/// Canonical version literal for test fixture INSERTs — re-exported
/// from `lorvex_store::test_support` so every workspace crate that
/// seeds rows in tests references the same canonical 16-char-hex
/// HLC. The constant's documentation explains why this shape sorts
/// strictly below every realistic post-update HLC and therefore
/// never silently no-ops a test mutation against an LWW gate
///. The 16-char hex suffix satisfies #2973-H5's
/// `Hlc::parse` invariant.
pub(super) use lorvex_store::test_support::TEST_VERSION;

fn insert_task_for_all_tasks_test(conn: &Connection, id: &str, status: &str, created_at: &str) {
    // lift to canonical TaskBuilder.
    let title = format!("task-{id}");
    let completed_at = (status == "completed").then_some(created_at);
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(&title)
        .status(status)
        .version(TEST_VERSION)
        .created_at(created_at)
        .completed_at(completed_at)
        .insert(conn);
}
