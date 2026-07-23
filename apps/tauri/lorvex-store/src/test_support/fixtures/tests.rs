use super::*;
use crate::test_support::test_conn;

#[test]
fn task_builder_inserts_minimal_row() {
    let conn = test_conn();
    TaskBuilder::new("task-1").insert(&conn);
    let title: String = conn
        .query_row("SELECT title FROM tasks WHERE id = 'task-1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(title, "Seed Task");
}

#[test]
fn task_builder_overrides_propagate() {
    let conn = test_conn();
    TaskBuilder::new("task-2")
        .title("Custom title")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .completed_at(Some("2026-04-01T00:00:00.000Z"))
        .insert(&conn);
    let (title, status, completed_at): (String, String, Option<String>) = conn
        .query_row(
            "SELECT title, status, completed_at FROM tasks WHERE id = 'task-2'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(title, "Custom title");
    assert_eq!(status, "completed");
    assert_eq!(completed_at.as_deref(), Some("2026-04-01T00:00:00.000Z"));
}

#[test]
fn task_builder_archived_at_persists() {
    let conn = test_conn();
    TaskBuilder::new("task-3")
        .archived_at(Some("2026-04-15T00:00:00.000Z"))
        .insert(&conn);
    let archived_at: Option<String> = conn
        .query_row(
            "SELECT archived_at FROM tasks WHERE id = 'task-3'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(archived_at.as_deref(), Some("2026-04-15T00:00:00.000Z"));
}

#[test]
fn list_builder_inserts_minimal_row() {
    let conn = test_conn();
    ListBuilder::new("list-personal")
        .name("Personal")
        .insert(&conn);
    let name: String = conn
        .query_row(
            "SELECT name FROM lists WHERE id = 'list-personal'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(name, "Personal");
}

#[test]
fn list_builder_or_ignore_no_op_against_seeded_inbox() {
    let conn = test_conn();
    // The migration baseline always seeds the 'inbox' list; a fresh
    // re-seed with `or_ignore(true)` must NOT fail.
    ListBuilder::new("inbox")
        .name("Different Name")
        .or_ignore(true)
        .insert(&conn);
    let name: String = conn
        .query_row("SELECT name FROM lists WHERE id = 'inbox'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(name, "Inbox", "seeded inbox row must survive the OR IGNORE");
}

#[test]
fn list_builder_optional_columns_persist() {
    let conn = test_conn();
    ListBuilder::new("list-color")
        .name("Tinted")
        .color(Some("#abcdef"))
        .icon(Some("star"))
        .description(Some("desc"))
        .insert(&conn);
    let (color, icon, description): (Option<String>, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT color, icon, description FROM lists WHERE id = 'list-color'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .unwrap();
    assert_eq!(color.as_deref(), Some("#abcdef"));
    assert_eq!(icon.as_deref(), Some("star"));
    assert_eq!(description.as_deref(), Some("desc"));
}
