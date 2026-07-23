//! CLI handler for `task.create`. Translates the typed
//! [`TaskCreateInputs`] CLI args into [`CreateTaskInput`], threads the
//! call through [`task_create::create_task`], and stamps the CLI's
//! audit/sync trail (idempotency lookup, outbox enqueues, ai_changelog
//! row, `local_change_seq` bump) before rendering the canonical
//! mutation envelope.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::Patch;
use lorvex_runtime::resolve_db_path;
use lorvex_workflow::task_create::{self, CreateTaskInput, CreateTaskResult, TaskCreateInput};
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::cli::OutputFormat;
use crate::commands::shared::{log_cli_changelog_with_state, CliChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::super::render_mutation_response;
use super::idempotency::{lookup_cli_idempotency, record_cli_idempotency};
use super::shared_flush::enqueue_task_lifecycle_effects;

pub(crate) struct TaskCreateInputs<'a> {
    pub(crate) title: &'a str,
    pub(crate) list_id: Option<&'a str>,
    pub(crate) priority: Option<u8>,
    pub(crate) due_date: Option<&'a str>,
    pub(crate) due_time: Option<&'a str>,
    pub(crate) planned_date: Option<&'a str>,
    pub(crate) estimated_minutes: Option<u32>,
    pub(crate) tags: &'a [String],
    pub(crate) body: Option<&'a str>,
    pub(crate) ai_notes: Option<&'a str>,
    pub(crate) depends_on: &'a [String],
    pub(crate) reminders: &'a [String],
    pub(crate) recurrence: Option<&'a str>,
    pub(crate) completed: bool,
    pub(crate) idempotency_key: Option<&'a str>,
}

pub(crate) fn run_task_create(
    inputs: &TaskCreateInputs<'_>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let (recurrence_json, recurrence_value) = parse_create_recurrence(inputs.recurrence)?;
    let request_repr = create_task_request_repr(inputs, recurrence_value.as_ref())?;
    fn lift<T>(value: Option<T>) -> Patch<T> {
        match value {
            None => Patch::Unset,
            Some(v) => Patch::Set(v),
        }
    }
    let input = CreateTaskInput {
        id: None,
        task: TaskCreateInput {
            title: inputs.title.to_string(),
            list_id: lift(inputs.list_id.map(str::to_string)),
            priority: lift(inputs.priority),
            due_date: lift(inputs.due_date.map(str::to_string)),
            due_time: lift(inputs.due_time.map(str::to_string)),
            planned_date: lift(inputs.planned_date.map(str::to_string)),
            estimated_minutes: lift(inputs.estimated_minutes),
            tags: optional_nonempty_vec(inputs.tags),
            body: lift(inputs.body.map(str::to_string)),
            raw_input: Patch::Unset,
            ai_notes: lift(inputs.ai_notes.map(str::to_string)),
            depends_on: optional_nonempty_vec(inputs.depends_on),
            reminders: optional_nonempty_vec(inputs.reminders),
            recurrence_json: lift(recurrence_json),
            completed: inputs.completed.then_some(true),
            status: Patch::Unset,
        },
        include_advice: false,
    };
    let raw = lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
        if let Some(cached) =
            lookup_cli_idempotency(conn, "create_task", inputs.idempotency_key, &request_repr)?
        {
            return Ok(cached);
        }
        let result = run_task_create_workflow_in_tx(conn, input)?;
        let raw = serde_json::to_string(&result.payload)?;
        record_cli_idempotency(
            conn,
            "create_task",
            inputs.idempotency_key,
            &request_repr,
            &raw,
        )?;
        Ok::<_, CliError>(raw)
    })?;
    render_mutation_response(
        "task.create",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload }),
    )
}

fn parse_create_recurrence(raw: Option<&str>) -> Result<(Option<String>, Option<Value>), CliError> {
    let Some(raw) = raw else {
        return Ok((None, None));
    };
    let parsed: Value = serde_json::from_str(raw).map_err(|e| {
        CliError::Validation(format!(
            "--recurrence must be a JSON object describing a RecurrenceRuleArgs: {e}"
        ))
    })?;
    if !parsed.is_object() {
        return Err(CliError::Validation(
            "--recurrence must be a JSON object (e.g. {\"freq\":\"weekly\",\"interval\":2,\"byday\":[\"MO\"]})".to_string(),
        ));
    }
    Ok((Some(parsed.to_string()), Some(parsed)))
}

fn create_task_request_repr(
    inputs: &TaskCreateInputs<'_>,
    recurrence: Option<&Value>,
) -> Result<String, CliError> {
    let mut args = serde_json::Map::new();
    args.insert("title".to_string(), json!(inputs.title));
    if let Some(value) = inputs.list_id {
        args.insert("list_id".to_string(), json!(value));
    }
    if let Some(value) = inputs.priority {
        args.insert("priority".to_string(), json!(value));
    }
    if let Some(value) = inputs.due_date {
        args.insert("due_date".to_string(), json!(value));
    }
    if let Some(value) = inputs.due_time {
        args.insert("due_time".to_string(), json!(value));
    }
    if let Some(value) = inputs.planned_date {
        args.insert("planned_date".to_string(), json!(value));
    }
    if let Some(value) = inputs.estimated_minutes {
        args.insert("estimated_minutes".to_string(), json!(value));
    }
    if !inputs.tags.is_empty() {
        args.insert("tags".to_string(), json!(inputs.tags));
    }
    if let Some(value) = inputs.body {
        args.insert("body".to_string(), json!(value));
    }
    if let Some(value) = inputs.ai_notes {
        args.insert("ai_notes".to_string(), json!(value));
    }
    if !inputs.depends_on.is_empty() {
        args.insert("depends_on".to_string(), json!(inputs.depends_on));
    }
    if !inputs.reminders.is_empty() {
        args.insert("reminders".to_string(), json!(inputs.reminders));
    }
    if let Some(value) = recurrence {
        args.insert("recurrence".to_string(), value.clone());
    }
    if inputs.completed {
        args.insert("completed".to_string(), json!(true));
    }
    if let Some(value) = inputs.idempotency_key {
        args.insert("idempotency_key".to_string(), json!(value));
    }
    lorvex_domain::canonical_json::canonicalize_json(&Value::Object(args)).map_err(|e| {
        CliError::Validation(format!("idempotency request canonicalization failed: {e}"))
    })
}

fn optional_nonempty_vec(values: &[String]) -> Option<Vec<String>> {
    (!values.is_empty()).then(|| values.to_vec())
}

fn run_task_create_workflow_in_tx(
    conn: &Connection,
    input: CreateTaskInput,
) -> Result<CreateTaskResult, CliError> {
    let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
    let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
    let result = {
        let handle = CliHlcStateHandle::new(&mut hlc_guard);
        let session = HlcSession::new(&handle);
        task_create::create_task(conn, &session, input)?
    };
    enqueue_task_lifecycle_effects(conn, &device_id, &mut hlc_guard, &result.sync_effects)?;
    log_cli_changelog_with_state(
        conn,
        &mut hlc_guard,
        CliChangelogParams {
            operation: "create",
            entity_type: ENTITY_TASK,
            entity_id: result.task_id.as_str(),
            summary: &result.summary,
            before_json: None,
            after_json: Some(result.task.clone()),
        },
    )?;
    lorvex_runtime::bump_local_change_seq(conn)?;
    Ok(result)
}
