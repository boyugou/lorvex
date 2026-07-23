use super::jump_list_io_enabled;
use super::query::query_task_row;
use crate::test_support::test_conn;

/// parity with the macOS
/// `spotlight_io_is_disabled_in_unit_tests` guard. The Jump
/// List path opens a COM apartment and writes through to the
/// shell; cargo test must never trigger that.
#[test]
fn jump_list_io_is_disabled_in_unit_tests() {
    assert!(
        !jump_list_io_enabled(),
        "unit tests must not invoke the Windows Jump List directly"
    );
}

/// mirror the macOS regression that completed
/// tasks must not appear in the Jump List discoverability
/// surface. Pre-fix the `query_task_row` helper was unused +
/// untested on Windows even though the production rebuild
/// path enforces the same `WHERE status IN ('open', 'someday')`
/// invariant — a future schema drift (e.g. introducing a new
/// status value) would silently ship a discoverability
/// regression on Windows long before macOS noticed.
#[test]
fn query_task_row_returns_none_for_completed_task() {
    let conn = test_conn();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Done")
        .status("completed")
        .version("v1")
        .created_at("2026-03-29T00:00:00Z")
        .insert(&conn);

    let row = query_task_row(&conn, "task-1").expect("completed task lookup should not error");
    assert!(row.is_none(), "completed task should not be jump-listable");
}

#[test]
fn query_task_row_surfaces_database_errors() {
    let conn = rusqlite::Connection::open_in_memory().expect("open broken db");

    let error =
        query_task_row(&conn, "task-1").expect_err("missing schema should surface query failure");
    let message = error.to_string();
    assert!(
        message.contains("no such table") || message.contains("tasks"),
        "unexpected error: {message}"
    );
}
