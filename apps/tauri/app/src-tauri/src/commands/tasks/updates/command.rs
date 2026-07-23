//! Tauri `update_task` IPC adapter — routes the single-row update
//! through [`lorvex_workflow::task_update::update_task`] so SQL writes,
//! lifecycle transitions, recurrence + due_date co-application, edge
//! diffing, and per-row sync-effect accumulation share one
//! implementation with the MCP and CLI surfaces.
//!
//! Wire shape: the renderer posts a JSON `updates` object whose keys
//! mirror the MCP `UpdateTaskArgs` field set; we deserialize it into
//! [`TaskUpdateInput`] and the workflow op consumes the typed value.
//!
//! Undo semantics: every non-bookkeeping update mints an undo token
//! carrying the full pre-mutation snapshot and registers it so the
//! Changelog can surface a late Undo affordance. Undo replays the
//! snapshot through the same update path, enqueueing a fresh upsert
//! that supersedes the forward write on peers.

use super::flush::IpcTaskUpdateFlush;
use super::*;

use lorvex_workflow::task_update::{
    flush_with_backend, update_task as workflow_update_task, TaskUpdateInput, UpdatedTaskOutcome,
};

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn update_task(id: String, updates: serde_json::Value) -> Result<TaskWithUndo, String> {
    // task ids are UUIDv7 — shape-check at the IPC boundary so a
    // malformed id can't reach the update writer (which touches tags,
    // dependencies, reminders, and the changelog).
    let id = crate::commands::shared::validate_uuid_id(&id, "id")?;
    update_task_inner(&id, &updates).map_err(String::from)
}

/// Inner helper for the `update_task` IPC. Mints an undo token from
/// the pre-mutation snapshot so the UI can show a Success toast with
/// Undo.
pub(crate) fn update_task_inner(
    id: &str,
    updates: &serde_json::Value,
) -> Result<TaskWithUndo, AppError> {
    let conn = get_conn()?;
    let result =
        with_immediate_transaction(&conn, |conn| update_task_inner_with_conn(conn, id, updates))?;

    crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

    // Post-commit Spotlight dispatch — routed through the shared
    // dispatcher so the "task mutated → reindex" rule lives in one
    // place across capture, update, and lifecycle surfaces.
    crate::commands::shared::reindex_task_after_mutation(&conn, result.task.id.clone());

    Ok(result)
}

/// Transaction body for `update_task_inner` — runs against the caller-
/// supplied connection so tests can drive it without the live Tauri
/// runtime. Snapshots the pre-mutation task, runs the canonical
/// `lorvex_workflow::task_update::update_task`, dispatches sync effects
/// via [`IpcTaskUpdateFlush`], and mints an undo token from the
/// pre-mutation snapshot.
pub(crate) fn update_task_inner_with_conn(
    conn: &Connection,
    id: &str,
    updates: &serde_json::Value,
) -> Result<TaskWithUndo, AppError> {
    // Capture the pre-mutation task (enriched with tags + depends_on)
    // so the undo can re-apply every updatable field.
    let pre_task = fetch_task_by_id(conn, id)?;

    let input = parse_update_payload(id, updates)?;
    run_update_workflow_and_flush(conn, input)?;

    let expires_at = compute_undo_expiry();
    let task = fetch_task_by_id(conn, id)?;
    let undo_token = build_update_undo_token(&pre_task, &expires_at)?;

    // cache the serialized undo token for the undo window so the
    // Changelog view can surface an Undo affordance for this row even
    // after the success toast has timed out.
    crate::commands::diagnostics::undo_token_cache::register(id, &undo_token, &expires_at);

    Ok(TaskWithUndo { task, undo_token })
}

/// Internal helper shared by the IPC entry and the update-undo replay
/// path. Runs the canonical workflow + flush pair against the caller-
/// supplied connection. Returns the workflow's [`UpdatedTaskOutcome`]
/// so callers that need the enriched after-task can read it from there;
/// callers that just want the row can `fetch_task_by_id` afterwards.
///
/// The HLC session is opened internally so this function works from
/// both the IPC entry (no surrounding executor) and the undo replay
/// (which also lacks one). Sync effects are flushed via
/// [`IpcTaskUpdateFlush`] before this returns, so the rows are visible
/// to any retrofit pass the caller runs.
pub(crate) fn run_update_workflow_and_flush(
    conn: &Connection,
    input: TaskUpdateInput,
) -> Result<UpdatedTaskOutcome, AppError> {
    let outcome = crate::hlc::with_hlc_session(|session| {
        workflow_update_task(conn, session, input).map_err(AppError::from)
    })?;
    let backend = IpcTaskUpdateFlush {
        executor_handled_ids: &[],
    };
    flush_with_backend(conn, &outcome.sync_effects, &backend)?;
    Ok(outcome)
}

