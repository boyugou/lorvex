use super::*;
use crate::open_db_in_memory;
use crate::repositories::task::write::{create_task, TaskCreateParams};
use lorvex_domain::TaskId;

fn tid(id: &str) -> TaskId {
    TaskId::from_trusted(id.to_string())
}

fn setup_recurring_task(conn: &Connection) {
    // First create a list since tasks require list_id for recurrence invariants
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) \
         VALUES ('list-1', 'Test List', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')",
        [],
    )
    .unwrap();

    let params = TaskCreateParams::builder(
        "task-r1",
        "Daily Review",
        "open",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-20T00:00:00Z",
    )
    .list_id(Some("list-1"))
    .due_date(Some("2026-03-20"))
    .recurrence(Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#))
    .recurrence_group_id(Some("group-1"))
    .canonical_occurrence_date(Some("2026-03-20"))
    .build()
    .unwrap();
    create_task(conn, &params).unwrap();
}

fn setup_non_recurring_task(conn: &Connection) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
         VALUES ('list-1', 'Test List', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')",
        [],
    )
    .unwrap();

    let params = TaskCreateParams::builder(
        "task-nr1",
        "One-off Task",
        "open",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-25T00:00:00Z",
    )
    .list_id(Some("list-1"))
    .due_date(Some("2026-03-25"))
    .build()
    .unwrap();
    create_task(conn, &params).unwrap();
}

#[test]
fn add_exception_to_recurring_task() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let json = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();

    let parsed: Vec<String> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, vec!["2026-03-25"]);

    // Verify DB
    let (exc, ver): (Option<String>, String) = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM task_recurrence_exceptions WHERE task_id = tasks.id), \
        version FROM tasks WHERE id = 'task-r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(exc.as_deref(), Some(&json[..]));
    assert_eq!(ver, "v1");
}

#[test]
fn add_exception_sorts_and_deduplicates() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-22",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();

    let exc: String = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM task_recurrence_exceptions WHERE task_id = tasks.id) \
        FROM tasks WHERE id = 'task-r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let parsed: Vec<String> = serde_json::from_str(&exc).unwrap();
    assert_eq!(parsed, vec!["2026-03-22", "2026-03-25"]);
}

#[test]
fn add_duplicate_exception_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v2",
        "2026-03-27T12:01:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("Exception already exists"));
}

#[test]
fn add_exception_to_non_recurring_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_non_recurring_task(&conn);

    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-nr1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("not recurring"));
}

#[test]
fn add_exception_before_anchor_date_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-19",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("task canonical occurrence date"));
}

#[test]
fn add_exception_for_nonexistent_task_returns_error() {
    let conn = open_db_in_memory().unwrap();
    let result = add_task_recurrence_exception(
        &conn,
        &tid("nonexistent"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    assert!(matches!(
        result,
        Err(StoreError::NotFound {
            entity: ENTITY_TASK,
            ..
        })
    ));
}

#[test]
fn add_exception_invalid_date_format_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "not-a-date",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("invalid date format"));
}

#[test]
fn add_exception_non_occurrence_returns_error() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
         VALUES ('list-1', 'Test List', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')",
        [],
    )
    .unwrap();

    // Weekly task, only Fridays
    let params = TaskCreateParams::builder(
        "task-weekly",
        "Weekly Friday",
        "open",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-20T00:00:00Z",
    )
    .list_id(Some("list-1"))
    .due_date(Some("2026-03-20")) // a Friday
    .recurrence(Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#))
    .recurrence_group_id(Some("group-weekly"))
    .canonical_occurrence_date(Some("2026-03-20"))
    .build()
    .unwrap();
    create_task(&conn, &params).unwrap();

    // 2026-03-25 is a Wednesday, not a Friday occurrence
    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-weekly"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err
        .to_string()
        .contains("not a valid occurrence of the recurrence pattern"));
}

#[test]
fn remove_exception_succeeds() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-22",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();

    let result = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v3",
        "2026-03-27T12:02:00Z",
    )
    .unwrap();
    let json = result.unwrap();
    let parsed: Vec<String> = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, vec!["2026-03-22"]);
}

