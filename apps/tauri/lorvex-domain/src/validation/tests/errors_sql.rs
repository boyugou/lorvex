use super::super::*;

#[test]
fn display_empty() {
    let err = ValidationError::Empty("title");
    assert_eq!(err.to_string(), "title must not be empty");
}

#[test]
fn display_too_long() {
    let err = ValidationError::TooLong {
        field: "title",
        max: 500,
        actual: 600,
    };
    assert_eq!(
        err.to_string(),
        "title exceeds maximum length (600 chars, limit 500)"
    );
}

#[test]
fn display_out_of_range() {
    let err = ValidationError::OutOfRange {
        field: "priority",
        min: 1,
        max: 3,
        actual: 0,
    };
    assert_eq!(
        err.to_string(),
        "priority is out of range (0, must be 1..=3)"
    );
}

#[test]
fn display_invalid_format() {
    let err = ValidationError::InvalidFormat {
        field: "date",
        expected: "YYYY-MM-DD",
        actual: "bad".to_string(),
    };
    assert_eq!(
        err.to_string(),
        "date has invalid format (got \"bad\", expected YYYY-MM-DD)"
    );
}

// -- assert_safe_sql_identifier -----------------------------------

#[test]
fn sql_identifier_valid_simple() {
    assert_safe_sql_identifier("tasks");
}

#[test]
fn sql_identifier_valid_with_underscores() {
    assert_safe_sql_identifier("ai_changelog");
}

#[test]
fn sql_identifier_valid_with_digits() {
    assert_safe_sql_identifier("table_2");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_empty() {
    assert_safe_sql_identifier("");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_semicolon() {
    assert_safe_sql_identifier("tasks; DROP TABLE tasks");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_spaces() {
    assert_safe_sql_identifier("my table");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_quotes() {
    assert_safe_sql_identifier("tasks'");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_parens() {
    assert_safe_sql_identifier("tasks()");
}

#[test]
#[should_panic(expected = "invalid SQL identifier")]
fn sql_identifier_rejects_dash() {
    assert_safe_sql_identifier("my-table");
}
