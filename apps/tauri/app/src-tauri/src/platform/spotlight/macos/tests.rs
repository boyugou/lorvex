use super::query::query_spotlight_task_row;
use super::spotlight_io_enabled;
use crate::test_support::test_conn;

#[test]
fn spotlight_io_is_disabled_in_unit_tests() {
    assert!(
        !spotlight_io_enabled(),
        "unit tests must not invoke Core Spotlight directly"
    );
}

#[test]
fn query_spotlight_task_row_returns_none_for_missing_or_non_indexable_task() {
    let conn = test_conn();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Done")
        .status("completed")
        .version("v1")
        .created_at("2026-03-29T00:00:00Z")
        .insert(&conn);

    let row =
        query_spotlight_task_row(&conn, "task-1").expect("completed task lookup should not error");
    assert!(row.is_none(), "completed task should not be indexable");
}

#[test]
fn query_spotlight_task_row_surfaces_database_errors() {
    let conn = rusqlite::Connection::open_in_memory().expect("open broken db");

    let error = query_spotlight_task_row(&conn, "task-1")
        .expect_err("missing schema should surface query failure");
    let message = error.to_string();
    assert!(
        message.contains("no such table") || message.contains("tasks"),
        "unexpected error: {message}"
    );
}
