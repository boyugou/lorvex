//! Input normalization + validation for a single-row task update.
//!
//! [`prepare_task_update`] reads the raw [`TaskUpdateInput`] and a
//! pre-loaded `before` snapshot, runs every shape / length / id-format
//! / count / cross-field guard the canonical `update_task` mutation
//! requires, and returns a [`PreparedTaskUpdate`] the downstream effect
//! modules read without re-validating.

use lorvex_domain::naming::{
    TaskStatus, STATUS_CANCELLED, STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY,
};
use lorvex_domain::{Patch, TaskId};
use lorvex_store::repositories::task::write;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

use super::super::input::TaskUpdateInput;
use super::dependencies::{
    apply_dependency_patch, find_task_dependencies, normalize_dependency_ids,
};
use super::tags::{apply_tag_patch, find_task_tags};

pub(crate) const MAX_AI_NOTES_LENGTH: usize = 50_000;

pub(in crate::task_update) struct PreparedTaskUpdate {
    pub(in crate::task_update) new_status: Option<String>,
    pub(in crate::task_update) new_depends_on: Option<Vec<String>>,
    pub(in crate::task_update) changed_deps: bool,
    pub(in crate::task_update) new_tags: Option<Vec<String>>,
    pub(in crate::task_update) changed_tags: bool,
    pub(in crate::task_update) new_recurrence: Patch<String>,
    pub(in crate::task_update) pending_due_date_patch: Patch<String>,
    pub(in crate::task_update) pending_due_time_patch: Patch<String>,
    pub(in crate::task_update) title: Option<String>,
    pub(in crate::task_update) body: Patch<String>,
    pub(in crate::task_update) raw_input: Patch<String>,
    pub(in crate::task_update) ai_notes: Patch<String>,
    pub(in crate::task_update) list_id: Patch<String>,
    pub(in crate::task_update) priority: Patch<i64>,
    pub(in crate::task_update) estimated_minutes: Patch<i64>,
    pub(in crate::task_update) planned_date: Patch<String>,
    pub(in crate::task_update) before_status: TaskStatus,
}

