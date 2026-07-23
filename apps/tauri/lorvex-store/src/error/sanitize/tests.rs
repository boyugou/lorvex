use super::*;

#[test]
fn unique_constraint() {
    assert_eq!(
        sanitize_sqlite_error("UNIQUE constraint failed: tasks.id"),
        Some("A task with this identifier already exists".to_string())
    );
}

#[test]
fn foreign_key_constraint() {
    assert!(sanitize_sqlite_error("FOREIGN KEY constraint failed").is_some());
}

#[test]
fn not_null_constraint() {
    assert_eq!(
        sanitize_sqlite_error("NOT NULL constraint failed: tasks.title"),
        Some("Required field 'title' must not be null".to_string())
    );
}

#[test]
fn not_null_constraint_no_dot() {
    // If the error message has no dot separator, fall through to the
    // generic message rather than leaking a bare table name.
    assert_eq!(
        sanitize_sqlite_error("NOT NULL constraint failed: tasks"),
        Some("A required field is missing".to_string())
    );
}

#[test]
fn check_constraint() {
    assert!(sanitize_sqlite_error("CHECK constraint failed: valid_status").is_some());
}

#[test]
fn database_locked() {
    assert!(sanitize_sqlite_error("database is locked").is_some());
}

#[test]
fn unknown_returns_none() {
    assert_eq!(sanitize_sqlite_error("something unexpected"), None);
}
