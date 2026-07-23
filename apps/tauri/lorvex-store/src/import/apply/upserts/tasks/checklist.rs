use rusqlite::Connection;

use lorvex_domain::checklist::{
    extract_markdown_checklist, validate_task_checklist_item_count,
    validate_task_checklist_item_text,
};
use lorvex_domain::sanitize_user_text;

use super::super::should_replace_versioned;
use crate::import::apply::helpers::{
    invalid_payload, optional_i64_field, optional_string_field, optional_sync_timestamp_field,
    required_string_field,
};
use crate::import::ImportError;

// ---------------------------------------------------------------------------
// Embedded task checklist materialization
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub(super) struct EmbeddedTaskChecklistItem {
    id: String,
    position: i64,
    text: String,
    completed_at: Option<String>,
    version: String,
    created_at: String,
    updated_at: String,
}

pub(super) fn parse_embedded_task_checklist_items(
    payload: &serde_json::Value,
    task_id: &lorvex_domain::TaskId,
    task_version: &str,
    task_created_at: &str,
    task_updated_at: &str,
) -> Result<Option<Vec<EmbeddedTaskChecklistItem>>, ImportError> {
    let Some(checklist_items) = payload.get("checklist_items") else {
        return Ok(None);
    };
    let Some(checklist_items) = checklist_items.as_array() else {
        if checklist_items.is_null() {
            return Ok(Some(Vec::new()));
        }
        return Err(invalid_payload(
            "task payload.checklist_items must be an array when present",
        ));
    };
    validate_task_checklist_item_count(checklist_items.len())
        .map_err(|error| invalid_payload(format!("task payload.checklist_items {error}")))?;

    checklist_items
        .iter()
        .enumerate()
        .map(|(index, item)| {
            let context = format!("task payload.checklist_items[{index}]");
            let embedded_task_id = optional_string_field(item, "task_id", &context)?
                .unwrap_or_else(|| task_id.as_str().to_string());
            if embedded_task_id.as_str() != task_id.as_str() {
                return Err(invalid_payload(format!(
                    "{context}.task_id must match parent task id `{task_id}`"
                )));
            }
            let text = sanitize_user_text(&required_string_field(item, "text", &context)?);
            validate_task_checklist_item_text(&text)
                .map_err(|error| invalid_payload(format!("{context}.text {error}")))?;
            Ok(EmbeddedTaskChecklistItem {
                id: optional_string_field(item, "id", &context)?
                    .unwrap_or_else(|| format!("{task_id}:checklist:{index}")),
                position: optional_i64_field(item, "position", &context)?.unwrap_or(index as i64),
                text,
                completed_at: optional_sync_timestamp_field(item, "completed_at", &context)?,
                version: optional_string_field(item, "version", &context)?
                    .unwrap_or_else(|| task_version.to_string()),
                created_at: optional_sync_timestamp_field(item, "created_at", &context)?
                    .unwrap_or_else(|| task_created_at.to_string()),
                updated_at: optional_sync_timestamp_field(item, "updated_at", &context)?
                    .unwrap_or_else(|| task_updated_at.to_string()),
            })
        })
        .collect::<Result<Vec<_>, _>>()
        .map(Some)
}