pub(in crate::task_update) fn prepare_task_update(
    conn: &Connection,
    update: &TaskUpdateInput,
    before: &Value,
    before_status: &str,
) -> Result<PreparedTaskUpdate, StoreError> {
    validate_task_id_shape(&update.id, "id")?;
    let list_id_patch = reject_clear_string_patch(
        &update.list_id,
        "list_id",
        "Tasks must belong to a real list. Choose a list instead of clearing list_id.",
    )?;
    validate_list_exists(conn, list_id_patch.as_deref().as_bind_value().copied())?;
    let normalized_status = match &update.status {
        Patch::Unset => None,
        Patch::Clear => {
            return Err(StoreError::Validation(
                "status cannot be cleared. Expected one of: open, completed, cancelled, someday"
                    .to_string(),
            ));
        }
        Patch::Set(value) => Some(normalize_status(value)?.to_string()),
    };
    // `Patch::Set(v)` may collapse to `Patch::Clear` when normalization
    // returns `None` (priority 0 sentinel), so the `Set` arm cannot use
    // `Patch::map` directly — keep the explicit triage.
    let normalized_priority: Patch<u8> = match &update.priority {
        Patch::Set(value) => match crate::task_create::normalize_task_priority(Some(*value))? {
            Some(v) => Patch::Set(v),
            None => Patch::Clear,
        },
        Patch::Clear => Patch::Clear,
        Patch::Unset => Patch::Unset,
    };
    let before_status_typed = write::parse_task_status_for_update(&update.id, before_status)?;

    validate_count(
        update.tags_set.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_TAGS,
        "tags",
    )?;
    validate_count(
        update.tags_add.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_TAGS,
        "tags",
    )?;
    validate_count(
        update.tags_remove.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_TAGS,
        "tags",
    )?;
    validate_count(
        update.depends_on.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_DEPENDENCIES,
        "depends_on",
    )?;
    validate_count(
        update.depends_on_add.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_DEPENDENCIES,
        "depends_on_add",
    )?;
    validate_count(
        update.depends_on_remove.as_ref().map(Vec::len).unwrap_or(0),
        lorvex_domain::validation::MAX_TASK_DEPENDENCIES,
        "depends_on_remove",
    )?;
    if update.depends_on.is_some()
        && (update.depends_on_add.is_some() || update.depends_on_remove.is_some())
    {
        return Err(StoreError::Validation(
            "Use either depends_on or depends_on_add/depends_on_remove in one update, not both."
                .to_string(),
        ));
    }
    validate_tags(update.tags_set.as_deref())?;
    validate_tags(update.tags_add.as_deref())?;
    validate_tags(update.tags_remove.as_deref())?;
    if update.tags_set.is_some() && (update.tags_add.is_some() || update.tags_remove.is_some()) {
        return Err(StoreError::Validation(
            "Use either tags_set or tags_add/tags_remove in one update, not both.".to_string(),
        ));
    }
    let changed_deps = update.depends_on.is_some()
        || update.depends_on_add.is_some()
        || update.depends_on_remove.is_some();
    let new_depends_on = if changed_deps {
        let merged = if let Some(replace) = update.depends_on.clone() {
            normalize_dependency_ids(replace)
        } else {
            let current = find_task_dependencies(conn, &TaskId::from_trusted(update.id.clone()))?;
            apply_dependency_patch(
                &current,
                update.depends_on_add.clone(),
                update.depends_on_remove.clone(),
            )
        };
        validate_count(
            merged.len(),
            lorvex_domain::validation::MAX_TASK_DEPENDENCIES,
            "depends_on",
        )?;
        crate::task_create::validate_task_ids_exist(conn, &merged, "depends_on")?;
        Some(merged)
    } else {
        None
    };

    let title = match &update.title {
        Patch::Unset => None,
        Patch::Clear => {
            return Err(StoreError::Validation(
                "task title must not be empty".to_string(),
            ));
        }
        Patch::Set(title) => {
            if title.trim().is_empty() || lorvex_domain::validation::is_visually_empty(title) {
                return Err(StoreError::Validation(
                    "task title must not be empty".to_string(),
                ));
            }
            lorvex_domain::validation::validate_string_length(
                title,
                "title",
                lorvex_domain::validation::MAX_TITLE_LENGTH,
            )?;
            Some(title.clone())
        }
    };
    validate_nullable_string_length(
        update.body.as_deref().as_bind_value().copied(),
        "body",
        lorvex_domain::validation::MAX_BODY_LENGTH,
    )?;
    validate_nullable_string_length(
        update.ai_notes.as_deref().as_bind_value().copied(),
        "ai_notes",
        MAX_AI_NOTES_LENGTH,
    )?;
    validate_nullable_string_length(
        update.raw_input.as_deref().as_bind_value().copied(),
        "raw_input",
        lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
    )?;
    let pending_due_date_patch =
        normalize_nullable_due_date_patch_for_conn(conn, update.due_date.clone())?;
    let pending_due_time_patch = update.due_time.clone().try_map(|value| {
        lorvex_domain::validation::validate_time_format(&value)?;
        Ok::<_, StoreError>(value)
    })?;
    validate_effective_due_pair(before, &pending_due_date_patch, &pending_due_time_patch)?;

    let estimated_minutes = update.estimated_minutes.clone().try_map(|minutes| {
        let normalized = i64::from(minutes);
        lorvex_domain::validation::validate_estimated_minutes(normalized)?;
        Ok::<_, StoreError>(normalized)
    })?;
    // `Patch::Set(rule)` may collapse to `Patch::Clear` when the
    // canonicalizer returns `None` (empty/whitespace rule normalizes to
    // "no recurrence") — explicit triage rather than `Patch::map`.
    let new_recurrence = match &update.recurrence {
        Patch::Set(rule) => {
            let raw = rule.to_string();
            match lorvex_domain::validation::normalize_task_recurrence(&raw)? {
                Some(canonical) => Patch::Set(canonical),
                None => Patch::Clear,
            }
        }
        Patch::Clear => Patch::Clear,
        Patch::Unset => Patch::Unset,
    };
    let planned_date =
        normalize_nullable_due_date_patch_for_conn(conn, update.planned_date.clone())?;
    let changed_tags =
        update.tags_set.is_some() || update.tags_add.is_some() || update.tags_remove.is_some();
    let new_tags = if changed_tags {
        let current_tags = find_task_tags(conn, &TaskId::from_trusted_str(&update.id))?;
        let merged = apply_tag_patch(
            &current_tags,
            update.tags_set.clone(),
            update.tags_add.clone(),
            update.tags_remove.clone(),
        );
        validate_count(
            merged.len(),
            lorvex_domain::validation::MAX_TASK_TAGS,
            "tags",
        )?;
        Some(merged)
    } else {
        None
    };

    Ok(PreparedTaskUpdate {
        new_status: normalized_status,
        new_depends_on,
        changed_deps,
        new_tags,
        changed_tags,
        new_recurrence,
        pending_due_date_patch,
        pending_due_time_patch,
        title,
        body: update.body.clone(),
        raw_input: update.raw_input.clone(),
        ai_notes: update.ai_notes.clone(),
        list_id: list_id_patch,
        priority: normalized_priority.map(i64::from),
        estimated_minutes,
        planned_date,
        before_status: before_status_typed,
    })
}

