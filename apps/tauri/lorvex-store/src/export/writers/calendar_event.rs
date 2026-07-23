//! `calendar_events` writer with embedded `attendees`.
//!
//! Attendees route through `attendee_shadow::load_attendees_with_extras`
//! so each attendee's per-row `extra_fields_json` shadow extras are
//! merged back into the export payload — preventing the round-trip
//! drift that `attendee_shadow` exists to prevent (#2317). The
//! `event_type` column is parsed through `CanonicalCalendarEventType` so
//! a non-canonical value surfaces as a Serialization error rather than
//! silently riding the wire.

use rusqlite::Connection;
use serde_json::json;

use super::{ExtractedRow, VersionedTableWriter};
use crate::error::StoreError;
use crate::export::{sqlite_bool_to_json, ExportError};
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::CanonicalCalendarEventType;

const SELECT_SQL: &str = "SELECT id, title, description, start_date, start_time, end_date,
                                 end_time, all_day, location, url, color,
                                 recurrence, timezone,
                                 (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]')
                                  FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) AS recurrence_exceptions,
                                 event_type,
                                 person_name, series_id, recurrence_instance_date,
                                 created_at, updated_at, version
                          FROM calendar_events";

pub(in crate::export) struct CalendarEventWriter;

impl VersionedTableWriter for CalendarEventWriter {
    fn entity_type(&self) -> &str {
        ENTITY_CALENDAR_EVENT
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
        let description: Option<String> = row.get(2)?;
        let start_date: String = row.get(3)?;
        let start_time: Option<String> = row.get(4)?;
        let end_date: Option<String> = row.get(5)?;
        let end_time: Option<String> = row.get(6)?;
        let all_day: i64 = row.get(7)?;
        let location: Option<String> = row.get(8)?;
        let url: Option<String> = row.get(9)?;
        let color: Option<String> = row.get(10)?;
        let recurrence: Option<String> = row.get(11)?;
        let timezone: Option<String> = row.get(12)?;
        let recurrence_exceptions: Option<String> = row.get(13)?;
        let event_type = row
            .get::<_, String>(14)?
            .parse::<CanonicalCalendarEventType>()
            .map_err(|error| {
                ExportError::Store(StoreError::Serialization(format!(
                    "calendar_events.event_type must be canonical before export: {error}"
                )))
            })?;
        let person_name: Option<String> = row.get(15)?;
        let series_id: Option<String> = row.get(16)?;
        let recurrence_instance_date: Option<String> = row.get(17)?;
        let created_at: String = row.get(18)?;
        let updated_at: String = row.get(19)?;
        let version: String = row.get(20)?;

        let typed_event_id = lorvex_domain::EventId::from_trusted(id.clone());
        let attendees = lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(
            conn,
            &typed_event_id,
        )?;

        let payload = json!({
            "id": id,
            "title": title,
            "description": description,
            "start_date": start_date,
            "start_time": start_time,
            "end_date": end_date,
            "end_time": end_time,
            "all_day": sqlite_bool_to_json("calendar_events", "all_day", all_day)?,
            "location": location,
            "url": url,
            "color": color,
            "recurrence": recurrence,
            "timezone": timezone,
            "recurrence_exceptions": recurrence_exceptions,
            "event_type": event_type.as_str(),
            "person_name": person_name,
            "series_id": series_id,
            "recurrence_instance_date": recurrence_instance_date,
            "created_at": created_at,
            "updated_at": updated_at,
            "attendees": attendees,
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
    use serde_json::Value;

    #[test]
    fn coerces_all_day_int_to_json_bool() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO calendar_events (id, title, start_date, all_day, event_type, created_at, updated_at, version) \
             VALUES ('cev-1', 'All day evt', '2026-02-02', 1, 'event', '2026-02-02T00:00:00Z', '2026-02-02T00:00:00Z', '0000000000000_0000_cev0001ad')",
            [],
        ).unwrap();

        let writer = CalendarEventWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        assert_eq!(extracted.entity_id, "cev-1");
        // `all_day` int column lands as a JSON bool, not a number — the
        // shadow merge contract relies on type-matched values.
        assert_eq!(extracted.payload.get("all_day"), Some(&Value::Bool(true)));
        assert_eq!(
            extracted.payload.get("event_type").and_then(Value::as_str),
            Some("event")
        );
    }

    #[test]
    fn exports_override_linkage_fields() {
        let conn = open_db_in_memory().unwrap();
        conn.execute(
            "INSERT INTO calendar_events (
                id, title, start_date, all_day, event_type, series_id,
                recurrence_instance_date, created_at, updated_at, version
             ) VALUES (
                'cev-override', 'Override', '2026-02-03', 0, 'event',
                'cev-series', '2026-02-03',
                '2026-02-03T00:00:00Z', '2026-02-03T00:00:00Z',
                '0000000000000_0000_cev0001ae'
             )",
            [],
        )
        .unwrap();

        let writer = CalendarEventWriter;
        let mut stmt = conn.prepare(writer.select_sql()).unwrap();
        let mut rows = stmt.query([]).unwrap();
        let row = rows.next().unwrap().unwrap();
        let extracted = writer.extract(&conn, row).unwrap();
        assert_eq!(
            extracted.payload.get("series_id").and_then(Value::as_str),
            Some("cev-series")
        );
        assert_eq!(
            extracted
                .payload
                .get("recurrence_instance_date")
                .and_then(Value::as_str),
            Some("2026-02-03")
        );
    }
}
