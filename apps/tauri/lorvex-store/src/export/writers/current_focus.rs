//! `current_focus` writer with embedded `task_ids`.
//!
//! The aggregate row is keyed by `date`; ordered task ids are folded in
//! from `current_focus_items` so a single envelope captures the full
//! daily focus snapshot.

use rusqlite::Connection;
use serde_json::json;

use super::{ExtractedRow, VersionedTableWriter};
use crate::export::ExportError;
use lorvex_domain::naming::ENTITY_CURRENT_FOCUS;

const SELECT_SQL: &str =
    "SELECT date, briefing, timezone, created_at, updated_at, version FROM current_focus";

const ITEMS_SQL: &str =
    "SELECT task_id FROM current_focus_items WHERE date = ?1 ORDER BY position ASC";

pub(in crate::export) struct CurrentFocusWriter;

impl VersionedTableWriter for CurrentFocusWriter {
    fn entity_type(&self) -> &str {
        ENTITY_CURRENT_FOCUS
    }

    fn select_sql(&self) -> &str {
        SELECT_SQL
    }

    fn extract(
        &self,
        conn: &Connection,
        row: &rusqlite::Row<'_>,
    ) -> Result<ExtractedRow, ExportError> {
        let date: String = row.get(0)?;
        let briefing: Option<String> = row.get(1)?;
        let timezone: Option<String> = row.get(2)?;
        let created_at: String = row.get(3)?;
        let updated_at: String = row.get(4)?;
        let version: String = row.get(5)?;

        let mut items_stmt = conn.prepare_cached(ITEMS_SQL)?;
        let task_ids: Vec<String> = items_stmt
            .query_map([&date], |r| r.get(0))?
            .collect::<Result<_, _>>()?;

        let payload = json!({
            "date": date,
            "briefing": briefing,
            "timezone": timezone,
            "created_at": created_at,
            "updated_at": updated_at,
            "task_ids": task_ids,
        });
        Ok(ExtractedRow {
            entity_id: date,
            version,
            payload,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::open_db_in_memory;
    use serde_json::Value;

    #[test]
    fn keys_payload_by_date_and_preserves_position_order() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO tasks (id, title, status, created_at, updated_at, version) \
             VALUES ('cf-task-a', 'A', 'open', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_cftaska01')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tasks (id, title, status, created_at, updated_at, version) \
             VALUES ('cf-task-b', 'B', 'open', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_cftaskb01')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO current_focus (date, created_at, updated_at, version) \
             VALUES ('2026-03-01', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', '0000000000000_0000_curfocus01')",
            [],
        ).unwrap();
        // Insert b at position 0 and a at position 1 to confirm
        // ordering rides position, not insert order.
        conn.execute(
            "INSERT INTO current_focus_items (date, task_id, position) VALUES ('2026-03-01', 'cf-task-b', 0)",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO current_focus_items (date, task_id, position) VALUES ('2026-03-01', 'cf-task-a', 1)",
            [],
        ).unwrap();

        let writer = CurrentFocusWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        assert_eq!(extracted.entity_id, "2026-03-01");
        let task_ids = extracted
            .payload
            .get("task_ids")
            .and_then(Value::as_array)
            .unwrap();
        let ids: Vec<&str> = task_ids.iter().filter_map(Value::as_str).collect();
        assert_eq!(ids, vec!["cf-task-b", "cf-task-a"]);
    }
}
