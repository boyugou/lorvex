//! `calendar_event` aggregate payload builder.
//!
//! Header columns from `calendar_events` plus the materialized
//! `attendees` collection merged with per-attendee shadow extras
//! (#2317) so unknown forward-compat fields round-trip across peers.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use lorvex_store::StoreError;

pub(super) fn build_calendar_event_payload(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
) -> Result<Option<Value>, StoreError> {
    // Mirror the column set the apply handler reads (see
    // lorvex_sync::apply::aggregate::calendar_event::apply_calendar_event_upsert).
    // Boolean `all_day` is read as i64 and rewritten as a JSON bool to match
    // the canonical wire shape — `is_sqlite_bool_column` for `calendar_events`
    // would flip the bare-columns reader the same way.
    //
    // `recurrence_end_date` is intentionally NOT projected: it is a
    // STORED generated column (see `001_schema.sql`) — every peer
    // recomputes it from `recurrence` on apply, so shipping the cached
    // value would just bloat the envelope.
    type Row = (
        String,         // id
        String,         // title
        Option<String>, // description
        String,         // start_date
        Option<String>, // start_time
        Option<String>, // end_date
        Option<String>, // end_time
        i64,            // all_day
        Option<String>, // location
        Option<String>, // url
        Option<String>, // color
        Option<String>, // recurrence
        Option<String>, // timezone
        Option<String>, // recurrence_exceptions
        String,         // event_type
        Option<String>, // person_name
        Option<String>, // series_id
        Option<String>, // recurrence_instance_date
        String,         // created_at
        String,         // updated_at
    );
    let row: Option<Row> = conn
        .query_row(
            "SELECT id, title, description, start_date, start_time, end_date, end_time,
                    all_day, location, url, color, recurrence, timezone,
                    (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]')
                     FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id),
                    event_type, person_name, series_id, recurrence_instance_date,
                    created_at, updated_at
             FROM calendar_events WHERE id = ?1",
            params![event_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                    row.get(11)?,
                    row.get(12)?,
                    row.get(13)?,
                    row.get(14)?,
                    row.get(15)?,
                    row.get(16)?,
                    row.get(17)?,
                    row.get(18)?,
                    row.get(19)?,
                ))
            },
        )
        .optional()?;

    let Some((
        id,
        title,
        description,
        start_date,
        start_time,
        end_date,
        end_time,
        all_day,
        location,
        url,
        color,
        recurrence,
        timezone,
        recurrence_exceptions,
        event_type,
        person_name,
        series_id,
        recurrence_instance_date,
        created_at,
        updated_at,
    )) = row
    else {
        return Ok(None);
    };

    // #2317: load attendees merged with their forward-compat shadow
    // extras so unknown per-attendee fields round-trip across peers.
    let typed_event_id = lorvex_domain::EventId::from_trusted(id.clone());
    let attendees =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(conn, &typed_event_id)?;
    let attendees_value = if attendees.is_empty() {
        Value::Null
    } else {
        Value::Array(attendees)
    };

    Ok(Some(json!({
        "id": id,
        "title": title,
        "description": description,
        "start_date": start_date,
        "start_time": start_time,
        "end_date": end_date,
        "end_time": end_time,
        "all_day": all_day != 0,
        "location": location,
        "url": url,
        "color": color,
        "recurrence": recurrence,
        "timezone": timezone,
        "recurrence_exceptions": recurrence_exceptions,
        "event_type": event_type,
        "person_name": person_name,
        "series_id": series_id,
        "recurrence_instance_date": recurrence_instance_date,
        "created_at": created_at,
        "updated_at": updated_at,
        "attendees": attendees_value,
    })))
}