/// Deserialize the renderer-supplied JSON patch into the workflow's
/// typed [`TaskUpdateInput`]. The id is injected from the IPC arg so
/// the wire payload doesn't need to repeat it.
///
/// Two wire-shape compensations live here until the renderer migrates
/// (#4346 step 6, out of scope for this PR):
///
///   * The renderer (and the update-undo snapshot, which serializes
///     the full `Task` row) uses `tags` for the set-replacement form,
///     while [`TaskUpdateInput`] follows the MCP contract and exposes
///     `tags_set` / `tags_add` / `tags_remove`. We translate `tags →
///     tags_set` only when the snapshot/payload contains the legacy
///     key and the new key is absent.
///   * The undo snapshot stores `recurrence` as its DB-canonical JSON
///     string (mirroring `Task.recurrence: Option<String>`). The
///     workflow accepts a structured object or null, so we decode the
///     stored string into a JSON value before handing it to serde.
///
/// Unknown fields are filtered out before deserialization so the
/// renderer's `Task`-shaped undo snapshot (which carries
/// `version`/`created_at`/...) passes the workflow input's
/// `deny_unknown_fields` gate.
fn parse_update_payload(
    id: &str,
    updates: &serde_json::Value,
) -> Result<TaskUpdateInput, AppError> {
    let source = updates
        .as_object()
        .ok_or_else(|| AppError::Validation("updates must be a JSON object".to_string()))?;

    // Per-field shape pre-checks. Catches the malformed-shape cases
    // (`priority: "high"`, `due_date: true`, etc.) with field-named
    // errors before serde produces a generic type-mismatch message
    // that doesn't name the offending key.
    type FieldKind = (&'static str, ValueShape);
    use ValueShape::{
        ArrayOfStrings, NullableInteger, NullableString, RecurrenceObjectOrNull, RequiredString,
    };
    const FIELD_SHAPES: &[FieldKind] = &[
        ("title", RequiredString),
        ("body", NullableString),
        ("ai_notes", NullableString),
        ("status", RequiredString),
        // `list_id` is checked as NullableString here so the
        // explicit "Tasks must belong to a real list" message below
        // can surface for the `null` (clear) case before the generic
        // shape message fires.
        ("list_id", NullableString),
        ("tags", ArrayOfStrings),
        ("tags_set", ArrayOfStrings),
        ("tags_add", ArrayOfStrings),
        ("tags_remove", ArrayOfStrings),
        ("priority", NullableInteger),
        ("due_date", NullableString),
        ("due_time", NullableString),
        ("planned_date", NullableString),
        ("estimated_minutes", NullableInteger),
        ("recurrence", RecurrenceObjectOrNull),
        ("depends_on", ArrayOfStrings),
        ("depends_on_add", ArrayOfStrings),
        ("depends_on_remove", ArrayOfStrings),
        ("raw_input", RequiredString),
    ];

    // Normalize `recurrence` (string-form snapshot → JSON value) BEFORE
    // shape-checking so the undo-replay path, whose pre-task snapshot
    // stores recurrence as a JSON-encoded string, isn't rejected.
    let normalized_recurrence = source
        .get("recurrence")
        .map(|value| normalize_recurrence_input(value.clone()))
        .transpose()?;

    for (field, shape) in FIELD_SHAPES {
        let value = if *field == "recurrence" {
            match normalized_recurrence.as_ref() {
                Some(value) => value,
                None => continue,
            }
        } else {
            match source.get(*field) {
                Some(value) => value,
                None => continue,
            }
        };
        if !shape.matches(value) {
            return Err(AppError::Validation(format!(
                "invalid {field} in update_task: {} (got {})",
                shape.describe(),
                value_type_name(value)
            )));
        }
    }
    if matches!(source.get("list_id"), Some(serde_json::Value::Null)) {
        return Err(AppError::Validation(
            "Tasks must belong to a real list. Choose a list instead of clearing list_id."
                .to_string(),
        ));
    }

    let mut patch = serde_json::Map::new();
    patch.insert("id".to_string(), serde_json::Value::String(id.to_string()));

    // Translate the renderer's `tags` (array form) into `tags_set`. If
    // the payload already carries `tags_set`, prefer that and ignore
    // the legacy key.
    let has_tags_set = source.contains_key("tags_set");
    for field in TaskUpdateInput::FIELDS {
        if *field == "id" {
            continue;
        }
        if *field == "recurrence" {
            if let Some(value) = normalized_recurrence.clone() {
                patch.insert("recurrence".to_string(), value);
            }
            continue;
        }
        if let Some(value) = source.get(*field) {
            patch.insert((*field).to_string(), value.clone());
        }
    }
    if !has_tags_set {
        if let Some(value) = source.get("tags") {
            patch.insert("tags_set".to_string(), value.clone());
        }
    }

    serde_json::from_value::<TaskUpdateInput>(serde_json::Value::Object(patch))
        .map_err(|err| AppError::Validation(format!("invalid update_task payload: {err}")))
}

/// Per-field shape pre-checks. The variants mirror the live wire-shape
/// expectations of [`TaskUpdateInput`] / its Tauri-only `tags` alias.
#[derive(Clone, Copy)]
enum ValueShape {
    /// A non-null string. Used for keys that workflow `Option<String>`
    /// treats as no-update on absence — `null` would be silently lost.
    RequiredString,
    /// A string or explicit `null` (clear).
    NullableString,
    /// An integer or explicit `null` (clear).
    NullableInteger,
    /// An array whose elements are all strings.
    ArrayOfStrings,
    /// A structured recurrence rule object, or `null`.
    RecurrenceObjectOrNull,
}

impl ValueShape {
    fn matches(&self, value: &serde_json::Value) -> bool {
        use serde_json::Value;
        match self {
            ValueShape::RequiredString => matches!(value, Value::String(_)),
            ValueShape::NullableString => matches!(value, Value::String(_) | Value::Null),
            ValueShape::NullableInteger => value.is_null() || value.is_i64() || value.is_u64(),
            ValueShape::ArrayOfStrings => match value {
                Value::Null => true,
                Value::Array(arr) => arr.iter().all(|v| matches!(v, Value::String(_))),
                _ => false,
            },
            ValueShape::RecurrenceObjectOrNull => {
                matches!(value, Value::Object(_) | Value::Null)
            }
        }
    }

    fn describe(&self) -> &'static str {
        match self {
            ValueShape::RequiredString => "expected a string",
            ValueShape::NullableString => "expected a string or null",
            ValueShape::NullableInteger => "expected an integer or null",
            ValueShape::ArrayOfStrings => "expected a JSON array of strings or null",
            ValueShape::RecurrenceObjectOrNull => {
                "expected a structured RecurrenceRuleArgs object or null"
            }
        }
    }
}

