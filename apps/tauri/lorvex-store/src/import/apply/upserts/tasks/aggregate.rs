use rusqlite::Connection;

use lorvex_domain::checklist::extract_markdown_checklist;
use lorvex_domain::sanitize_user_text;
use lorvex_domain::validation::{
    validate_body, validate_date_format, validate_estimated_minutes, validate_priority,
    validate_title,
};

use super::super::{should_replace_versioned, UpsertResult};
use super::checklist::{materialize_task_checklist_items, parse_embedded_task_checklist_items};
use crate::import::apply::helpers::{
    optional_i64_field, optional_string_field, optional_sync_timestamp_field, required_i64_field,
    required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_task(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "task payload")?;
    let version = entry.version.as_str();
    let title = sanitize_user_text(&required_string_field(p, "title", "task payload")?);
    // validate imported title length now — not at render
    // time. An oversize field would otherwise sit in the DB and hang
    // every read path that materializes the row.
    validate_title(&title).map_err(|e| {
        ImportError::InvalidPayload(format!("task {id} title failed validation: {e}"))
    })?;
    let status = required_string_field(p, "status", "task payload")?;
    if !matches!(
        status.as_str(),
        "open" | "completed" | "cancelled" | "someday"
    ) {
        return Err(ImportError::InvalidPayload(format!(
            "task {id} status {status:?} must be one of open|completed|cancelled|someday"
        )));
    }
    let created_at = required_sync_timestamp_field(p, "created_at", "task payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "task payload")?;
    let defer_count = required_i64_field(p, "defer_count", "task payload")?;
    let body =
        optional_string_field(p, "body", "task payload")?.map(|value| sanitize_user_text(&value));
    // cap body length at import time too.
    if let Some(ref b) = body {
        validate_body(b).map_err(|e| {
            ImportError::InvalidPayload(format!("task {id} body failed validation: {e}"))
        })?;
    }
    let raw_input = optional_string_field(p, "raw_input", "task payload")?
        .map(|value| sanitize_user_text(&value));
    if let Some(ref input) = raw_input {
        validate_body(input).map_err(|e| {
            ImportError::InvalidPayload(format!("task {id} raw_input failed validation: {e}"))
        })?;
    }
    let ai_notes = optional_string_field(p, "ai_notes", "task payload")?
        .map(|value| sanitize_user_text(&value));
    if let Some(ref notes) = ai_notes {
        validate_body(notes).map_err(|e| {
            ImportError::InvalidPayload(format!("task {id} ai_notes failed validation: {e}"))
        })?;
    }
    let list_id = optional_string_field(p, "list_id", "task payload")?;
    let list_id = match list_id {
        Some(list_id) => {
            let typed_list_id = lorvex_domain::ListId::from_trusted(list_id.clone());
            crate::validate_task_list_exists(conn, &typed_list_id).map_err(ImportError::from)?;
            list_id
        }
        None => {
            return Err(ImportError::InvalidPayload(
                "task payload must reference a real list_id; null-list tasks are a legacy repair state and cannot be imported"
                    .to_string(),
            ));
        }
    };
    // Clamp priority to the valid range (1-3) or null. Out-of-range values
    // from older exports are silently coerced instead of causing a CHECK
    // constraint failure — import should be resilient.
    // still run `validate_priority` first so we surface
    // obviously bogus values (i64::MAX, negatives) in the import
    // findings rather than silently clamping a clearly malformed
    // payload. The subsequent `.clamp(1, 3)` is harmless once the
    // value is known to be in-range.
    let priority = match optional_i64_field(p, "priority", "task payload")? {
        Some(v) => {
            validate_priority(v).map_err(|e| {
                ImportError::InvalidPayload(format!("task {id} priority failed validation: {e}"))
            })?;
            Some(v.clamp(1, 3))
        }
        None => None,
    };
    let due_date = optional_string_field(p, "due_date", "task payload")?;
    if let Some(ref d) = due_date {
        validate_date_format(d).map_err(|e| {
            ImportError::InvalidPayload(format!("task {id} due_date failed validation: {e}"))
        })?;
    }
    let due_time = optional_string_field(p, "due_time", "task payload")?;
    lorvex_domain::time::DueAt::from_optional_str_pair(due_date.as_deref(), due_time.as_deref())
        .map_err(|e| {
            ImportError::InvalidPayload(format!("task {id} due_at failed validation: {e}"))
        })?;
    let estimated_minutes = optional_i64_field(p, "estimated_minutes", "task payload")?;
    if let Some(minutes) = estimated_minutes {
        validate_estimated_minutes(minutes).map_err(|e| {
            ImportError::InvalidPayload(format!(
                "task {id} estimated_minutes failed validation: {e}"
            ))
        })?;
    }
    let recurrence = optional_string_field(p, "recurrence", "task payload")?;
    let recurrence_exceptions = optional_string_field(p, "recurrence_exceptions", "task payload")?;
    let spawned_from = optional_string_field(p, "spawned_from", "task payload")?;
    let recurrence_group_id = optional_string_field(p, "recurrence_group_id", "task payload")?;
    let canonical_occurrence_date =
        optional_string_field(p, "canonical_occurrence_date", "task payload")?;
    let completed_at = optional_sync_timestamp_field(p, "completed_at", "task payload")?;
    let last_deferred_at = optional_sync_timestamp_field(p, "last_deferred_at", "task payload")?;
    let last_defer_reason = optional_string_field(p, "last_defer_reason", "task payload")?
        .map(|value| sanitize_user_text(&value))
        .filter(|reason| !reason.is_empty());
    if let Some(reason) = last_defer_reason.as_deref() {
        if !lorvex_domain::naming::is_valid_defer_reason(reason) {
            return Err(ImportError::InvalidPayload(format!(
                "task {id} last_defer_reason {reason:?} must be one of: {}",
                lorvex_domain::naming::ALL_DEFER_REASONS.join("|")
            )));
        }
    }
    let planned_date = optional_string_field(p, "planned_date", "task payload")?;
    let available_from = optional_string_field(p, "available_from", "task payload")?;
    let recurrence_instance_key =
        optional_string_field(p, "recurrence_instance_key", "task payload")?;
    // preserve Trash state across import. Without
    // round-tripping `archived_at`, importing a backup wipes Trash
    // and re-receiving a task envelope on a peer would too.
    let archived_at = optional_sync_timestamp_field(p, "archived_at", "task payload")?;
    if defer_count < 0 {
        return Err(ImportError::InvalidPayload(format!(
            "task {id} defer_count must be non-negative (got {defer_count})"
        )));
    }
    let typed_task_id = lorvex_domain::TaskId::from_trusted(id.clone());
    let materialized_checklist =
        parse_embedded_task_checklist_items(p, &typed_task_id, version, &created_at, &updated_at)?;
    let normalized_body = match materialized_checklist.as_ref() {
        Some(_) => body.clone(),
        None => body.as_deref().and_then(|body| {
            let extracted = extract_markdown_checklist(body);
            if extracted.items.is_empty() {
                Some(body.to_string())
            } else if extracted.remaining_body.trim().is_empty() {
                None
            } else {
                Some(extracted.remaining_body)
            }
        }),
    };

    let result: UpsertResult = match should_replace_versioned(conn, "tasks", "id", &id, version)? {
        None => {
            conn.execute(
                "INSERT INTO tasks (id, title, body, raw_input, ai_notes,
                 status, list_id,
                 priority, due_date, due_time, estimated_minutes,
                 recurrence, spawned_from, recurrence_group_id,
                 canonical_occurrence_date,
                 created_at, updated_at,
                 completed_at, last_deferred_at, last_defer_reason, planned_date, defer_count,
                 recurrence_instance_key, archived_at, version, available_from)
                VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26)",
                rusqlite::params![
                    id,
                    title,
                    normalized_body.as_deref(),
                    raw_input.as_deref(),
                    ai_notes.as_deref(),
                    status,
                    Some(list_id.as_str()),
                    priority,
                    due_date.as_deref(),
                    due_time.as_deref(),
                    estimated_minutes,
                    recurrence.as_deref(),
                    spawned_from.as_deref(),
                    recurrence_group_id.as_deref(),
                    canonical_occurrence_date.as_deref(),
                    created_at,
                    updated_at,
                    completed_at.as_deref(),
                    last_deferred_at.as_deref(),
                    last_defer_reason.as_deref(),
                    planned_date.as_deref(),
                    defer_count,
                    recurrence_instance_key.as_deref(),
                    archived_at.as_deref(),
                    version,
                    available_from.as_deref(),
                ],
            )?;
            UpsertResult::Created
        }
        Some(true) => {
            conn.execute(
                "UPDATE tasks SET title=?2, body=?3, raw_input=?4, ai_notes=?5,
                 status=?6,
                 list_id=?7, priority=?8, due_date=?9, due_time=?10, estimated_minutes=?11,
                 recurrence=?12,
                 spawned_from=?13, recurrence_group_id=?14,
                 canonical_occurrence_date=?15,
                 created_at=?16, updated_at=?17, completed_at=?18, last_deferred_at=?19,
                 last_defer_reason=?20, planned_date=?21, defer_count=?22,
                 recurrence_instance_key=?23, archived_at=?24, version=?25, available_from=?26
                WHERE id=?1",
                rusqlite::params![
                    id,
                    title,
                    normalized_body.as_deref(),
                    raw_input.as_deref(),
                    ai_notes.as_deref(),
                    status,
                    Some(list_id.as_str()),
                    priority,
                    due_date.as_deref(),
                    due_time.as_deref(),
                    estimated_minutes,
                    recurrence.as_deref(),
                    spawned_from.as_deref(),
                    recurrence_group_id.as_deref(),
                    canonical_occurrence_date.as_deref(),
                    created_at,
                    updated_at,
                    completed_at.as_deref(),
                    last_deferred_at.as_deref(),
                    last_defer_reason.as_deref(),
                    planned_date.as_deref(),
                    defer_count,
                    recurrence_instance_key.as_deref(),
                    archived_at.as_deref(),
                    version,
                    available_from.as_deref(),
                ],
            )?;
            UpsertResult::Updated
        }
        Some(false) => UpsertResult::Skipped,
    };

    match result {
        UpsertResult::Created | UpsertResult::Updated => {
            // EXDATEs landed in `task_recurrence_exceptions`
            // (#4585) — rewrite the per-task registry from the
            // wire-form JSON now that the parent row is settled.
            crate::recurrence_exceptions::replace_task_exceptions_from_json(
                conn,
                typed_task_id.as_str(),
                recurrence_exceptions.as_deref(),
            )?;
            materialize_task_checklist_items(
                conn,
                &typed_task_id,
                p,
                body.as_deref(),
                version,
                &created_at,
                &updated_at,
            )?;
        }
        UpsertResult::Skipped => {}
    }

    Ok(result)
}
