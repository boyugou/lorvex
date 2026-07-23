//! Input validation + INSERT row materialization for task create.
//!
//! [`PreparedTaskInsert`] is the validated, normalized row the
//! orchestrator hands to the store layer. [`prepare_task_insert`]
//! is the only constructor — it walks the full validation chain
//! (length limits, priority/date normalization, recurrence transition
//! planning, dependency-cycle check) before producing it.
//!
//! Side modules:
//! - [`super::date_parse`] for flexible `due_date` / `planned_date`
//!   normalization (today/tomorrow/RFC 3339/etc.).
//! - [`crate::recurrence_config`] for recurrence transition planning.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_domain::validation::{
    MAX_BODY_LENGTH, MAX_SHORT_TEXT_LENGTH, MAX_TASK_DEPENDENCIES, MAX_TASK_TAGS, MAX_TITLE_LENGTH,
};
use lorvex_domain::{Patch, TaskId};
use lorvex_store::repositories::task::write::{self, TaskCreateParams};
use lorvex_store::StoreError;
use rusqlite::{params_from_iter, Connection, OptionalExtension};

use super::date_parse::normalize_due_date_input_for_conn;
use super::input::TaskCreateInput;
use crate::dependency_validation::validate_no_dependency_cycle;

const MAX_AI_NOTES_LENGTH: usize = 50_000;

pub struct PreparedTaskInsert {
    pub id: String,
    pub title: String,
    pub depends_on: Vec<String>,
    pub tags: Vec<String>,
    pub(super) body: Option<String>,
    pub(super) raw_input: Option<String>,
    pub(super) ai_notes: Option<String>,
    pub(super) status: String,
    pub(super) list_id: Option<String>,
    pub(super) priority: Option<i64>,
    pub(super) due_date: Option<String>,
    pub(super) due_time: Option<String>,
    pub(super) estimated_minutes: Option<i64>,
    pub(super) recurrence: Option<String>,
    pub(super) recurrence_group_id: Option<String>,
    pub(super) canonical_occurrence_date: Option<String>,
    pub(super) planned_date: Option<String>,
    pub(super) version: String,
    pub(super) now: String,
}

impl PreparedTaskInsert {
    pub fn execute_insert(&self, conn: &Connection) -> Result<(), StoreError> {
        let params = TaskCreateParams::builder(
            &self.id,
            &self.title,
            &self.status,
            &self.version,
            &self.now,
        )
        .body(self.body.as_deref())
        .raw_input(self.raw_input.as_deref())
        .ai_notes(self.ai_notes.as_deref())
        .list_id(self.list_id.as_deref())
        .priority(self.priority)
        .due_date(self.due_date.as_deref())
        .due_time(self.due_time.as_deref())
        .estimated_minutes(self.estimated_minutes)
        .recurrence(self.recurrence.as_deref())
        .recurrence_group_id(self.recurrence_group_id.as_deref())
        .canonical_occurrence_date(self.canonical_occurrence_date.as_deref())
        .planned_date(self.planned_date.as_deref())
        .build()?;
        write::create_task(conn, &params)?;
        Ok(())
    }
}