pub(crate) fn validate_task_id_shape(id: &str, field_name: &'static str) -> Result<(), StoreError> {
    lorvex_domain::entity_id::parse_id_with_sentinel(id, field_name, None)
        .map(|_| ())
        .map_err(|error| StoreError::Validation(error.to_string()))
}

/// Reject `Patch::Clear` for fields whose target column is NOT NULL.
/// Returns the patch unchanged so the caller can keep threading it.
fn reject_clear_string_patch(
    patch: &Patch<String>,
    field_name: &'static str,
    message: &'static str,
) -> Result<Patch<String>, StoreError> {
    if patch.is_clear() {
        let _ = field_name; // included in the static message for clarity
        return Err(StoreError::Validation(message.to_string()));
    }
    Ok(patch.clone())
}

fn validate_list_exists(conn: &Connection, list_id: Option<&str>) -> Result<(), StoreError> {
    let Some(list_id) = list_id else {
        return Ok(());
    };
    if list_id.trim().is_empty() {
        return Err(StoreError::Validation(
            "list_id must not be empty".to_string(),
        ));
    }
    validate_task_id_shape(list_id, "list_id")?;
    let exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM lists WHERE id = ?1)",
        [list_id],
        |row| row.get(0),
    )?;
    if !exists {
        return Err(StoreError::Validation(format!(
            "list '{list_id}' does not exist"
        )));
    }
    Ok(())
}

fn normalize_status(status: &str) -> Result<&'static str, StoreError> {
    match status {
        STATUS_OPEN => Ok(STATUS_OPEN),
        STATUS_COMPLETED => Ok(STATUS_COMPLETED),
        STATUS_CANCELLED => Ok(STATUS_CANCELLED),
        STATUS_SOMEDAY => Ok(STATUS_SOMEDAY),
        other => Err(StoreError::Validation(format!(
            "Invalid status '{other}'. Expected one of: open, completed, cancelled, someday"
        ))),
    }
}

fn normalize_nullable_due_date_patch_for_conn(
    conn: &Connection,
    patch: Patch<String>,
) -> Result<Patch<String>, StoreError> {
    patch.try_map(|value| crate::task_create::normalize_due_date_input_for_conn(conn, value))
}

fn validate_effective_due_pair(
    before: &Value,
    due_date: &Patch<String>,
    due_time: &Patch<String>,
) -> Result<(), StoreError> {
    let effective_due_date = effective_due_component(before, "due_date", due_date);
    let effective_due_time = effective_due_component(before, "due_time", due_time);
    lorvex_domain::time::DueAt::from_optional_str_pair(
        effective_due_date.as_deref(),
        effective_due_time.as_deref(),
    )?;
    Ok(())
}

fn effective_due_component(before: &Value, field: &str, patch: &Patch<String>) -> Option<String> {
    match patch {
        Patch::Set(value) => Some(value.clone()),
        Patch::Clear => None,
        Patch::Unset => before
            .get(field)
            .and_then(Value::as_str)
            .map(str::to_string),
    }
}

fn validate_count(count: usize, max: usize, field_name: &'static str) -> Result<(), StoreError> {
    if count > max {
        return Err(StoreError::Validation(format!(
            "{field_name} supports at most {max} item(s), got {count}"
        )));
    }
    Ok(())
}

fn validate_nullable_string_length(
    value: Option<&str>,
    field_name: &'static str,
    max_len: usize,
) -> Result<(), StoreError> {
    if let Some(value) = value {
        lorvex_domain::validation::validate_string_length(value, field_name, max_len)?;
    }
    Ok(())
}

fn validate_tags(tags: Option<&[String]>) -> Result<(), StoreError> {
    if let Some(tags) = tags {
        for tag in tags {
            lorvex_domain::validation::validate_string_length(
                tag,
                "tag",
                lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH,
            )?;
        }
    }
    Ok(())
}
