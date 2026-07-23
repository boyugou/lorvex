use super::cancel_shared::filter_before_states;
use crate::contract::{BatchDeferTasksArgs, MAX_SHORT_TEXT_LENGTH};
use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_task_reminder_syncs, execute_mcp_batch_mutation_with_audit_finalizer,
};
use crate::system::handler_support::{
    fetch_tasks_json_batch, plural_s, required_json_i64_field, required_json_string_field,
    utc_now_iso,
};
use crate::system::vec_limits::validate_batch_ids;
use crate::tasks::validation::{sanitize_optional_user_text, validate_optional_string_length};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::TASK_SHIFTED_REMINDER_IDS;
use lorvex_workflow::task_deferral;
use rusqlite::Connection;
use serde_json::{json, Value};

fn find_before_task<'a>(before_tasks: &'a [Value], task_id: &str) -> Result<&'a Value, McpError> {
    before_tasks
        .iter()
        .find(|task| task.get("id").and_then(Value::as_str) == Some(task_id))
        .ok_or_else(|| {
            McpError::Internal(format!(
                "malformed task batch state: missing task snapshot for {task_id}"
            ))
        })
}

fn quoted_task_title(task: &Value, context: &str) -> Result<String, McpError> {
    Ok(format!(
        "'{}'",
        required_json_string_field(task, "title", context)?
    ))
}

struct BatchDeferTaskInput {
    id: String,
    ai_notes_value: Option<String>,
}

struct BatchDeferTasksMutation {
    tasks: Vec<BatchDeferTaskInput>,
    before_tasks: Vec<Value>,
    normalized_until_date: String,
    structured_reason: Option<String>,
    now: String,
    summary: String,
}

impl Mutation for BatchDeferTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_defer"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(json!({ "before_states": self.before_tasks })))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut shifted_reminder_ids = Vec::new();
        for task in &self.tasks {
            let version = hlc.next_version_string();
            let patch = task_deferral::TaskDeferralPatch {
                planned_date: Some(self.normalized_until_date.as_str()),
                ai_notes: task.ai_notes_value.as_deref(),
                last_defer_reason: self.structured_reason.as_deref(),
            };

            let task_id = TaskId::from_trusted(task.id.clone());
            let result =
                task_deferral::defer_task(conn, &task_id, &patch, &version, &self.now, || {
                    Ok::<String, StoreError>(hlc.next_version_string())
                })?;
            if !result.updated {
                return Err(StoreError::StaleVersion {
                    entity: ENTITY_TASK,
                    id: task.id.clone(),
                });
            }
            shifted_reminder_ids.extend(result.shifted_reminder_ids);
        }

        let deferred_ids: Vec<String> = self.tasks.iter().map(|task| task.id.clone()).collect();
        let deferred_tasks = fetch_tasks_json_batch(conn, &deferred_ids, "task after defer")
            .map_err(mcp_error_to_store)?;
        let mut output = MutationOutput::new(
            json!({ "after_states": deferred_tasks }),
            self.summary.clone(),
        );
        output.set_extra(
            &TASK_SHIFTED_REMINDER_IDS,
            Value::Array(
                shifted_reminder_ids
                    .into_iter()
                    .map(Value::String)
                    .collect(),
            ),
        );
        Ok(output)
    }
}

fn shifted_reminder_ids(execution: &MutationExecution) -> Result<Vec<String>, McpError> {
    let ids = execution
        .output
        .get_extra(&TASK_SHIFTED_REMINDER_IDS)
        .and_then(Value::as_array)
        .expect("Mutation contract: batch_defer_tasks shifted reminder ids stamped by apply");
    ids.iter()
        .map(|value| {
            value.as_str().map(str::to_string).ok_or_else(|| {
                McpError::Internal(
                    "batch_defer_tasks shifted reminder id extra contained a non-string value"
                        .to_string(),
                )
            })
        })
        .collect()
}

fn mcp_error_to_store(error: McpError) -> StoreError {
    match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) | McpError::UserMessage(message) => {
            StoreError::Validation(message)
        }
        McpError::NotFound(message) => StoreError::NotFound {
            entity: ENTITY_TASK,
            id: message,
        },
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    }
}

