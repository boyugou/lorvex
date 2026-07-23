//! Foreign-key preflight for inbound envelope apply and shadow promotion.

use rusqlite::Connection;

use lorvex_domain::naming;

use super::super::ApplyError;
use crate::composite_edge::split_composite_edge_id;

type FkResult = Result<Option<(naming::EntityKind, String)>, ApplyError>;

fn payload_object(payload: &str) -> Result<serde_json::Value, ApplyError> {
    match serde_json::from_str::<serde_json::Value>(payload) {
        Ok(serde_json::Value::Object(map)) => Ok(serde_json::Value::Object(map)),
        Ok(_) => Err(ApplyError::InvalidPayload(
            "sync payload must be a JSON object".to_string(),
        )),
        Err(e) => Err(ApplyError::InvalidPayload(format!(
            "malformed sync payload JSON: {e}"
        ))),
    }
}

fn required_str<'a>(
    payload: &'a serde_json::Value,
    entity_type: &str,
    field: &str,
) -> Result<&'a str, ApplyError> {
    payload.get(field).and_then(|v| v.as_str()).ok_or_else(|| {
        ApplyError::InvalidPayload(format!(
            "invalid {entity_type} payload: missing string field {field}"
        ))
    })
}

// The edge FK preflight always derives FK targets from
// `entity_id` (canonical `{a}:{b}`) rather than the payload, so
// every edge uses entity_id parts for the existence checks and
// additionally requires the payload FK fields to agree with
// entity_id. Parsing payload instead of entity_id would let
// a malformed peer envelope whose payload disagrees with
// entity_id slip past the preflight and hit the SQL FK
// constraint at INSERT time, blocking the apply batch under
// StrictAtomic.
fn split_edge_id<'a>(
    entity_type: &str,
    entity_id: &'a str,
) -> Result<(&'a str, &'a str), ApplyError> {
    split_composite_edge_id(entity_id).map_err(|err| {
        ApplyError::InvalidPayload(format!("edge {entity_type} entity_id invalid: {err}"))
    })
}

fn require_edge_field_matches(
    entity_type: &str,
    val: &serde_json::Value,
    field: &str,
    expected: &str,
) -> Result<(), ApplyError> {
    if let Some(actual) = val.get(field).and_then(|v| v.as_str()) {
        if actual != expected {
            return Err(ApplyError::InvalidPayload(format!(
                "edge {entity_type} payload.{field} {actual:?} does not match \
                 entity_id half {expected:?} — payload-vs-entity_id mismatch"
            )));
        }
    }
    Ok(())
}

/// Check FK dependencies for an entity/edge before INSERT.
///
/// Returns `Some((missing_entity_type, missing_entity_id))` if a required
/// FK target doesn't exist locally. Returns `None` if all deps are present.
pub(crate) fn check_fk_dependencies(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    payload: &str,
) -> FkResult {
    let val = payload_object(payload)?;
    // dispatch on `EntityKind` so every FK-preflight
    // arm is enumerated against the authoritative variant set.
    // Unrecognized strings fall through to the same "no FK preflight"
    // no-op the legacy `_ => {}` arm produced.
    let Some(kind) = naming::EntityKind::parse(entity_type) else {
        return Ok(None);
    };
    match kind {
        naming::EntityKind::TaskTag => check_task_tag_edge(conn, entity_type, entity_id, &val),
        naming::EntityKind::TaskDependency => {
            check_task_dependency_edge(conn, entity_type, entity_id, &val)
        }
        naming::EntityKind::TaskCalendarEventLink => {
            check_task_calendar_event_link_edge(conn, entity_type, entity_id, &val)
        }
        naming::EntityKind::HabitCompletion => {
            check_habit_completion_edge(conn, entity_type, entity_id, &val)
        }
        naming::EntityKind::TaskReminder | naming::EntityKind::TaskChecklistItem => {
            check_task_child_parent(conn, entity_type, &val)
        }
        naming::EntityKind::HabitReminderPolicy => {
            check_habit_reminder_policy_parent(conn, entity_type, &val)
        }
        naming::EntityKind::Task => check_task_list_parent(conn, &val),
        // Other aggregate roots, audit stream, and local-only kinds:
        // no FK preflight needed.
        naming::EntityKind::List
        | naming::EntityKind::Tag
        | naming::EntityKind::Habit
        | naming::EntityKind::CalendarEvent
        | naming::EntityKind::Preference
        | naming::EntityKind::Memory
        | naming::EntityKind::MemoryRevision
        | naming::EntityKind::DailyReview
        | naming::EntityKind::CurrentFocus
        | naming::EntityKind::FocusSchedule
        | naming::EntityKind::CalendarSubscription
        | naming::EntityKind::AiChangelog
        | naming::EntityKind::TaskProviderEventLink
        | naming::EntityKind::DeviceState
        | naming::EntityKind::SavedQuery
        | naming::EntityKind::ImportSession => Ok(None),
    }
}

