use super::*;

// this test exercises a hand-rolled `tasks` schema (not
// the real migration suite) and a literal `UPDATE … SET status …`
// path that does NOT pass through the apply-pipeline LWW gate. The
// seed version below is therefore documentation: it reads as the
// canonical [`TEST_VERSION`] (digit-prefixed, lex-sorts below every
// realistic post-update HLC) so a future migration that wires this
// schema into the LWW pipeline will not silently no-op the assertion.
//
// Stays raw: the hand-rolled schema only carries a subset of the
// real `tasks` columns, so `TaskBuilder` (which targets the canonical
// schema) cannot be used here without inserting NULLs into columns
// the test schema doesn't define.

#[test]
fn mark_task_cancelled_marks_status_cancelled_without_removing_row() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        &format!(
            "CREATE TABLE tasks (
                id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                version TEXT NOT NULL DEFAULT '{TEST_VERSION}',
                updated_at TEXT NOT NULL,
                completed_at TEXT,
                last_deferred_at TEXT
            )"
        ),
        [],
    )
    .expect("create tasks");
    conn.execute(
        "INSERT INTO tasks (id, status, version, updated_at, completed_at, last_deferred_at)
         VALUES ('task-1', 'open', ?1, '2026-03-02T00:00:00Z', NULL, NULL)",
        params![TEST_VERSION],
    )
    .expect("insert task");

    let affected = conn.execute(
        "UPDATE tasks SET status = 'cancelled', completed_at = NULL, last_deferred_at = NULL, updated_at = ?2 WHERE id = ?1",
        rusqlite::params!["task-1", "2026-03-02T12:00:00Z"],
    ).expect("soft delete task");
    assert_eq!(affected, 1);

    let (status, updated_at): (String, String) = conn
        .query_row(
            "SELECT status, updated_at FROM tasks WHERE id = 'task-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read task");
    assert_eq!(status, "cancelled");
    assert_eq!(updated_at, "2026-03-02T12:00:00Z");

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = 'task-1'",
            [],
            |row| row.get(0),
        )
        .expect("count task rows");
    assert_eq!(count, 1);
}

#[test]
fn mark_task_cancelled_clears_completed_and_deferred_timestamps() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        &format!(
            "CREATE TABLE tasks (
                id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                version TEXT NOT NULL DEFAULT '{TEST_VERSION}',
                updated_at TEXT NOT NULL,
                completed_at TEXT,
                last_deferred_at TEXT
            )"
        ),
        [],
    )
    .expect("create tasks");
    conn.execute(
        "INSERT INTO tasks (id, status, version, updated_at, completed_at, last_deferred_at)
         VALUES ('task-1', 'completed', ?1, '2026-03-02T00:00:00Z', '2026-03-01T12:00:00Z', '2026-03-01T10:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert task");

    let affected = conn.execute(
        "UPDATE tasks SET status = 'cancelled', completed_at = NULL, last_deferred_at = NULL, updated_at = ?2 WHERE id = ?1",
        rusqlite::params!["task-1", "2026-03-02T12:00:00Z"],
    ).expect("soft delete task");
    assert_eq!(affected, 1);

    let (status, updated_at, completed_at, last_deferred_at): (
        String,
        String,
        Option<String>,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT status, updated_at, completed_at, last_deferred_at FROM tasks WHERE id = 'task-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read task");
    assert_eq!(status, "cancelled");
    assert_eq!(updated_at, "2026-03-02T12:00:00Z");
    assert_eq!(completed_at, None);
    assert_eq!(last_deferred_at, None);
}

#[test]
fn hard_delete_task_lww_removes_task_row() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        &format!(
            "CREATE TABLE tasks (
                id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                version TEXT NOT NULL DEFAULT '{TEST_VERSION}',
                updated_at TEXT NOT NULL
            )"
        ),
        [],
    )
    .expect("create tasks");
    conn.execute(
        "INSERT INTO tasks (id, status, version, updated_at) VALUES ('task-1', 'open', ?1, '2026-03-02T00:00:00Z')",
        params![TEST_VERSION],
    )
    .expect("insert task");

    let affected = lorvex_store::repositories::task::write::hard_delete_task_lww(
        &conn,
        &lorvex_domain::TaskId::from_trusted("task-1".to_string()),
        "9999999999999_9999_ffffffffffffffff",
    )
    .expect("LWW hard delete task");
    assert_eq!(affected, 1);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = 'task-1'",
            [],
            |row| row.get(0),
        )
        .expect("count task rows");
    assert_eq!(count, 0);
}