fn value_type_name(value: &serde_json::Value) -> &'static str {
    match value {
        serde_json::Value::Null => "null",
        serde_json::Value::Bool(_) => "boolean",
        serde_json::Value::Number(n) if n.is_f64() => "float",
        serde_json::Value::Number(_) => "integer",
        serde_json::Value::String(_) => "string",
        serde_json::Value::Array(_) => "array",
        serde_json::Value::Object(_) => "object",
    }
}

/// The undo-snapshot path stores `recurrence` as a DB-canonical JSON
/// string (`Task.recurrence: Option<String>`). The workflow accepts a
/// structured object or null, so we decode the stored string into a
/// JSON value before handing it to serde. Non-string values pass
/// through verbatim — the renderer already posts objects/null.
fn normalize_recurrence_input(value: serde_json::Value) -> Result<serde_json::Value, AppError> {
    match value {
        serde_json::Value::String(rule) => serde_json::from_str::<serde_json::Value>(&rule)
            .map_err(|e| {
                AppError::Validation(format!(
                    "update_task payload contains malformed recurrence JSON: {e}"
                ))
            }),
        other => Ok(other),
    }
}

/// Legacy entry preserved so the undo-replay path and a handful of
/// older tests can drive the update flow against a caller-supplied
/// connection without parsing through the IPC boundary. Internally
/// routes through the canonical workflow + flush pair; no undo token
/// is minted.
pub(crate) fn update_task_internal(
    conn: &Connection,
    id: &str,
    updates: &serde_json::Value,
    now: &str,
) -> Result<Task, AppError> {
    let _ = now; // workflow re-derives `now` via `sync_timestamp_now`.
    let input = parse_update_payload(id, updates)?;
    run_update_workflow_and_flush(conn, input)?;
    fetch_task_by_id(conn, id)
}