fn check_task_tag_edge(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    val: &serde_json::Value,
) -> FkResult {
    let (task_id, tag_id) = split_edge_id(entity_type, entity_id)?;
    require_edge_field_matches(entity_type, val, "task_id", task_id)?;
    require_edge_field_matches(entity_type, val, "tag_id", tag_id)?;
    if !row_exists(conn, "tasks", "id", task_id)? {
        return Ok(Some((naming::EntityKind::Task, task_id.to_string())));
    }
    if !row_exists(conn, "tags", "id", tag_id)? {
        return Ok(Some((naming::EntityKind::Tag, tag_id.to_string())));
    }
    Ok(None)
}

fn check_task_dependency_edge(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    val: &serde_json::Value,
) -> FkResult {
    let (task_id, depends_on_task_id) = split_edge_id(entity_type, entity_id)?;
    require_edge_field_matches(entity_type, val, "task_id", task_id)?;
    require_edge_field_matches(entity_type, val, "depends_on_task_id", depends_on_task_id)?;
    if !row_exists(conn, "tasks", "id", task_id)? {
        return Ok(Some((naming::EntityKind::Task, task_id.to_string())));
    }
    if !row_exists(conn, "tasks", "id", depends_on_task_id)? {
        return Ok(Some((
            naming::EntityKind::Task,
            depends_on_task_id.to_string(),
        )));
    }
    Ok(None)
}

fn check_task_calendar_event_link_edge(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    val: &serde_json::Value,
) -> FkResult {
    let (task_id, event_id) = split_edge_id(entity_type, entity_id)?;
    require_edge_field_matches(entity_type, val, "task_id", task_id)?;
    require_edge_field_matches(entity_type, val, "calendar_event_id", event_id)?;
    if !row_exists(conn, "tasks", "id", task_id)? {
        return Ok(Some((naming::EntityKind::Task, task_id.to_string())));
    }
    if !row_exists(conn, "calendar_events", "id", event_id)? {
        return Ok(Some((
            naming::EntityKind::CalendarEvent,
            event_id.to_string(),
        )));
    }
    Ok(None)
}

fn check_habit_completion_edge(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    val: &serde_json::Value,
) -> FkResult {
    let (habit_id, completed_date) = split_edge_id(entity_type, entity_id)?;
    require_edge_field_matches(entity_type, val, "habit_id", habit_id)?;
    require_edge_field_matches(entity_type, val, "completed_date", completed_date)?;
    if !row_exists(conn, "habits", "id", habit_id)? {
        return Ok(Some((naming::EntityKind::Habit, habit_id.to_string())));
    }
    Ok(None)
}

fn check_task_child_parent(
    conn: &Connection,
    entity_type: &str,
    val: &serde_json::Value,
) -> FkResult {
    let task_id = required_str(val, entity_type, "task_id")?;
    if !row_exists(conn, "tasks", "id", task_id)? {
        return Ok(Some((naming::EntityKind::Task, task_id.to_string())));
    }
    Ok(None)
}

fn check_habit_reminder_policy_parent(
    conn: &Connection,
    entity_type: &str,
    val: &serde_json::Value,
) -> FkResult {
    let habit_id = required_str(val, entity_type, "habit_id")?;
    if !row_exists(conn, "habits", "id", habit_id)? {
        return Ok(Some((naming::EntityKind::Habit, habit_id.to_string())));
    }
    Ok(None)
}

/// Task: check list_id FK if present (list may not have synced yet).
/// Empty strings are treated the same as missing — apply_task_upsert
/// will resolve the fallback list in that case.
fn check_task_list_parent(conn: &Connection, val: &serde_json::Value) -> FkResult {
    let list_id = val
        .get("list_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty());
    if let Some(list_id) = list_id {
        if !row_exists(conn, "lists", "id", list_id)? {
            return Ok(Some((naming::EntityKind::List, list_id.to_string())));
        }
    }
    Ok(None)
}

/// Check if a row exists in a table by PK.
fn row_exists(
    conn: &Connection,
    table: &str,
    pk_col: &str,
    pk_val: &str,
) -> Result<bool, rusqlite::Error> {
    // dispatch on the (table, pk_col) pair to a literal
    // SQL string, mirroring the `version_stamp::SimplePkSql` pattern
    // landed for #2857. This eliminates `format!`-interpolated SQL
    // and the runtime `assert_safe_sql_identifier` panic guard at
    // call time. Every caller in this module passes `&'static str`
    // literals so this match is exhaustive in practice; an unknown
    // (table, col) pair surfaces as a clean `InvalidQuery` rather
    // than a panic that DoSes the apply pipeline.
    let sql: &'static str = match (table, pk_col) {
        ("tasks", "id") => "SELECT 1 FROM tasks WHERE id = ?1",
        ("tags", "id") => "SELECT 1 FROM tags WHERE id = ?1",
        ("habits", "id") => "SELECT 1 FROM habits WHERE id = ?1",
        ("lists", "id") => "SELECT 1 FROM lists WHERE id = ?1",
        ("calendar_events", "id") => "SELECT 1 FROM calendar_events WHERE id = ?1",
        _ => return Err(rusqlite::Error::InvalidQuery),
    };
    // route the FK preflight through `prepare_cached`
    // so each per-envelope existence probe re-uses a single prepared
    // statement per (table, pk_col) pair across the whole apply batch.
    let mut stmt = conn.prepare_cached(sql)?;
    let mut rows = stmt.query(rusqlite::params![pk_val])?;
    Ok(rows.next()?.is_some())
}
