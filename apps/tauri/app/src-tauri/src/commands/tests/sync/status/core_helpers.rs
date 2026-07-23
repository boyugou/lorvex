use super::*;

/// Inlined from the former sync_apply module — simple JSON-to-preference-string conversion.
fn preference_value_to_storage(value: Option<&serde_json::Value>) -> String {
    match value {
        None | Some(serde_json::Value::Null) => "null".to_string(),
        Some(serde_json::Value::String(v)) => v.clone(),
        Some(other) => serde_json::to_string(other).unwrap_or_else(|_| "null".to_string()),
    }
}

#[test]
fn preference_value_to_storage_preserves_string_and_json_values() {
    assert_eq!(
        preference_value_to_storage(Some(&json!("\"zh\""))),
        "\"zh\"".to_string()
    );
    assert_eq!(
        preference_value_to_storage(Some(&json!({"enabled": true}))),
        "{\"enabled\":true}".to_string()
    );
}

#[test]
fn with_immediate_transaction_rolls_back_on_error() {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute("CREATE TABLE tx_test (value TEXT NOT NULL)", [])
        .expect("create tx_test");

    let result: Result<(), crate::error::AppError> = with_immediate_transaction(&conn, |conn| {
        conn.execute("INSERT INTO tx_test (value) VALUES ('hello')", [])
            .map_err(crate::error::AppError::from)?;
        Err(crate::error::AppError::Internal(
            "force rollback".to_string(),
        ))
    });
    assert!(result.is_err());

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tx_test", [], |row| row.get(0))
        .expect("count rows");
    assert_eq!(count, 0);
}
