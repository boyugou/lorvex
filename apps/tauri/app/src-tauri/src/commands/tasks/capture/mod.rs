use lorvex_domain::naming::{STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_domain::Patch;
use lorvex_store::repositories::task::write;
use lorvex_workflow::task_create::{self, CreateTaskInput, TaskCreateInput};
use serde::Deserialize;

use crate::error::{AppError, AppResult};

use super::{
    fetch_task_by_id, finalize_task_mutation, get_conn, invariants, link_tag_to_task,
    sync_timestamp_now, with_immediate_transaction, Task,
};
use crate::hlc::with_hlc_session;

#[derive(Default, Deserialize)]
#[serde(default)]
pub struct QuickCaptureRequest {
    pub title: String,
    pub list_id: Option<String>,
    pub due_date: Option<String>,
    pub priority: Option<i64>,
    pub estimated_minutes: Option<i64>,
    pub body: Option<String>,
    pub tags: Option<Vec<String>>,
    pub status: Option<String>,
    /// AI/MCP-captured tasks may pre-populate the original raw input
    /// text and AI notes. The Tauri quick-capture surface plumbs these
    /// through verbatim so capture from external assistants doesn't
    /// silently drop the columns the canonical workflow knows about.
    pub raw_input: Option<String>,
    pub ai_notes: Option<String>,
    pub recurrence_json: Option<String>,
    pub planned_date: Option<String>,
    pub depends_on: Option<Vec<String>>,
    pub reminders: Option<Vec<String>>,
}

#[tauri::command]
pub fn quick_capture(mut request: QuickCaptureRequest) -> Result<Task, String> {
    // list_id is a UUIDv7 — shape-check at the IPC
    // boundary so a malformed id never reaches
    // `resolve_required_task_list_id` (which would only catch
    // missing rows, not a non-UUID shape). Mirrors the per-task-id
    // validators in the sibling command surface.
    // list-id contexts accept the `INBOX_LIST_ID`
    // sentinel; the CLI's `capture --list inbox` invocation now has
    // an end-to-end equivalent on the Tauri IPC surface.
    request.list_id = request
        .list_id
        .take()
        .map(|raw| crate::commands::shared::validate_list_id(&raw, "list_id"))
        .transpose()?;
    quick_capture_inner(request).map_err(String::from)
}

fn quick_capture_inner(request: QuickCaptureRequest) -> AppResult<Task> {
    let conn = get_conn()?;
    let task = quick_capture_with_conn(&conn, request)?;
    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

    // Post-commit Spotlight dispatch. Routed through the
    // shared dispatcher (see `crate::commands::shared::spotlight_dispatch`).
    crate::commands::shared::reindex_task_after_mutation(&conn, task.id.clone());
    Ok(task)
}

/// Testable entry point — same implementation as `quick_capture_inner`
/// but takes an externally-managed connection so unit tests can feed an
/// in-memory DB without going through `get_conn()` + Spotlight side
/// effects.
pub(crate) fn quick_capture_with_conn(
    conn: &rusqlite::Connection,
    request: QuickCaptureRequest,
) -> AppResult<Task> {
    let QuickCaptureRequest {
        title,
        list_id,
        due_date,
        priority,
        estimated_minutes,
        body,
        tags,
        status,
        raw_input,
        ai_notes,
        recurrence_json,
        planned_date,
        depends_on,
        reminders,
    } = request;

    // Unicode hygiene (#2427): scrub bidi overrides / zero-width / line
    // separators and normalize to NFC before validation, so a title made
    // entirely of invisible controls is rejected as empty and a tag cannot
    // be silently split by a ZWSP into two lookup keys.
    let title = lorvex_domain::sanitize_user_text(&title);
    let body = body.map(|s| lorvex_domain::sanitize_user_text(&s));
    let tags = tags.map(|items| {
        let mut seen = std::collections::HashSet::new();
        items
            .into_iter()
            // Unicode hygiene (#2427): scrub each tag before the
            // trim + emptiness check so a tag made entirely of
            // ZWSPs collapses to "" and is dropped.
            .map(|s| lorvex_domain::sanitize_user_text(&s).trim().to_string())
            .filter(|s| !s.is_empty() && seen.insert(lorvex_domain::tag::normalize_lookup_key(s)))
            .collect::<Vec<_>>()
    });

    // Input validation (mirrors MCP server defense-in-depth checks)
    invariants::validation::validate_task_title(&title)?;
    invariants::validation::validate_task_body(body.as_deref())?;
    invariants::validation::validate_task_priority(priority)?;
    invariants::validation::validate_task_tags(tags.as_deref())?;
    if let Some(ref d) = due_date {
        if lorvex_domain::validation::validate_date_format(d).is_err() {
            return Err(crate::error::AppError::Validation(format!(
                "invalid due_date format: {d}"
            )));
        }
    }
    if let Some(mins) = estimated_minutes {
        lorvex_domain::validation::validate_estimated_minutes(mins).map_err(|_| {
            crate::error::AppError::Validation(format!(
                "estimated_minutes must be between 0 and {}",
                lorvex_domain::validation::MAX_ESTIMATED_MINUTES
            ))
        })?;
    }

    let id = lorvex_domain::new_entity_id_string();
    let status = match status.as_deref() {
        Some(STATUS_SOMEDAY) => STATUS_SOMEDAY,
        Some(STATUS_OPEN) | None => STATUS_OPEN,
        Some(other) => {
            return Err(format!(
                "Invalid status for quick_capture: '{other}'. Use 'open' or 'someday'."
            )
            .into())
        }
    };

    let priority_u8: Option<u8> = priority
        .map(|p| {
            u8::try_from(p).map_err(|_| AppError::Validation(format!("invalid priority: {p}")))
        })
        .transpose()?;
    let estimated_minutes_u32: Option<u32> = estimated_minutes
        .map(|m| {
            u32::try_from(m)
                .map_err(|_| AppError::Validation(format!("invalid estimated_minutes: {m}")))
        })
        .transpose()?;

    fn lift<T>(value: Option<T>) -> Patch<T> {
        match value {
            None => Patch::Unset,
            Some(v) => Patch::Set(v),
        }
    }
    let workflow_input = CreateTaskInput {
        id: Some(id),
        task: TaskCreateInput {
            title,
            list_id: lift(list_id),
            priority: lift(priority_u8),
            due_date: lift(due_date),
            due_time: Patch::Unset,
            estimated_minutes: lift(estimated_minutes_u32),
            tags,
            body: lift(body),
            raw_input: lift(raw_input),
            ai_notes: lift(ai_notes),
            depends_on,
            reminders,
            recurrence_json: lift(recurrence_json),
            planned_date: lift(planned_date),
            completed: None,
            status: Patch::Set(status.to_string()),
        },
        include_advice: false,
    };

    with_immediate_transaction(conn, |conn| {
        // #3378: take a single HLC session for this whole top-level
        // mutation so the create_task stamp + every downstream
        // bookkeeping share one lock acquisition.
        let task_id = with_hlc_session(|session| {
            let outcome = task_create::create_task(conn, session, workflow_input.clone())
                .map_err(AppError::from)?;
            Ok::<String, AppError>(outcome.task_id.into_string())
        })?;
        finalize_task_mutation(conn, &task_id)
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn duplicate_task(id: String) -> Result<Task, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so the duplicator never sees a malformed source id.
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    duplicate_task_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn duplicate_task_inner(id: String) -> AppResult<Task> {
    let conn = get_conn()?;
    let task = duplicate_task_with_conn(&conn, &id)?;
    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

    // Post-commit Spotlight dispatch.
    crate::platform::spotlight::apply_actions(
        &conn,
        &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
            vec![task.id.clone()],
        )],
    );
    Ok(task)
}

/// Testable entry point — identical implementation to
/// `duplicate_task_inner` minus the Spotlight/event-bus side effects
/// that need a running Tauri runtime.
pub(crate) fn duplicate_task_with_conn(conn: &rusqlite::Connection, id: &str) -> AppResult<Task> {
    with_immediate_transaction(conn, |conn| {
        let source = fetch_task_by_id(conn, id)?;
        let new_id = lorvex_domain::new_entity_id_string();
        let now = sync_timestamp_now();
        // #3378: same session-per-mutation pattern as `quick_capture`.
        let version = with_hlc_session(|session| Ok(session.next_version_string()))?;

        // Delegate duplicate recurrence config to shared planner.
        let source_state = lorvex_workflow::recurrence_config::RecurrenceState {
            recurrence: source.recurrence.clone(),
            recurrence_group_id: source.recurrence_group_id.clone(),
            canonical_occurrence_date: source.canonical_occurrence_date.clone(),
            due_date: source.due_date.clone(),
            due_time: source.due_time.clone(),
        };
        let dup_actions =
            lorvex_workflow::recurrence_config::plan_duplicate_recurrence(&source_state);
        let dup_group_id = dup_actions.set_recurrence_group_id;
        let dup_canonical = dup_actions
            .set_canonical_occurrence_date
            .as_bind_value()
            .cloned();

        // Build a TaskRow-compatible struct from the Tauri Task for the shared function.
        // The store-side row carries typed `Date` / `TimeOfDay`; the
        // Tauri IPC `Task` model exposes the wire-stable `String`
        // shape, so re-parse at the boundary. Any malformed string
        // surfaces as a typed Validation error rather than corrupting
        // the row.
        let parse_optional_date =
            |raw: Option<&str>| -> Result<Option<lorvex_domain::time::Date>, AppError> {
                raw.map(lorvex_domain::time::Date::parse)
                    .transpose()
                    .map_err(|e| AppError::Validation(e.to_string()))
            };
        let parse_optional_time =
            |raw: Option<&str>| -> Result<Option<lorvex_domain::time::TimeOfDay>, AppError> {
                raw.map(lorvex_domain::time::TimeOfDay::parse)
                    .transpose()
                    .map_err(|e| AppError::Validation(e.to_string()))
            };
        let source_row = lorvex_store::repositories::task::read::TaskRow::from_parts(
            lorvex_store::repositories::task::read::TaskCore::new(
                lorvex_store::repositories::task::read::TaskCoreFields {
                    id: source.id.clone(),
                    title: source.title.clone(),
                    body: source.body.clone(),
                    raw_input: source.raw_input.clone(),
                    ai_notes: source.ai_notes.clone(),
                    status: source.status.clone(),
                    list_id: source.list_id.clone(),
                    priority: source.priority,
                    version: source.version.clone(),
                    created_at: source.created_at.clone(),
                    updated_at: source.updated_at.clone(),
                },
            ),
            lorvex_store::repositories::task::read::TaskScheduling::new(
                lorvex_store::repositories::task::read::TaskSchedulingFields {
                    due: lorvex_domain::time::DueAt::from_optional_pair(
                        parse_optional_date(source.due_date.as_deref())?,
                        parse_optional_time(source.due_time.as_deref())?,
                    )
                    .map_err(|e| String::from(crate::error::AppError::from(e)))?,
                    estimated_minutes: source.estimated_minutes,
                    planned_date: parse_optional_date(source.planned_date.as_deref())?,
                    // The Tauri IPC `Task` model does not yet surface
                    // `available_from`; this recurrence-preview row therefore
                    // cannot carry it. Defer-until is set through the MCP
                    // write surface, not this preview path.
                    available_from: None,
                    defer_count: source.defer_count,
                    last_deferred_at: source.last_deferred_at.clone(),
                    last_defer_reason: source.last_defer_reason.map(|r| r.as_str().to_string()),
                },
            ),
            lorvex_store::repositories::task::read::TaskRecurrenceState::new(
                lorvex_store::repositories::task::read::TaskRecurrenceStateFields {
                    recurrence: source.recurrence.clone(),
                    recurrence_exceptions: source.recurrence_exceptions.clone(),
                    spawned_from: source.spawned_from.clone(),
                    recurrence_group_id: source.recurrence_group_id.clone(),
                    canonical_occurrence_date: parse_optional_date(
                        source.canonical_occurrence_date.as_deref(),
                    )?,
                    recurrence_instance_key: None,
                },
            ),
            lorvex_store::repositories::task::read::TaskLifecycleTimestamps::new(
                lorvex_store::repositories::task::read::TaskLifecycleTimestampsFields {
                    completed_at: source.completed_at.clone(),
                    archived_at: source.archived_at.clone(),
                },
            ),
        );

        let new_title = format!("{} (copy)", source.title);
        let resolved_list_id =
            lorvex_store::resolve_required_task_list_id(conn, Some(&source.list_id)).map_err(
                |error| match error {
                    lorvex_store::StoreError::Validation(message) => AppError::Validation(message),
                    other => AppError::from(other),
                },
            )?;
        // Re-stamp the resolved list_id by tearing the row down to its
        // owned `*Fields` carriers and rebuilding via the canonical
        // constructors. The struct-update form
        // (`TaskRow { core: TaskCore { list_id, ..source_row.core }, .. }`)
        // does not work since the inner field-private types seal their
        // columns; the public `into_parts` / `*Fields` / `::new`
        // pipeline is the canonical mutation surface.
        let (core, scheduling, recurrence, lifecycle) = source_row.into_parts();
        let mut core_fields = core.into_fields();
        core_fields.list_id = resolved_list_id;
        let source_row = lorvex_store::repositories::task::read::TaskRow::from_parts(
            lorvex_store::repositories::task::read::TaskCore::new(core_fields),
            scheduling,
            recurrence,
            lifecycle,
        );

        write::duplicate_task(
            conn,
            &source_row,
            &new_id,
            &new_title,
            dup_group_id.as_deref(),
            dup_canonical.as_deref(),
            &version,
            &now,
        )
        .map_err(AppError::from)?;

        // Copy tags from the source task via tag_id references
        if let Some(ref tags) = source.tags {
            for tag in tags {
                link_tag_to_task(
                    conn,
                    &lorvex_domain::TaskId::from_trusted(new_id.clone()),
                    tag,
                    &now,
                )?;
            }
        }

        finalize_task_mutation(conn, &new_id)
    })
}

#[cfg(test)]
mod tests;
