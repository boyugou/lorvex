//! Shared boundary error sanitization for SQLite errors.
//!
//! Both the MCP server and Tauri app need to translate internal SQLite errors
//! into user-facing messages without leaking table/column names. This module
//! provides a single shared implementation per the spec (doc 21).

/// Attempt to sanitize a known SQLite error into a friendly user-facing message.
/// Returns `None` if the error doesn't match any known pattern.
pub fn sanitize_sqlite_error(raw: &str) -> Option<String> {
    if raw.contains("UNIQUE constraint failed") {
        if let Some(suffix) = raw.split("UNIQUE constraint failed: ").nth(1) {
            let entity = suffix
                .split('.')
                .next()
                .unwrap_or("record")
                .trim_end_matches('s');
            return Some(format!("A {entity} with this identifier already exists"));
        }
        return Some("A record with this identifier already exists".to_string());
    }
    if raw.contains("FOREIGN KEY constraint failed") {
        return Some(
            "Operation failed: a referenced record does not exist or would be orphaned".to_string(),
        );
    }
    if raw.contains("NOT NULL constraint failed") {
        if let Some(suffix) = raw.split("NOT NULL constraint failed: ").nth(1) {
            // Expected format: "table.column". Only extract the column name
            // if the suffix contains a dot; otherwise fall through to the
            // generic message to avoid leaking a bare table name.
            if suffix.contains('.') {
                if let Some(column) = suffix.split('.').next_back() {
                    return Some(format!("Required field '{column}' must not be null"));
                }
            }
        }
        return Some("A required field is missing".to_string());
    }
    if raw.contains("CHECK constraint failed") {
        return Some("A value failed a validation check".to_string());
    }
    if raw.contains("database is locked") || raw.contains("database table is locked") {
        return Some("The database is temporarily busy. Please retry the operation.".to_string());
    }
    None
}

#[cfg(test)]
mod tests;
