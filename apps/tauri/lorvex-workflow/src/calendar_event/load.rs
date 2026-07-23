//! Calendar-event row reader.
//!
//! Loads a single `calendar_events` row enriched with its per-event
//! attendee sub-table + shadow, returning the JSON shape every
//! surface re-exports as the post-mutation `after` snapshot.

use lorvex_domain::EventId;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

/// Load a calendar event row as a JSON value, enriching the
/// `attendees` array from the per-event sub-table + shadow.
/// Surfaces re-export the same JSON as their post-mutation
/// `after`.
pub fn load_calendar_event_json(
    conn: &Connection,
    event_id: &str,
) -> Result<Option<Value>, StoreError> {
    let Some(row) = lorvex_store::calendar_timeline::queries::get_calendar_event(conn, event_id)
        .map_err(StoreError::from)?
    else {
        return Ok(None);
    };
    let mut event = serde_json::to_value(row)
        .map_err(|e| StoreError::Serialization(format!("calendar event row → JSON: {e}")))?;
    let typed_event_id = EventId::from_trusted(event_id.to_string());
    let attendees =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(conn, &typed_event_id)?;
    if let Some(obj) = event.as_object_mut() {
        if attendees.is_empty() {
            obj.insert("attendees".to_string(), Value::Null);
        } else {
            obj.insert("attendees".to_string(), Value::Array(attendees));
        }
    }
    Ok(Some(event))
}
