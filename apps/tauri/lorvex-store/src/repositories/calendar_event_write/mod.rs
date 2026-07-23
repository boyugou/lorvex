//! Calendar event write repository — shared INSERT/UPDATE/DELETE for `calendar_events`.
//!
//! Used by both the Tauri app and the MCP server so the SQL logic exists in
//! exactly one place.

use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::{CanonicalCalendarEventType, Patch};
use rusqlite::{params, Connection};

use crate::error::StoreError;
use crate::repositories::lww_update::execute_lww_update;

/// enforce the canonical-event-type contract at the lowest
/// repo entry. The schema CHECK on `calendar_events.event_type` already
/// rejects non-canonical values, but failing there raises an opaque SQL
/// constraint error from arbitrarily deep call stacks; rejecting here yields
/// a `StoreError::Validation` with a user-readable message that matches what
/// the import + sync apply paths produce for the same input.
///
/// route through `CanonicalCalendarEventType::validate` so
/// every layer (sync apply, store repository, Tauri/MCP entry) shares
/// one source of truth for the canonical set and identical error
/// wording.
fn validate_event_type(value: &str) -> Result<(), StoreError> {
    CanonicalCalendarEventType::validate(value)
        .map(|_| ())
        .map_err(|err| StoreError::Validation(format!("calendar event {err}")))
}

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

/// Parameters for inserting a new calendar event.
#[derive(Debug, Clone)]
pub struct CalendarEventCreateParams<'a> {
    pub id: &'a str,
    pub title: &'a str,
    pub description: Option<&'a str>,
    pub recurrence: Option<&'a str>,
    pub recurrence_exceptions: Option<&'a str>,
    pub timezone: Option<&'a str>,
    pub start_date: &'a str,
    pub start_time: Option<&'a str>,
    pub end_date: Option<&'a str>,
    pub end_time: Option<&'a str>,
    pub all_day: bool,
    pub location: Option<&'a str>,
    pub url: Option<&'a str>,
    pub color: Option<&'a str>,
    pub event_type: &'a str,
    pub person_name: Option<&'a str>,
    pub version: &'a str,
    pub now: &'a str,
}