pub fn prepare_task_insert(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    id: String,
    now: String,
    input: TaskCreateInput,
) -> Result<PreparedTaskInsert, StoreError> {
    let TaskCreateInput {
        title,
        list_id,
        priority,
        due_date,
        due_time,
        estimated_minutes,
        tags,
        body,
        raw_input,
        ai_notes,
        depends_on,
        reminders,
        recurrence_json,
        planned_date,
        completed: _,
        status,
    } = input;

    // For create, `Patch::Unset` and `Patch::Clear` collapse to the
    // same NULL-on-insert behavior the writer needs. Project every
    // Patch<T> down to Option<T> immediately so the rest of the
    // function stays uniform.
    let list_id = patch_to_option(list_id);
    let priority = patch_to_option(priority);
    let due_date = patch_to_option(due_date);
    let due_time = patch_to_option(due_time);
    let estimated_minutes = patch_to_option(estimated_minutes);
    let body = patch_to_option(body);
    let raw_input = patch_to_option(raw_input);
    let ai_notes = patch_to_option(ai_notes);
    let recurrence_json = patch_to_option(recurrence_json);
    let planned_date = patch_to_option(planned_date);
    let status = patch_to_option(status);

    let initial_status = match status.as_deref() {
        None | Some(STATUS_OPEN) => STATUS_OPEN.to_string(),
        Some(STATUS_SOMEDAY) => STATUS_SOMEDAY.to_string(),
        Some(other) => {
            return Err(StoreError::Validation(format!(
                "invalid initial status for task create: '{other}' (only 'open' or 'someday' accepted)"
            )));
        }
    };

    let title = lorvex_domain::sanitize_user_text(&title);
    let body = body.map(|value| lorvex_domain::sanitize_user_text(&value));
    let ai_notes = ai_notes.map(|value| lorvex_domain::sanitize_user_text(&value));
    let raw_input = raw_input.map(|value| lorvex_domain::sanitize_user_text(&value));
    let tags = tags.map(|values| {
        values
            .into_iter()
            .map(|value| lorvex_domain::sanitize_user_text(&value))
            .collect::<Vec<_>>()
    });

    if title.trim().is_empty() || lorvex_domain::validation::is_visually_empty(&title) {
        return Err(StoreError::Validation(
            "task title must not be empty".to_string(),
        ));
    }
    lorvex_domain::validation::validate_string_length(&title, "title", MAX_TITLE_LENGTH)?;
    lorvex_domain::validation::validate_optional_string_length(
        body.as_deref(),
        "body",
        MAX_BODY_LENGTH,
    )?;
    lorvex_domain::validation::validate_optional_string_length(
        ai_notes.as_deref(),
        "ai_notes",
        MAX_AI_NOTES_LENGTH,
    )?;
    lorvex_domain::validation::validate_optional_string_length(
        raw_input.as_deref(),
        "raw_input",
        MAX_SHORT_TEXT_LENGTH,
    )?;
    validate_tags(tags.as_deref())?;
    validate_count(
        tags.as_ref().map(Vec::len).unwrap_or(0),
        MAX_TASK_TAGS,
        "tags",
    )?;
    validate_count(
        depends_on.as_ref().map(Vec::len).unwrap_or(0),
        MAX_TASK_DEPENDENCIES,
        "depends_on",
    )?;
    validate_count(
        reminders.as_ref().map(Vec::len).unwrap_or(0),
        50,
        "reminders",
    )?;
    drop(reminders);

    let recurrence = recurrence_json
        .as_deref()
        .map(lorvex_domain::validation::normalize_task_recurrence)
        .transpose()?
        .flatten();
    let list_id = Some(lorvex_store::resolve_required_task_list_id(
        conn,
        list_id.as_deref(),
    )?);
    if let Some(ref deps) = depends_on {
        validate_task_ids_exist(conn, deps, "depends_on")?;
    }
    let id_typed = TaskId::from_trusted(id.clone());
    validate_no_dependency_cycle(conn, &id_typed, depends_on.as_deref().unwrap_or(&[]))?;

    let priority = normalize_task_priority(priority)?;
    let due_date = due_date
        .map(|value| normalize_due_date_input_for_conn(conn, value))
        .transpose()?;
    let planned_date = planned_date
        .map(|value| normalize_due_date_input_for_conn(conn, value))
        .transpose()?;
    if let Some(ref value) = due_time {
        lorvex_domain::validation::validate_time_format(value)?;
    }

    let tags_normalized = tags
        .map(|values| normalize_tags(values.iter().map(String::as_str)))
        .unwrap_or_default();
    let version = hlc.next_version_string();

    let mut due_date = due_date;
    let old_state = crate::recurrence_config::RecurrenceState {
        recurrence: None,
        recurrence_group_id: None,
        canonical_occurrence_date: None,
        due_date: due_date.clone(),
        due_time: due_time.clone(),
    };
    let today = crate::timezone::today_ymd_for_conn(conn)?;
    let (_transition, rec_actions) = crate::recurrence_config::plan_recurrence_transition(
        &old_state,
        recurrence.as_deref(),
        &today,
    );
    let recurrence_group_id = rec_actions.set_recurrence_group_id;
    let canonical_occurrence_date = rec_actions
        .set_canonical_occurrence_date
        .as_bind_value()
        .cloned();
    if let Some(ref fallback_due) = rec_actions.set_due_date {
        due_date = Some(fallback_due.clone());
    }

    Ok(PreparedTaskInsert {
        id,
        title,
        depends_on: depends_on.unwrap_or_default(),
        tags: tags_normalized,
        body,
        raw_input,
        ai_notes,
        status: initial_status,
        list_id,
        priority: priority.map(i64::from),
        due_date,
        due_time,
        estimated_minutes: estimated_minutes.map(i64::from),
        recurrence,
        recurrence_group_id,
        canonical_occurrence_date,
        planned_date,
        version,
        now,
    })
}

