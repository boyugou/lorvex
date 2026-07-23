use super::*;

#[test]
#[serial_test::serial(hlc)]
fn unique_constraint_mapped() {
    let msg = to_error_message("UNIQUE constraint failed: tasks.id");
    assert_eq!(msg, "Error: A task with this identifier already exists");
}

#[test]
#[serial_test::serial(hlc)]
fn foreign_key_constraint_mapped() {
    let msg = to_error_message("FOREIGN KEY constraint failed");
    assert_eq!(
        msg,
        "Error: Operation failed: a referenced record does not exist or would be orphaned"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn not_null_constraint_mapped() {
    let msg = to_error_message("NOT NULL constraint failed: tasks.title");
    assert_eq!(msg, "Error: Required field \'title\' must not be null");
}

#[test]
#[serial_test::serial(hlc)]
fn check_constraint_mapped() {
    let msg = to_error_message("CHECK constraint failed: valid_status");
    assert_eq!(msg, "Error: A value failed a validation check");
}

#[test]
#[serial_test::serial(hlc)]
fn database_locked_mapped() {
    let msg = to_error_message("database is locked");
    assert_eq!(
        msg,
        "Error: The database is temporarily busy. Please retry the operation."
    );
}

#[test]
#[serial_test::serial(hlc)]
fn unknown_error_preserves_sanitized_detail() {
    let msg = to_error_message("something unexpected happened");
    assert!(msg.starts_with("Error: an internal error occurred."));
    assert!(
        msg.contains("something unexpected happened"),
        "unmapped error must preserve the detail for retry/adapt decisions: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn unknown_error_redacts_secrets_before_returning() {
    let msg = to_error_message("HTTP fetch failed: Authorization: Bearer eyJhbGciOi.deadbeef");
    assert!(msg.starts_with("Error: an internal error occurred."));
    assert!(
        !msg.contains("eyJhbGciOi.deadbeef"),
        "bearer token must be redacted: {msg}"
    );
    assert!(msg.contains("[REDACTED]"));
}

#[test]
#[serial_test::serial(hlc)]
fn unknown_error_truncates_to_avoid_giant_responses() {
    let long = "x".repeat(400);
    let msg = to_error_message(long);
    // Generic prefix (~47 chars) + 200 chars of detail + "…" = about 250.
    assert!(
        msg.chars().count() < 300,
        "truncation failed: {}",
        msg.chars().count()
    );
    assert!(msg.contains('…'));
}