pub(crate) fn batch_defer_tasks(
    conn: &Connection,
    args: BatchDeferTasksArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchDeferTasksArgs {
        task_ids: ids,
        until_date,
        reason,
        structured_reason,
        idempotency_key,
    } = args;
    // see batch_complete_tasks for rationale.
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_defer_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_batch_ids(&ids, "batch_defer_tasks")?;
    validate_optional_string_length(reason.as_deref(), "reason", MAX_SHORT_TEXT_LENGTH)?;
    let reason = sanitize_optional_user_text(reason, "reason", MAX_SHORT_TEXT_LENGTH)?;
    if let Some(ref sr) = structured_reason {
        if !lorvex_domain::naming::is_valid_defer_reason(sr) {
            return Err(McpError::Validation(format!(
                "Invalid structured_reason '{}'. Valid values: {}",
                sr,
                lorvex_domain::naming::ALL_DEFER_REASONS.join(", ")
            )));
        }
    }

    let normalized_until_date =
        crate::tasks::support::normalize_due_date_input_for_conn(conn, until_date)?;

    let before_tasks = fetch_tasks_json_batch(conn, &ids, "batch_defer_tasks")?;
    if before_tasks.len() != ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_defer_tasks requested {} task(s) but only {} found",
            ids.len(),
            before_tasks.len()
        )));
    }

    // reject the whole batch on any non-deferrable
    // task instead of silently skipping. Matches the atomicity
    // discipline of batch_complete_tasks and the broader CLAUDE.md
    // rule. Caller is expected to re-call with the open subset.
    let mut skipped: Vec<String> = Vec::with_capacity(ids.len());
    let mut to_defer: Vec<String> = Vec::with_capacity(ids.len());
    for id in &ids {
        let task = find_before_task(&before_tasks, id)?;
        let status = required_json_string_field(task, "status", "batch_defer_tasks before-task")?;
        if status == STATUS_COMPLETED || status == STATUS_CANCELLED {
            skipped.push(id.clone());
        } else {
            to_defer.push(id.clone());
        }
    }

    if !skipped.is_empty() {
        return Err(McpError::Validation(format!(
            "batch_defer_tasks rejects partial application: {} of {} task(s) are completed or cancelled and cannot be deferred: [{}]. \
             Re-call with the open subset.",
            skipped.len(),
            ids.len(),
            skipped.join(", ")
        )));
    }

    let titles = to_defer
        .iter()
        .map(|tid| {
            let task = find_before_task(&before_tasks, tid)?;
            quoted_task_title(task, "batch_defer_tasks before-task")
        })
        .collect::<Result<Vec<_>, McpError>>()?
        .join(", ");
    let reason_part = reason
        .as_ref()
        .map(|r| format!(" — {r}"))
        .unwrap_or_default();
    let summary = format!(
        "Deferred {} task{} until {}{reason_part}: {}",
        to_defer.len(),
        plural_s(to_defer.len()),
        normalized_until_date,
        titles,
    );

    // #2939-H3: aggregate before/after states for the parent
    // batch_defer changelog row. `before_tasks` was loaded at the top
    // of the handler and `deferred_tasks` is the post-mutation
    // snapshot for the response.
    let deferred_before = filter_before_states(&before_tasks, &to_defer);
    let tasks = to_defer
        .iter()
        .map(|task_id| {
            let ai_notes_value = if let Some(reason_text) = reason.as_deref() {
                let task = find_before_task(&before_tasks, task_id)?;
                let before_defer_count =
                    required_json_i64_field(task, "defer_count", "batch_defer_tasks before-task")?;
                let before_ai_notes = task
                    .get("ai_notes")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                let new_defer_count = before_defer_count + 1;
                let defer_note = format!("Deferred (#{new_defer_count}): {reason_text}");
                Some(if before_ai_notes.trim().is_empty() {
                    defer_note
                } else {
                    format!("{before_ai_notes}\n\n{defer_note}")
                })
            } else {
                None
            };
            Ok(BatchDeferTaskInput {
                id: task_id.clone(),
                ai_notes_value,
            })
        })
        .collect::<Result<Vec<_>, McpError>>()?;
    let mutation = BatchDeferTasksMutation {
        tasks,
        before_tasks: deferred_before,
        normalized_until_date,
        structured_reason,
        now: utc_now_iso(),
        summary,
    };
    let output = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "batch_defer_tasks",
        to_defer,
        McpError::from,
        |conn, execution| {
            let ids = shifted_reminder_ids(execution)?;
            enqueue_task_reminder_syncs(conn, &ids)
        },
    )?;
    let deferred_tasks = output
        .after
        .get("after_states")
        .and_then(Value::as_array)
        .expect("Mutation contract: batch_defer_tasks after_states stamped by apply")
        .clone();

    let response = serde_json::to_string(&json!({
        "deferred_count": deferred_tasks.len(),
        "deferred": deferred_tasks,
        "skipped": skipped,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_defer_tasks",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

#[cfg(test)]
mod tests;
