//! `daily_reviews` writer with embedded `linked_task_ids` + `linked_list_ids`.

use rusqlite::Connection;
use serde_json::json;

use super::{ExtractedRow, VersionedTableWriter};
use crate::export::ExportError;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;

const SELECT_SQL: &str = "SELECT date, summary, mood, energy_level, wins, blockers,
                                 learnings, ai_synthesis, timezone, created_at, updated_at, version
                          FROM daily_reviews";

const TASK_LINKS_SQL: &str = "SELECT task_id FROM daily_review_task_links WHERE review_date = ?1";
const LIST_LINKS_SQL: &str = "SELECT list_id FROM daily_review_list_links WHERE review_date = ?1";

pub(in crate::export) struct DailyReviewWriter;

impl VersionedTableWriter for DailyReviewWriter {
    fn entity_type(&self) -> &str {
        ENTITY_DAILY_REVIEW
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
        let summary: String = row.get(1)?;
        let mood: Option<i64> = row.get(2)?;
        let energy_level: Option<i64> = row.get(3)?;
        let wins: Option<String> = row.get(4)?;
        let blockers: Option<String> = row.get(5)?;
        let learnings: Option<String> = row.get(6)?;
        let ai_synthesis: Option<String> = row.get(7)?;
        let timezone: Option<String> = row.get(8)?;
        let created_at: String = row.get(9)?;
        let updated_at: String = row.get(10)?;
        let version: String = row.get(11)?;

        let mut task_links_stmt = conn.prepare_cached(TASK_LINKS_SQL)?;
        let linked_task_ids: Vec<String> = task_links_stmt
            .query_map([&date], |r| r.get(0))?
            .collect::<Result<_, _>>()?;
        let mut list_links_stmt = conn.prepare_cached(LIST_LINKS_SQL)?;
        let linked_list_ids: Vec<String> = list_links_stmt
            .query_map([&date], |r| r.get(0))?
            .collect::<Result<_, _>>()?;

        let payload = json!({
            "date": date,
            "summary": summary,
            "mood": mood,
            "energy_level": energy_level,
            "wins": wins,
            "blockers": blockers,
            "learnings": learnings,
            "ai_synthesis": ai_synthesis,
            "timezone": timezone,
            "created_at": created_at,
            "updated_at": updated_at,
            "linked_task_ids": linked_task_ids,
            "linked_list_ids": linked_list_ids,
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
    fn embeds_both_task_and_list_links_keyed_by_date() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version) \
             VALUES ('list-dr', 'L', '#000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_listdr001')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version) \
             VALUES ('task-dr', 'T', 'open', 'list-dr', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_taskdr001')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO daily_reviews (date, summary, created_at, updated_at, version) \
             VALUES ('2026-05-01', 'sum', '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z', '0000000000000_0000_drvr00001')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO daily_review_task_links (review_date, task_id, created_at) VALUES ('2026-05-01', 'task-dr', '2026-05-01T00:00:00Z')",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO daily_review_list_links (review_date, list_id, created_at) VALUES ('2026-05-01', 'list-dr', '2026-05-01T00:00:00Z')",
            [],
        ).unwrap();

        let writer = DailyReviewWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        assert_eq!(extracted.entity_id, "2026-05-01");
        let tasks = extracted
            .payload
            .get("linked_task_ids")
            .and_then(Value::as_array)
            .unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].as_str(), Some("task-dr"));
        let lists = extracted
            .payload
            .get("linked_list_ids")
            .and_then(Value::as_array)
            .unwrap();
        assert_eq!(lists.len(), 1);
        assert_eq!(lists[0].as_str(), Some("list-dr"));
    }
}
