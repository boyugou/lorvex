//! `tasks` writer with embedded `checklist_items`.
//!
//! Tasks fold their `task_checklist_items` rows into the payload as a
//! `checklist_items` array so a single envelope carries the full
//! authoring state. The auxiliary statement is reused via
//! `prepare_cached` so the per-row cost stays compiled-once.

use rusqlite::Connection;
use serde_json::{json, Value};

use super::{ExtractedRow, VersionedTableWriter};
use crate::export::ExportError;
use lorvex_domain::naming::ENTITY_TASK;

const SELECT_SQL: &str = "SELECT id, title, body, raw_input, ai_notes,
                                 status, list_id,
                                 priority, due_date, due_time, estimated_minutes,
                                 recurrence,
                                 (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]')
                                  FROM task_recurrence_exceptions WHERE task_id = tasks.id) AS recurrence_exceptions,
                                 spawned_from, recurrence_group_id,
                                 canonical_occurrence_date,
                                 created_at, updated_at, completed_at, last_deferred_at, last_defer_reason,
                                 planned_date, defer_count, recurrence_instance_key, archived_at, version,
                                 available_from
                          FROM tasks";

const CHECKLIST_SQL: &str =
    "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
     FROM task_checklist_items
     WHERE task_id = ?1
     ORDER BY position ASC, created_at ASC, id ASC";

pub(in crate::export) struct TaskWriter;

impl VersionedTableWriter for TaskWriter {
    fn entity_type(&self) -> &str {
        ENTITY_TASK
    }

    fn select_sql(&self) -> &str {
        SELECT_SQL
    }

    fn extract(
        &self,
        conn: &Connection,
        row: &rusqlite::Row<'_>,
    ) -> Result<ExtractedRow, ExportError> {
        let id: String = row.get(0)?;
        let title: String = row.get(1)?;
        let body: Option<String> = row.get(2)?;
        let raw_input: Option<String> = row.get(3)?;
        let ai_notes: Option<String> = row.get(4)?;
        let status: String = row.get(5)?;
        let list_id: String = row.get(6)?;
        let priority: Option<i64> = row.get(7)?;
        let due_date: Option<String> = row.get(8)?;
        let due_time: Option<String> = row.get(9)?;
        let estimated_minutes: Option<i64> = row.get(10)?;
        let recurrence: Option<String> = row.get(11)?;
        let recurrence_exceptions: Option<String> = row.get(12)?;
        let spawned_from: Option<String> = row.get(13)?;
        let recurrence_group_id: Option<String> = row.get(14)?;
        let canonical_occurrence_date: Option<String> = row.get(15)?;
        let created_at: String = row.get(16)?;
        let updated_at: String = row.get(17)?;
        let completed_at: Option<String> = row.get(18)?;
        let last_deferred_at: Option<String> = row.get(19)?;
        let last_defer_reason: Option<String> = row.get(20)?;
        let planned_date: Option<String> = row.get(21)?;
        let defer_count: i64 = row.get(22)?;
        let recurrence_instance_key: Option<String> = row.get(23)?;
        let archived_at: Option<String> = row.get(24)?;
        let version: String = row.get(25)?;
        let available_from: Option<String> = row.get(26)?;

        let mut checklist_stmt = conn.prepare_cached(CHECKLIST_SQL)?;
        let mut checklist_items: Vec<Value> = Vec::new();
        let mut checklist_rows = checklist_stmt.query([&id])?;
        while let Some(checklist_row) = checklist_rows.next()? {
            let item_id: String = checklist_row.get(0)?;
            let task_id: String = checklist_row.get(1)?;
            let position: i64 = checklist_row.get(2)?;
            let text: String = checklist_row.get(3)?;
            let completed_at: Option<String> = checklist_row.get(4)?;
            let item_version: String = checklist_row.get(5)?;
            let item_created_at: String = checklist_row.get(6)?;
            let item_updated_at: String = checklist_row.get(7)?;
            checklist_items.push(json!({
                "id": item_id,
                "task_id": task_id,
                "position": position,
                "text": text,
                "completed_at": completed_at,
                "version": item_version,
                "created_at": item_created_at,
                "updated_at": item_updated_at,
            }));
        }

        let payload = json!({
            "id": id,
            "title": title,
            "body": body,
            "raw_input": raw_input,
            "ai_notes": ai_notes,
            "status": status,
            "list_id": list_id,
            "checklist_items": checklist_items,
            "priority": priority,
            "due_date": due_date,
            "due_time": due_time,
            "estimated_minutes": estimated_minutes,
            "recurrence": recurrence,
            "recurrence_exceptions": recurrence_exceptions,
            "spawned_from": spawned_from,
            "recurrence_group_id": recurrence_group_id,
            "canonical_occurrence_date": canonical_occurrence_date,
            "created_at": created_at,
            "updated_at": updated_at,
            "completed_at": completed_at,
            "last_deferred_at": last_deferred_at,
            "last_defer_reason": last_defer_reason,
            "planned_date": planned_date,
            "defer_count": defer_count,
            "recurrence_instance_key": recurrence_instance_key,
            "archived_at": archived_at,
            "available_from": available_from,
        });
        Ok(ExtractedRow {
            entity_id: id,
            version,
            payload,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::open_db_in_memory;

    #[test]
    fn embeds_checklist_items_ordered_by_position() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO tasks (id, title, status, created_at, updated_at, version) \
             VALUES ('task-cl', 'T', 'open', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_taskcl001')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at) \
             VALUES ('cl-2', 'task-cl', 1, 'second', '0000000000000_0000_clitem002', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at) \
             VALUES ('cl-1', 'task-cl', 0, 'first', '0000000000000_0000_clitem001', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        ).unwrap();

        let writer = TaskWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let mut found = None;
        while let Some(row) = rows.next().unwrap() {
            let extracted = writer.extract(&conn, row).unwrap();
            if extracted.entity_id == "task-cl" {
                found = Some(extracted);
                break;
            }
        }
        let extracted = found.expect("inserted task-cl should be visible");
        let items = extracted
            .payload
            .get("checklist_items")
            .and_then(Value::as_array)
            .unwrap();
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].get("id").and_then(Value::as_str), Some("cl-1"));
        assert_eq!(items[1].get("id").and_then(Value::as_str), Some("cl-2"));
        assert_eq!(extracted.version, "0000000000000_0000_taskcl001");
    }
}