/// Materialize the embedded `checklist_items` payload onto the
/// `task_checklist_items` table.
///
/// `task_checklist_items` carries its own
/// HLC `version` per row and is also synced as an independent child
/// entity (`ENTITY_TASK_CHECKLIST_ITEM` in `dispatch_child`). The
/// previous shape blindly `DELETE`d every existing row before
/// re-inserting from the embedded array — but a peer that had toggled
/// a single item locally (a per-item envelope) and then received a
/// stale aggregate-task envelope would silently lose its newer local
/// edit. The fix: gate every per-row replacement through the same LWW
/// check (`should_replace_versioned`) the per-entity dispatch uses,
/// AND only delete rows whose local version is strictly older than the
/// embedded payload's version. Items the payload does not reference
/// are deleted only when no peer has a newer version of them on this
/// device — i.e. when their version is `<=` the parent task's
/// embedded version envelope.
pub(super) fn materialize_task_checklist_items(
    conn: &Connection,
    task_id: &lorvex_domain::TaskId,
    payload: &serde_json::Value,
    original_body: Option<&str>,
    task_version: &str,
    task_created_at: &str,
    task_updated_at: &str,
) -> Result<(), ImportError> {
    let items = if let Some(items) = parse_embedded_task_checklist_items(
        payload,
        task_id,
        task_version,
        task_created_at,
        task_updated_at,
    )? {
        items
    } else {
        match original_body {
            None => Vec::new(),
            Some(body) => {
                let extracted = extract_markdown_checklist(body);
                validate_task_checklist_item_count(extracted.items.len()).map_err(|error| {
                    invalid_payload(format!("task payload.checklist_items {error}"))
                })?;
                extracted
                    .items
                    .iter()
                    .enumerate()
                    .map(|(index, item)| EmbeddedTaskChecklistItem {
                        id: format!("{task_id}:checklist:{index}"),
                        position: item.position,
                        text: item.text.clone(),
                        completed_at: item.completed.then(|| task_updated_at.to_string()),
                        version: task_version.to_string(),
                        created_at: task_created_at.to_string(),
                        updated_at: task_updated_at.to_string(),
                    })
                    .collect()
            }
        }
    };

    // Per-item LWW upsert: only replace rows whose local version is
    // strictly older than the incoming embedded item, and only insert
    // rows that don't already exist with a newer version. A locally-
    // edited item the aggregate envelope hasn't seen yet is preserved.
    let payload_ids: std::collections::BTreeSet<&str> =
        items.iter().map(|item| item.id.as_str()).collect();

    // Lift the per-item INSERT and UPDATE prepares out of the loop —
    // an aggregate envelope with N checklist items pays one parse per
    // statement instead of N. Both statements live across the per-item
    // dispatch so we cache them once in the per-call scope.
    let mut insert_stmt = conn
        .prepare_cached(
            "INSERT INTO task_checklist_items (
                id, task_id, position, text, completed_at, version, created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        )
        .map_err(ImportError::from)?;
    let mut update_stmt = conn
        .prepare_cached(
            "UPDATE task_checklist_items
             SET task_id = ?2, position = ?3, text = ?4, completed_at = ?5,
                 version = ?6, created_at = ?7, updated_at = ?8
             WHERE id = ?1",
        )
        .map_err(ImportError::from)?;
    for item in &items {
        match should_replace_versioned(conn, "task_checklist_items", "id", &item.id, &item.version)?
        {
            None => {
                insert_stmt.execute(rusqlite::params![
                    item.id,
                    task_id,
                    item.position,
                    item.text,
                    item.completed_at,
                    item.version,
                    item.created_at,
                    item.updated_at,
                ])?;
            }
            Some(true) => {
                update_stmt.execute(rusqlite::params![
                    item.id,
                    task_id,
                    item.position,
                    item.text,
                    item.completed_at,
                    item.version,
                    item.created_at,
                    item.updated_at,
                ])?;
            }
            Some(false) => {
                // Existing local version is newer — preserve the local row.
            }
        }
    }
    drop(insert_stmt);
    drop(update_stmt);

    // Delete the rows the embedded payload no longer references, but
    // only if their local version is `<=` the parent task's embedded
    // version envelope. A row whose version is strictly newer than
    // the parent envelope was authored by a per-item envelope this
    // aggregate has not yet observed; it must survive.
    let local_rows: Vec<(String, String)> = {
        let mut stmt = conn
            .prepare_cached("SELECT id, version FROM task_checklist_items WHERE task_id = ?1")
            .map_err(ImportError::from)?;
        let rows: Vec<(String, String)> = stmt
            .query_map([task_id], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(ImportError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(ImportError::from)?;
        rows
    };

    let task_hlc = lorvex_domain::hlc::Hlc::parse(task_version).map_err(|error| {
        invalid_payload(format!(
            "task payload.checklist_items: parent task `{task_id}` has invalid HLC version: {error}"
        ))
    })?;
    let mut delete_stmt = conn
        .prepare_cached("DELETE FROM task_checklist_items WHERE id = ?1")
        .map_err(ImportError::from)?;
    for (id, local_version) in local_rows {
        if payload_ids.contains(id.as_str()) {
            continue;
        }
        let local_hlc =
            lorvex_domain::hlc::Hlc::parse(local_version.as_str()).map_err(|error| {
                invalid_payload(format!(
                    "local task_checklist_items.id `{id}` has invalid HLC version: {error}"
                ))
            })?;
        if local_hlc <= task_hlc {
            delete_stmt.execute([id.as_str()])?;
        }
        // else: the local row was authored by a per-item envelope newer
        // than the aggregate task envelope; preserve it until the
        // task envelope catches up.
    }
    Ok(())
}
