//! Upserts for `calendar_events` and `calendar_subscriptions`, plus the
//! materializer that rebuilds embedded `calendar_event_attendees` rows.

use rusqlite::Connection;

use lorvex_domain::validation::{validate_date_format, validate_time_format};
use lorvex_domain::CanonicalCalendarEventType;

use super::super::helpers::{
    invalid_payload, optional_string_field, required_bool_as_i64_field, required_string_field,
    required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{import_lww_upsert, should_replace_versioned, LwwUpsertSpec, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_calendar_event(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "calendar_event payload")?;
    let version = entry.version.as_str();
    let title = required_string_field(p, "title", "calendar_event payload")?;
    let start_date = required_string_field(p, "start_date", "calendar_event payload")?;
    let event_type = required_string_field(p, "event_type", "calendar_event payload")?
        .parse::<CanonicalCalendarEventType>()
        .map_err(|message| invalid_payload(format!("calendar_event payload {message}")))?;
    let created_at = required_sync_timestamp_field(p, "created_at", "calendar_event payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "calendar_event payload")?;
    let all_day = required_bool_as_i64_field(p, "all_day", "calendar_event payload")?;
    let description = optional_string_field(p, "description", "calendar_event payload")?;
    let start_time = optional_string_field(p, "start_time", "calendar_event payload")?;
    let end_date = optional_string_field(p, "end_date", "calendar_event payload")?;
    let end_time = optional_string_field(p, "end_time", "calendar_event payload")?;
    let location = optional_string_field(p, "location", "calendar_event payload")?;
    let url = optional_string_field(p, "url", "calendar_event payload")?;
    let color = optional_string_field(p, "color", "calendar_event payload")?;
    let recurrence = optional_string_field(p, "recurrence", "calendar_event payload")?;
    let timezone = optional_string_field(p, "timezone", "calendar_event payload")?;
    let recurrence_exceptions =
        optional_string_field(p, "recurrence_exceptions", "calendar_event payload")?;
    let person_name = optional_string_field(p, "person_name", "calendar_event payload")?;
    let series_id = optional_string_field(p, "series_id", "calendar_event payload")?;
    let recurrence_instance_date =
        optional_string_field(p, "recurrence_instance_date", "calendar_event payload")?;
    if let Some(value) = recurrence_instance_date.as_deref() {
        validate_date_format(value).map_err(|e| {
            ImportError::InvalidPayload(format!(
                "calendar_event {id} recurrence_instance_date failed validation: {e}"
            ))
        })?;
    }
    if series_id.is_some() != recurrence_instance_date.is_some() {
        return Err(ImportError::InvalidPayload(
            "calendar_event payload: series_id and recurrence_instance_date must be set or cleared together"
                .to_string(),
        ));
    }
    validate_calendar_event_boundary_fields(
        &id,
        &start_date,
        start_time.as_deref(),
        end_date.as_deref(),
        end_time.as_deref(),
        all_day,
    )?;

    // Calendar events carry an embedded `attendees` array that the
    // materializer rebuilds into the `calendar_event_attendees` join
    // table — and only when the parent row was created or updated.
    // The shared `import_lww_upsert` dispatcher fits the simple cases
    // but doesn't surface the discriminated outcome we need to gate
    // attendee materialization on, so the LWW gate stays inline here.
    let result = match should_replace_versioned(conn, "calendar_events", "id", &id, version)? {
        None => {
            conn.prepare_cached(
                "INSERT INTO calendar_events (id, title, description, start_date, start_time,
                 end_date, end_time, all_day, location, url, color, recurrence,
                 timezone, event_type, person_name,
                 series_id, recurrence_instance_date, created_at, updated_at, version)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20)",
            )?
            .execute(rusqlite::params![
                id,
                title,
                description.as_deref(),
                start_date,
                start_time.as_deref(),
                end_date.as_deref(),
                end_time.as_deref(),
                all_day,
                location.as_deref(),
                url.as_deref(),
                color.as_deref(),
                recurrence.as_deref(),
                timezone.as_deref(),
                event_type.as_str(),
                person_name.as_deref(),
                series_id.as_deref(),
                recurrence_instance_date.as_deref(),
                created_at,
                updated_at,
                version,
            ])?;
            UpsertResult::Created
        }
        Some(true) => {
            conn.prepare_cached(
                "UPDATE calendar_events SET title=?2, description=?3, start_date=?4,
                 start_time=?5, end_date=?6, end_time=?7, all_day=?8, location=?9,
                 url=?10, color=?11, recurrence=?12, timezone=?13,
                 event_type=?14, person_name=?15,
                 series_id=?16, recurrence_instance_date=?17,
                 created_at=?18, updated_at=?19, version=?20
                 WHERE id=?1",
            )?
            .execute(rusqlite::params![
                id,
                title,
                description.as_deref(),
                start_date,
                start_time.as_deref(),
                end_date.as_deref(),
                end_time.as_deref(),
                all_day,
                location.as_deref(),
                url.as_deref(),
                color.as_deref(),
                recurrence.as_deref(),
                timezone.as_deref(),
                event_type.as_str(),
                person_name.as_deref(),
                series_id.as_deref(),
                recurrence_instance_date.as_deref(),
                created_at,
                updated_at,
                version,
            ])?;
            UpsertResult::Updated
        }
        Some(false) => return Ok(UpsertResult::Skipped),
    };

    // EXDATE registry lives in
    // `calendar_event_recurrence_exceptions` since #4585 — rewrite
    // it from the wire-form JSON after the parent INSERT/UPDATE.
    crate::recurrence_exceptions::replace_event_exceptions_from_json(
        conn,
        &id,
        recurrence_exceptions.as_deref(),
    )?;

    // Materialize embedded attendees into calendar_event_attendees.
    let typed_event_id = lorvex_domain::EventId::from_trusted(id);
    materialize_calendar_event_attendees(conn, &typed_event_id, p)?;

    Ok(result)
}

