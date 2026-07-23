//! Generic writer for any versioned table whose payload is just the
//! columns it stores, no embedded children.
//!
//! Covers `lists`, `tags`, `calendar_subscriptions`,
//! `preferences`, `memories`, `memory_revisions`, `task_reminders`,
//! `task_checklist_items`, and `habit_reminder_policies`. Habits use the
//! dedicated `HabitWriter` because their `weekly` weekday set lives in the
//! `habit_weekdays` child. The single-table-row → payload reshape
//! is uniform: copy each column verbatim into a JSON object, threading
//! per-column type-coercion through [`sqlite_column_value_to_json`].

use rusqlite::Connection;
use serde_json::{Map, Value};

use super::{ExtractedRow, VersionedTableWriter};
use crate::export::{sqlite_column_value_to_json, ExportError};

/// Versioned-table writer for tables whose payload mirrors their column
/// list. Validates SQL identifiers at construction so the shared
/// pipeline never re-checks them on the hot path.
pub(in crate::export) struct ColumnarEntityWriter {
    entity_type: &'static str,
    table_name: &'static str,
    id_column: &'static str,
    columns: &'static [&'static str],
    select_sql: String,
}

impl ColumnarEntityWriter {
    pub(in crate::export) fn new(
        entity_type: &'static str,
        table_name: &'static str,
        id_column: &'static str,
        columns: &'static [&'static str],
    ) -> Self {
        lorvex_domain::assert_safe_sql_identifier(table_name);
        lorvex_domain::assert_safe_sql_identifier(id_column);
        for col in columns {
            lorvex_domain::assert_safe_sql_identifier(col);
        }
        let cols = columns.join(", ");
        let select_sql = format!("SELECT {cols}, version FROM {table_name}");
        Self {
            entity_type,
            table_name,
            id_column,
            columns,
            select_sql,
        }
    }
}

impl VersionedTableWriter for ColumnarEntityWriter {
    fn entity_type(&self) -> &str {
        self.entity_type
    }

    fn select_sql(&self) -> &str {
        &self.select_sql
    }

    fn extract(
        &self,
        _conn: &Connection,
        row: &rusqlite::Row<'_>,
    ) -> Result<ExtractedRow, ExportError> {
        let mut payload = Map::new();
        for (i, &col) in self.columns.iter().enumerate() {
            let val: rusqlite::types::Value = row.get(i)?;
            payload.insert(
                col.to_string(),
                sqlite_column_value_to_json(self.table_name, col, val)?,
            );
        }
        // Entity id sits in the payload at `id_column` — handle both
        // TEXT and INTEGER PKs without relying on the ToString impl
        // for `Value`, which would quote a TEXT id.
        let entity_id = match payload.get(self.id_column) {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Number(n)) => n.to_string(),
            _ => String::new(),
        };
        let version: String = row.get(self.columns.len())?;
        Ok(ExtractedRow {
            entity_id,
            version,
            payload: Value::Object(payload),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::open_db_in_memory;
    use lorvex_domain::naming::ENTITY_LIST;

    #[test]
    fn extracts_text_id_without_quoting() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version) \
             VALUES ('list-x', 'Project', '#00FF00', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_textid001')",
            [],
        ).unwrap();

        let writer = ColumnarEntityWriter::new(
            ENTITY_LIST,
            "lists",
            "id",
            &[
                "id",
                "name",
                "color",
                "icon",
                "description",
                "ai_notes",
                "created_at",
                "updated_at",
                "archived_at",
                "position",
            ],
        );

        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let mut found = None;
        while let Some(row) = rows.next().unwrap() {
            let extracted = writer.extract(&conn, row).unwrap();
            if extracted.entity_id == "list-x" {
                found = Some(extracted);
                break;
            }
        }
        let extracted = found.expect("inserted row should be visible");
        // Plain string id, no surrounding quotes.
        assert_eq!(extracted.entity_id, "list-x");
        assert_eq!(extracted.version, "0000000000000_0000_textid001");
        assert_eq!(
            extracted.payload.get("name").and_then(Value::as_str),
            Some("Project")
        );
        assert!(extracted.payload.get("archived_at").is_some());
        assert_eq!(
            extracted.payload.get("position").and_then(Value::as_i64),
            Some(0)
        );
    }

    #[test]
    #[should_panic(expected = "invalid SQL identifier")]
    fn constructor_rejects_unsafe_table_name() {
        ColumnarEntityWriter::new(ENTITY_LIST, "lists; DROP TABLE", "id", &["id"]);
    }
}