/// Insert a calendar event into the `calendar_events` table.
pub fn create_calendar_event(
    conn: &Connection,
    params: &CalendarEventCreateParams<'_>,
) -> Result<(), StoreError> {
    validate_event_type(params.event_type)?;
    conn.prepare_cached(
        "INSERT INTO calendar_events \
         (id, title, description, recurrence, timezone, \
          start_date, start_time, end_date, end_time, all_day, location, url, color, \
          event_type, person_name, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?17)",
    )?
    .execute(params![
        params.id,
        params.title,
        params.description,
        params.recurrence,
        params.timezone,
        params.start_date,
        params.start_time,
        params.end_date,
        params.end_time,
        i64::from(params.all_day),
        params.location,
        params.url,
        params.color,
        params.event_type,
        params.person_name,
        params.version,
        params.now,
    ])?;
    // Exceptions live in `calendar_event_recurrence_exceptions`
    // since #4585; replace the per-event registry from the
    // optional JSON wire form.
    crate::recurrence_exceptions::replace_event_exceptions_from_json(
        conn,
        params.id,
        params.recurrence_exceptions,
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

/// Patch fields for updating a calendar event. Nullable columns use
/// [`Patch<&str>`] for explicit three-state PATCH semantics:
/// - `Patch::Unset` = field not included in UPDATE
/// - `Patch::Clear` = SET column = NULL
/// - `Patch::Set("value")` = SET column = 'value'
#[derive(Debug, Clone, Default)]
pub struct CalendarEventUpdatePatch<'a> {
    pub event_id: &'a str,
    pub title: Option<&'a str>,
    pub description: Patch<&'a str>,
    pub recurrence: Patch<&'a str>,
    pub recurrence_exceptions: Patch<&'a str>,
    pub timezone: Patch<&'a str>,
    pub start_date: Option<&'a str>,
    pub start_time: Patch<&'a str>,
    pub end_date: Patch<&'a str>,
    pub end_time: Patch<&'a str>,
    pub all_day: lorvex_domain::AllDayPatch,
    pub location: Patch<&'a str>,
    pub url: Patch<&'a str>,
    pub color: Patch<&'a str>,
    pub event_type: Patch<&'a str>,
    pub person_name: Patch<&'a str>,
    pub version: &'a str,
    pub now: &'a str,
}

/// Apply a partial update to a calendar event. Returns `Ok(())` when
/// the LWW gate accepted the write, and [`StoreError::StaleVersion`]
/// when it rejected the write because the patch's `version` was not
/// strictly newer than the row's current `version`.
///
/// Always sets `version` and `updated_at`. Additional fields are only included
/// when their corresponding patch field is `Some`.
///
/// `WHERE id = :event_id AND :version > version` uses
/// **named** parameters so the LWW gate binds against the patch's
/// version regardless of how many optional `SET` columns precede it.
/// The previous shape used positional `?` placeholders for both the
/// SET clause and the WHERE clause, with the WHERE binds appended
/// after every SET bind — meaning a single field re-ordering or a
/// new SET column inserted between two existing ones would silently
/// shift the LWW comparison to bind against the wrong column. That
/// brittleness was hidden today only by a lex-ordering coincidence
/// (ISO timestamps lex-compare to 13-digit-physical-ms HLCs in the
/// 2026–2027 window in a way that made `?> wrong-column` always
/// pass), so the bug would have surfaced silently at year-rollover.
/// Named binds lock the LWW comparison to its intended column name
/// regardless of SET-clause shape.
pub fn apply_calendar_event_update(
    conn: &Connection,
    patch: &CalendarEventUpdatePatch<'_>,
) -> Result<(), StoreError> {
    if let Patch::Set(value) = patch.event_type {
        validate_event_type(value)?;
    }
    // `Option<&str>: ToSql` maps `None` → SQL NULL; `Patch::as_bind_value()`
    // collapses `Set(v)` → `Some(v)` and `Clear` → `None` so we route
    // both states through the same bind. `Unset` skips entirely.
    let mut set_parts: Vec<&str> = vec!["version = :version", "updated_at = :now"];
    // `AllDayPatch::target_value()` returns `Some(true/false)` when the
    // patch carries an explicit `all_day` change and `None` when the
    // patch leaves the existing flag alone — same shape the previous
    // `Option<bool>` carried, but the typed enum prevents callers from
    // forgetting the unarchive-equivalent (`SetTimed`) branch.
    let all_day_int: Option<i64> = patch.all_day.target_value().map(i64::from);

    // Materialize each Patch field's bind value into a local
    // `Option<&str>` so the params Vec can borrow it.
    let description_bind: Option<&str> = patch.description.as_bind_value().copied();
    let recurrence_bind: Option<&str> = patch.recurrence.as_bind_value().copied();
    let timezone_bind: Option<&str> = patch.timezone.as_bind_value().copied();
    let start_time_bind: Option<&str> = patch.start_time.as_bind_value().copied();
    let end_date_bind: Option<&str> = patch.end_date.as_bind_value().copied();
    let end_time_bind: Option<&str> = patch.end_time.as_bind_value().copied();
    let location_bind: Option<&str> = patch.location.as_bind_value().copied();
    let url_bind: Option<&str> = patch.url.as_bind_value().copied();
    let color_bind: Option<&str> = patch.color.as_bind_value().copied();
    let event_type_bind: Option<&str> = patch.event_type.as_bind_value().copied();
    let person_name_bind: Option<&str> = patch.person_name.as_bind_value().copied();

    let mut params: Vec<(&str, &dyn rusqlite::types::ToSql)> = vec![
        (":version", &patch.version),
        (":now", &patch.now),
        (":event_id", &patch.event_id),
    ];

    if let Some(ref title) = patch.title {
        set_parts.push("title = :title");
        params.push((":title", title));
    }
    if patch.description.is_set_or_clear() {
        set_parts.push("description = :description");
        params.push((":description", &description_bind));
    }
    if patch.recurrence.is_set_or_clear() {
        set_parts.push("recurrence = :recurrence");
        params.push((":recurrence", &recurrence_bind));
    }
    if patch.timezone.is_set_or_clear() {
        set_parts.push("timezone = :timezone");
        params.push((":timezone", &timezone_bind));
    }
    if let Some(ref sd) = patch.start_date {
        set_parts.push("start_date = :start_date");
        params.push((":start_date", sd));
    }
    if patch.start_time.is_set_or_clear() {
        set_parts.push("start_time = :start_time");
        params.push((":start_time", &start_time_bind));
    }
    if patch.end_date.is_set_or_clear() {
        set_parts.push("end_date = :end_date");
        params.push((":end_date", &end_date_bind));
    }
    if patch.end_time.is_set_or_clear() {
        set_parts.push("end_time = :end_time");
        params.push((":end_time", &end_time_bind));
    }
    if all_day_int.is_some() {
        set_parts.push("all_day = :all_day");
        params.push((":all_day", &all_day_int));
    }
    if patch.location.is_set_or_clear() {
        set_parts.push("location = :location");
        params.push((":location", &location_bind));
    }
    if patch.url.is_set_or_clear() {
        set_parts.push("url = :url");
        params.push((":url", &url_bind));
    }
    if patch.color.is_set_or_clear() {
        set_parts.push("color = :color");
        params.push((":color", &color_bind));
    }
    if patch.event_type.is_set_or_clear() {
        set_parts.push("event_type = :event_type");
        params.push((":event_type", &event_type_bind));
    }
    if patch.person_name.is_set_or_clear() {
        set_parts.push("person_name = :person_name");
        params.push((":person_name", &person_name_bind));
    }

    // gate on `:version > calendar_events.version` so a
    // local update racing an in-flight sync apply that already landed
    // a newer remote version cannot blindly overwrite the cluster's
    // state. Mirrors the LWW guard added to apply_task_update and the
    // existing list/preference paths.
    let sql = format!(
        "UPDATE calendar_events SET {} WHERE id = :event_id AND :version > version RETURNING 1",
        set_parts.join(", ")
    );
    // `RETURNING 1` + `query_row` lets `execute_lww_update` translate
    // the LWW miss (`QueryReturnedNoRows`) into `StaleVersion`,
    // retiring the duplicated `if rows == 0 { … }` branches every
    // caller carry.
    execute_lww_update(
        conn,
        &sql,
        params.as_slice(),
        ENTITY_CALENDAR_EVENT,
        patch.event_id,
    )?;

    // Exceptions live in `calendar_event_recurrence_exceptions`
    // since #4585. When the patch carries an explicit
    // `recurrence_exceptions` change, replace the per-event
    // registry from the wire JSON form. `Patch::Clear` drops every
    // row; `Patch::Set("[...]")` rewrites the set; `Patch::Unset`
    // leaves the registry untouched. The replace runs after the
    // LWW gate accepted the UPDATE, so a stale-version patch
    // cannot reach this branch (the helper returns early on
    // `StaleVersion`).
    if patch.recurrence_exceptions.is_set_or_clear() {
        let bind: Option<&str> = patch.recurrence_exceptions.as_bind_value().copied();
        crate::recurrence_exceptions::replace_event_exceptions_from_json(
            conn,
            patch.event_id,
            bind,
        )?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

pub fn delete_calendar_event_lww(
    conn: &Connection,
    id: &str,
    version: &str,
) -> Result<usize, StoreError> {
    crate::repositories::lww_delete::execute_lww_delete_by_id(
        conn,
        "calendar_events",
        "id",
        ENTITY_CALENDAR_EVENT,
        id,
        version,
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
