use crate::error::StoreError;

use super::ExportError;

/// Convert a `rusqlite::types::Value` to a `serde_json::Value`.
pub(super) fn sqlite_value_to_json(val: rusqlite::types::Value) -> serde_json::Value {
    match val {
        rusqlite::types::Value::Null => serde_json::Value::Null,
        rusqlite::types::Value::Integer(i) => serde_json::Value::Number(i.into()),
        rusqlite::types::Value::Real(f) => lorvex_domain::serde_support::sqlite_real_to_json(f),
        rusqlite::types::Value::Text(s) => serde_json::Value::String(s),
        rusqlite::types::Value::Blob(b) => {
            // Encode blobs as base64 strings for JSON transport.
            use hex::encode;
            serde_json::Value::String(encode(b))
        }
    }
}

pub(super) fn sqlite_bool_to_json(
    table: &str,
    column: &str,
    value: i64,
) -> Result<serde_json::Value, ExportError> {
    match value {
        0 => Ok(serde_json::Value::Bool(false)),
        1 => Ok(serde_json::Value::Bool(true)),
        other => Err(ExportError::Store(StoreError::Serialization(format!(
            "{table}.{column} must be 0 or 1 before export, got {other}"
        )))),
    }
}

pub(super) fn sqlite_column_value_to_json(
    table: &str,
    column: &str,
    val: rusqlite::types::Value,
) -> Result<serde_json::Value, ExportError> {
    if table == "preferences" && column == "value" {
        return match val {
            rusqlite::types::Value::Text(raw) => serde_json::from_str(&raw).map_err(|error| {
                ExportError::Store(StoreError::Serialization(format!(
                    "preferences.value must be canonical JSON before export: {error}"
                )))
            }),
            rusqlite::types::Value::Null => Ok(serde_json::Value::Null),
            _ => Err(ExportError::Store(StoreError::Serialization(
                "preferences.value must be a JSON-encoded SQLite text value before export"
                    .to_string(),
            ))),
        };
    }

    if lorvex_domain::storage_schema::is_sqlite_bool_column(table, column) {
        return match val {
            rusqlite::types::Value::Integer(value) => sqlite_bool_to_json(table, column, value),
            rusqlite::types::Value::Null => Ok(serde_json::Value::Null),
            _ => Err(ExportError::Store(StoreError::Serialization(format!(
                "{table}.{column} must be a SQLite integer boolean before export"
            )))),
        };
    }

    Ok(sqlite_value_to_json(val))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preference_value_column_exports_parsed_json_not_raw_text() {
        let value = sqlite_column_value_to_json(
            "preferences",
            "value",
            rusqlite::types::Value::Text("\"dark\"".to_string()),
        )
        .unwrap();
        assert_eq!(value, serde_json::json!("dark"));

        let value = sqlite_column_value_to_json(
            "preferences",
            "value",
            rusqlite::types::Value::Text("{\"end\":\"17:00\",\"start\":\"09:00\"}".to_string()),
        )
        .unwrap();
        assert_eq!(value, serde_json::json!({"end": "17:00", "start": "09:00"}));
    }

    #[test]
    fn preference_value_column_rejects_malformed_json_text() {
        let error = sqlite_column_value_to_json(
            "preferences",
            "value",
            rusqlite::types::Value::Text("dark".to_string()),
        )
        .expect_err("malformed preference JSON should fail export");

        assert!(
            error.to_string().contains("preferences.value"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn non_preference_text_columns_still_export_as_strings() {
        let value = sqlite_column_value_to_json(
            "memories",
            "content",
            rusqlite::types::Value::Text("\"dark\"".to_string()),
        )
        .unwrap();
        assert_eq!(value, serde_json::json!("\"dark\""));
    }
}