#[test]
fn remove_last_exception_sets_null() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();
    let result = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v2",
        "2026-03-27T12:01:00Z",
    )
    .unwrap();
    assert!(result.is_none());

    // Verify DB has NULL
    let exc: Option<String> = conn
        .query_row(
            "SELECT (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
         FROM task_recurrence_exceptions WHERE task_id = tasks.id) \
        FROM tasks WHERE id = 'task-r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(exc.is_none());
}

#[test]
fn remove_nonexistent_exception_returns_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let result = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    let err = result.unwrap_err();
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("not in the exceptions list"));
}

#[test]
fn remove_from_nonexistent_task_returns_error() {
    let conn = open_db_in_memory().unwrap();
    let result = remove_task_recurrence_exception(
        &conn,
        &tid("nonexistent"),
        "2026-03-25",
        "v1",
        "2026-03-27T12:00:00Z",
    );
    assert!(matches!(
        result,
        Err(StoreError::NotFound {
            entity: ENTITY_TASK,
            ..
        })
    ));
}

#[test]
fn empty_version_rejected() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));

    let result = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));

    // Whitespace-only should also be rejected
    let result = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "  ",
        "2026-03-28T00:00:00Z",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("version must not be empty"));
}

// Pre-#4585 the exception list lived as a free-form JSON TEXT
// column, so a manually-corrupted row could ship malformed JSON
// into the parser. The list now normalizes into
// `task_recurrence_exceptions`, with each row a bare
// `YYYY-MM-DD` date string built up by `json_group_array` on
// read — the parser can no longer observe malformed JSON. The
// two `*_rejects_malformed_existing_exceptions_json` regressions
// have been retired: the bug class they pinned is no longer
// reachable at the storage layer.

#[test]
fn remove_exception_rejects_malformed_when_unused() {
    // retained as a smoke entry so the new `add_exception` /
    // `remove_exception` paths still cover the recurrence-rule
    // validation surface against an empty registry. The previous
    // test's malformed-JSON precondition was rewritten as a
    // no-op precondition because the malformed-JSON branch is now
    // structurally unreachable (see comment above).
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);

    let result = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-21",
        "v1",
        "2026-03-27T12:00:00Z",
    );

    let err = result.unwrap_err();
    // Removal of a never-registered exception surfaces as a
    // validation error with the canonical "not in the exceptions
    // list" wording. The previous shape pinned a JSON-parse
    // error, which is no longer reachable.
    assert!(matches!(err, StoreError::Validation(_)));
    assert!(err.to_string().contains("not in the exceptions list"));
}

/// an attempted exception write with
/// a version string that doesn't lex-strictly-exceed the row's
/// current version MUST be rejected with `StaleVersion`.
#[test]
fn add_exception_with_stale_version_returns_stale_version_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 'task-r1'",
        ["9999999999999_0099_peerdevice000"],
    )
    .unwrap();

    let stale_attempt = add_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "0000000000001_0001_localdevice00", // strictly less than peer
        "2026-03-27T12:00:00Z",
    );

    match stale_attempt {
        Err(StoreError::StaleVersion { entity, ref id }) => {
            assert_eq!(entity, ENTITY_TASK);
            assert_eq!(id, "task-r1");
        }
        other => panic!("expected StoreError::StaleVersion, got {other:?}"),
    }

    // Confirm the row's version was NOT regressed.
    let current_version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = 'task-r1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(current_version, "9999999999999_0099_peerdevice000");
}

#[test]
fn remove_exception_with_stale_version_returns_stale_version_error() {
    let conn = open_db_in_memory().unwrap();
    setup_recurring_task(&conn);
    crate::recurrence_exceptions::replace_task_exceptions_from_json(
        &conn,
        "task-r1",
        Some("[\"2026-03-25\"]"),
    )
    .unwrap();
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 'task-r1'",
        ["9999999999999_0099_peerdevice000"],
    )
    .unwrap();

    let stale_attempt = remove_task_recurrence_exception(
        &conn,
        &tid("task-r1"),
        "2026-03-25",
        "0000000000001_0001_localdevice00",
        "2026-03-27T12:00:00Z",
    );

    assert!(matches!(
        stale_attempt,
        Err(StoreError::StaleVersion { entity, .. }) if entity == ENTITY_TASK
    ));
}
