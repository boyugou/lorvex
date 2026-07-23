//! `focus_schedule` writer with embedded `blocks`.
//!
//! Blocks are produced through `focus_schedule_snapshot::serialize_blocks_for_sync`
//! so the export shape matches the wire format used by sync, including
//! provider write-down neutralization.

use rusqlite::Connection;
use serde_json::json;

use super::{ExtractedRow, VersionedTableWriter};
use crate::export::ExportError;
use lorvex_domain::naming::ENTITY_FOCUS_SCHEDULE;

const SELECT_SQL: &str =
    "SELECT date, rationale, timezone, created_at, updated_at, version FROM focus_schedule";

pub(in crate::export) struct FocusScheduleWriter;

impl VersionedTableWriter for FocusScheduleWriter {
    fn entity_type(&self) -> &str {
        ENTITY_FOCUS_SCHEDULE
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
        let rationale: Option<String> = row.get(1)?;
        let timezone: Option<String> = row.get(2)?;
        let created_at: String = row.get(3)?;
        let updated_at: String = row.get(4)?;
        let version: String = row.get(5)?;

        let blocks = crate::focus_schedule_snapshot::serialize_blocks_for_sync(conn, &date)?;

        let payload = json!({
            "date": date,
            "rationale": rationale,
            "timezone": timezone,
            "created_at": created_at,
            "updated_at": updated_at,
            "blocks": blocks,
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
    fn keys_payload_by_date_and_includes_blocks_array() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO focus_schedule (date, rationale, timezone, created_at, updated_at, version) \
             VALUES ('2026-04-01', 'why', 'UTC', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z', '0000000000000_0000_fsched0001')",
            [],
        ).unwrap();

        let writer = FocusScheduleWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        assert_eq!(extracted.entity_id, "2026-04-01");
        assert_eq!(extracted.version, "0000000000000_0000_fsched0001");
        // `blocks` is always serialized, even when empty.
        assert!(matches!(
            extracted.payload.get("blocks"),
            Some(Value::Array(_))
        ));
    }
}
