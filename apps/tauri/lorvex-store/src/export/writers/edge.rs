//! Versioned-table writer for edge tables.
//!
//! Edges differ from entities in two ways: the JSONL line shape omits a
//! top-level `entity_id` (the composite key already lives inside the
//! payload), and the `entity_id` used for shadow-merge bookkeeping is a
//! synthesized composite (e.g. `"task-1:tag-1"`) routed through
//! [`super::super::edge_entity_id`].

use rusqlite::Connection;
use serde_json::{Map, Value};

use super::{ExtractedRow, LineFormat, VersionedTableWriter};
use crate::export::{edge_entity_id, sqlite_column_value_to_json, ExportError};

pub(in crate::export) struct EdgeWriter {
    edge_type: &'static str,
    table_name: &'static str,
    columns: &'static [&'static str],
    select_sql: String,
}

impl EdgeWriter {
    pub(in crate::export) fn new(
        edge_type: &'static str,
        table_name: &'static str,
        columns: &'static [&'static str],
    ) -> Self {
        lorvex_domain::assert_safe_sql_identifier(table_name);
        for col in columns {
            lorvex_domain::assert_safe_sql_identifier(col);
        }
        let cols = columns.join(", ");
        let select_sql = format!("SELECT {cols}, version FROM {table_name}");
        Self {
            edge_type,
            table_name,
            columns,
            select_sql,
        }
    }
}

impl VersionedTableWriter for EdgeWriter {
    fn entity_type(&self) -> &str {
        self.edge_type
    }

    fn select_sql(&self) -> &str {
        &self.select_sql
    }

    fn line_format(&self) -> LineFormat {
        LineFormat::Edge
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
        let entity_id = edge_entity_id(self.edge_type, &payload)?;
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
    use lorvex_domain::naming::EDGE_TASK_TAG;

    #[test]
    fn extracts_composite_entity_id_from_payload() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version) \
             VALUES ('list-edge', 'L', '#000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_listedge1')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version) \
             VALUES ('task-edge', 'T', 'open', 'list-edge', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_taskedge1')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version) \
             VALUES ('tag-edge', 'urgent', 'urgent', '#FF0000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_tagedge01')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
             VALUES ('task-edge', 'tag-edge', '2026-01-01T00:00:00Z', '0000000000000_0000_edgever01')",
            [],
        ).unwrap();

        let writer = EdgeWriter::new(
            EDGE_TASK_TAG,
            "task_tags",
            &["task_id", "tag_id", "created_at"],
        );
        assert_eq!(writer.line_format(), LineFormat::Edge);
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        // Composite key derivation: task_id:tag_id.
        assert_eq!(extracted.entity_id, "task-edge:tag-edge");
        assert_eq!(extracted.version, "0000000000000_0000_edgever01");
        assert_eq!(
            extracted.payload.get("task_id").and_then(Value::as_str),
            Some("task-edge")
        );
        assert_eq!(
            extracted.payload.get("tag_id").and_then(Value::as_str),
            Some("tag-edge")
        );
    }
}