fn validate_calendar_event_boundary_fields(
    id: &str,
    start_date: &str,
    start_time: Option<&str>,
    end_date: Option<&str>,
    end_time: Option<&str>,
    all_day: i64,
) -> Result<(), ImportError> {
    validate_date_format(start_date).map_err(|e| {
        ImportError::InvalidPayload(format!(
            "calendar_event {id} start_date failed validation: {e}"
        ))
    })?;
    if let Some(value) = end_date {
        validate_date_format(value).map_err(|e| {
            ImportError::InvalidPayload(format!(
                "calendar_event {id} end_date failed validation: {e}"
            ))
        })?;
    }
    if let Some(value) = start_time {
        validate_time_format(value).map_err(|e| {
            ImportError::InvalidPayload(format!(
                "calendar_event {id} start_time failed validation: {e}"
            ))
        })?;
    }
    if let Some(value) = end_time {
        validate_time_format(value).map_err(|e| {
            ImportError::InvalidPayload(format!(
                "calendar_event {id} end_time failed validation: {e}"
            ))
        })?;
    }
    if all_day != 0 && (start_time.is_some() || end_time.is_some()) {
        return Err(ImportError::InvalidPayload(
            "calendar_event payload: all_day=1 requires start_time and end_time to be null"
                .to_string(),
        ));
    }
    Ok(())
}

pub(in crate::import::apply::upserts) fn upsert_calendar_subscription(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "calendar_subscription payload")?;
    let version = entry.version.as_str();
    let name = required_string_field(p, "name", "calendar_subscription payload")?;
    let url = required_string_field(p, "url", "calendar_subscription payload")?;
    let created_at =
        required_sync_timestamp_field(p, "created_at", "calendar_subscription payload")?;
    let updated_at =
        required_sync_timestamp_field(p, "updated_at", "calendar_subscription payload")?;
    let enabled = required_bool_as_i64_field(p, "enabled", "calendar_subscription payload")?;
    let color = optional_string_field(p, "color", "calendar_subscription payload")?;

    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "calendar_subscriptions",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql: "INSERT INTO calendar_subscriptions (id, name, url, color, enabled,
                 created_at, updated_at, version)
                VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
            update_sql: "UPDATE calendar_subscriptions SET name=?2, url=?3, color=?4, enabled=?5,
                 created_at=?6, updated_at=?7, version=?8
                WHERE id=?1",
        },
        rusqlite::params![
            id,
            name,
            url,
            color.as_deref(),
            enabled,
            created_at,
            updated_at,
            version,
        ],
    )
}

/// Rebuild `calendar_event_attendees` from the embedded `attendees` array in the payload.
///
/// lowercase + trim `email` at the import boundary
/// before `INSERT OR IGNORE`. The export pipeline already
/// canonicalizes emails (NFC + ASCII-lowercase), but a hand-crafted
/// import archive carrying mixed-case rows would silently dedup
/// against whichever casing landed first — the user lost attendee
/// rows whose case differed from the canonical form, with no error
/// surfaced. Defense-in-depth at the import boundary keeps the
/// import idempotent regardless of source casing.
fn materialize_calendar_event_attendees(
    conn: &Connection,
    event_id: &lorvex_domain::EventId,
    payload: &serde_json::Value,
) -> Result<(), ImportError> {
    conn.prepare_cached("DELETE FROM calendar_event_attendees WHERE event_id = ?1")?
        .execute([event_id])?;
    if let Some(attendees) = payload.get("attendees") {
        let attendees = attendees
            .as_array()
            .ok_or_else(|| invalid_payload("calendar_event payload.attendees must be an array"))?;
        // Lift the per-attendee INSERT prepare out of the loop. An
        // event with N attendees pays one parse instead of N.
        let mut insert_stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
             VALUES (?1, ?2, ?3, ?4, ?5)",
        )?;
        for (index, att) in attendees.iter().enumerate() {
            let context = format!("calendar_event payload.attendees[{index}]");
            let email = required_string_field(att, "email", &context)?
                .trim()
                .to_lowercase();
            let name = optional_string_field(att, "name", &context)?;
            let raw_status = optional_string_field(att, "status", &context)?;
            let status = raw_status
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|trimmed| {
                    lorvex_domain::AttendeeStatus::parse_strict(trimmed)
                        .map(|status| status.as_str().to_string())
                        .ok_or_else(|| {
                            invalid_payload(format!(
                                "{context}.status '{trimmed}' is not a recognized RFC 5545 \
                                 PARTSTAT value (expected one of: {})",
                                lorvex_domain::attendee_status_allowlist_display()
                            ))
                        })
                })
                .transpose()?;
            // Synthesize the device-local identity, matching the sync-apply +
            // local-write surfaces so a restored event keys its attendees the
            // same way. The anonymous content-hash basis is only evaluated for
            // a fully-anonymous attendee (no email AND no name); import does
            // not carry the surplus `extras` (it materializes only the known
            // columns), so the basis omits them — consistent with import's
            // known-columns-only rebuild.
            let attendee_id = if email.is_empty() && name.is_none() {
                let basis = lorvex_domain::attendee_identity::anonymous_identity_basis(
                    &email,
                    name.as_deref(),
                    status.as_deref(),
                    None,
                );
                lorvex_domain::attendee_identity::synthesize(&email, name.as_deref(), &basis)
            } else {
                lorvex_domain::attendee_identity::synthesize(&email, name.as_deref(), "")
            };
            insert_stmt.execute(rusqlite::params![
                event_id,
                attendee_id,
                email,
                name,
                status
            ])?;
        }
    }
    Ok(())
}