/// Collapse a `Patch<T>` down to `Option<T>` for the create path.
///
/// At create time `Patch::Unset` (field absent) and `Patch::Clear`
/// (explicit JSON null) are semantically equivalent — both leave the
/// column NULL on insert. The surrounding workflow exposes the
/// three-state shape so it matches `TaskUpdateInput`, but the writer
/// only consumes the lowered `Option<T>` form.
fn patch_to_option<T>(patch: Patch<T>) -> Option<T> {
    match patch {
        Patch::Unset | Patch::Clear => None,
        Patch::Set(value) => Some(value),
    }
}

pub(crate) fn normalize_task_priority(value: Option<u8>) -> Result<Option<u8>, StoreError> {
    match value {
        None => Ok(None),
        Some(1..=3) => Ok(value),
        Some(other) => Err(StoreError::Validation(format!(
            "Invalid priority '{other}'. Expected one of: 1, 2, 3"
        ))),
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

fn validate_tags(tags: Option<&[String]>) -> Result<(), StoreError> {
    if let Some(tags) = tags {
        for tag in tags {
            lorvex_domain::validation::validate_string_length(tag, "tag", MAX_SHORT_TEXT_LENGTH)?;
        }
    }
    Ok(())
}

fn normalize_tags<'a>(tags: impl IntoIterator<Item = &'a str>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for tag in tags {
        let normalized = tag.trim().to_lowercase();
        if !normalized.is_empty() && seen.insert(normalized.clone()) {
            out.push(normalized);
        }
    }
    out
}

pub(crate) fn validate_task_ids_exist(
    conn: &Connection,
    task_ids: &[String],
    field_name: &'static str,
) -> Result<(), StoreError> {
    for id in task_ids {
        if id.trim().is_empty() {
            return Err(StoreError::Validation(format!(
                "{field_name} contains an empty task ID"
            )));
        }
        if let Err(error) = lorvex_domain::entity_id::parse_id_with_sentinel(id, field_name, None) {
            return Err(StoreError::Validation(error.to_string()));
        }
    }
    if task_ids.is_empty() {
        return Ok(());
    }
    let deduped = task_ids
        .iter()
        .map(String::as_str)
        .collect::<std::collections::BTreeSet<_>>();
    let placeholders = lorvex_domain::sql_csv_placeholders(deduped.len());
    let sql = format!("SELECT id FROM tasks WHERE id IN ({placeholders})");
    let params = params_from_iter(deduped.iter().copied());
    let existing = conn
        .prepare_cached(&sql)?
        .query_map(params, |row| row.get::<_, String>(0))?
        .collect::<Result<std::collections::HashSet<_>, _>>()?;
    if let Some(missing) = task_ids
        .iter()
        .find(|task_id| !existing.contains(task_id.as_str()))
    {
        return Err(StoreError::Validation(format!(
            "{field_name} references non-existent task '{missing}'"
        )));
    }
    Ok(())
}

pub(super) fn build_create_summary(
    conn: &Connection,
    prepared: &PreparedTaskInsert,
    completed: bool,
) -> Result<String, StoreError> {
    let list_name = match prepared.list_id.as_ref() {
        Some(task_list_id) => conn
            .query_row(
                "SELECT name FROM lists WHERE id = ?1",
                [task_list_id],
                |row| row.get::<_, String>(0),
            )
            .optional()?,
        None => None,
    };
    let list_part = list_name
        .as_ref()
        .map(|name| format!(" in {name}"))
        .unwrap_or_default();
    let due_part = prepared
        .due_date
        .as_ref()
        .map(|date| format!(", due {date}"))
        .unwrap_or_default();
    let completed_part = if completed { " (completed)" } else { "" };
    Ok(format!(
        "Created task '{}'{}{}{}",
        prepared.title, list_part, due_part, completed_part
    ))
}
