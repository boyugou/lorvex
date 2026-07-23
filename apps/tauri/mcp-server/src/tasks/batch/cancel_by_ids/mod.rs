use super::cancel_shared::filter_before_states;
use crate::contract::{BatchCancelTasksArgs, MAX_SHORT_TEXT_LENGTH};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_existing_tasks_json, fetch_tasks_json_batch, plural_s, required_json_string_field,
    utc_now_iso,
};
use crate::system::vec_limits::validate_batch_ids;
use crate::tasks::dependencies::sync_dep_affected_tasks;
use crate::tasks::lifecycle::effects::LifecycleSyncLogContext;
use crate::tasks::validation::{sanitize_optional_user_text, validate_optional_string_length};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, CancelLifecycleTransitionResult, LifecycleSyncPlan,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashSet;

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

fn task_title_or_unknown(before_tasks: &[Value], task_id: &str) -> String {
    find_before_task(before_tasks, task_id)
        .ok()
        .and_then(|task| {
            required_json_string_field(task, "title", "batch_cancel_tasks")
                .ok()
                .map(str::to_string)
        })
        .unwrap_or_else(|| "unknown".to_string())
}

struct BatchCancelTaskInput {
    id: String,
    ai_notes_value: Option<String>,
}

struct BatchCancelTasksMutation {
    tasks: Vec<BatchCancelTaskInput>,
    before_tasks: Vec<Value>,
    now: String,
    cancel_series: bool,
    summary: String,
    transitions: RefCell<Vec<(String, CancelLifecycleTransitionResult)>>,
}

impl BatchCancelTasksMutation {
    fn task_ids(&self) -> Vec<String> {
        self.tasks.iter().map(|task| task.id.clone()).collect()
    }

    fn take_transitions(&self) -> Vec<(String, CancelLifecycleTransitionResult)> {
        self.transitions.replace(Vec::new())
    }
}

impl Mutation for BatchCancelTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_cancel"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(json!({ "before_states": self.before_tasks })))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut transitions = Vec::with_capacity(self.tasks.len());
        for task in &self.tasks {
            if let Some(ai_notes_value) = task.ai_notes_value.as_deref() {
                conn.prepare_cached(
                    "UPDATE tasks
                     SET ai_notes = ?1
                     WHERE id = ?2",
                )?
                .execute(params![ai_notes_value, &task.id])?;
            }

            let task_id = TaskId::from_trusted(task.id.clone());
            let result =
                workflow_effects::run_cancel(conn, &task_id, &self.now, self.cancel_series, hlc)?;
            if !result.updated {
                return Err(StoreError::Validation(format!(
                    "Task '{}' could not be cancelled",
                    task.id
                )));
            }
            transitions.push((task.id.clone(), result));
        }

        let task_ids = self.task_ids();
        let cancelled_tasks =
            fetch_existing_tasks_json(conn, &task_ids).map_err(mcp_error_to_store)?;
        self.transitions.replace(transitions);
        Ok(MutationOutput::new(
            json!({ "after_states": cancelled_tasks }),
            self.summary.clone(),
        ))
    }
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

pub(crate) fn batch_cancel_tasks(
    conn: &Connection,
    args: BatchCancelTasksArgs,
) -> Result<String, McpError> {
    // Capture the canonical request fingerprint before destructure so
    // keyed retries can replay the original response and reject payload
    // drift under the same token.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchCancelTasksArgs {
        task_ids: ids,
        reason,
        cancel_series,
        // `dry_run` is consumed at the router layer (#2370).
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_cancel_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_batch_ids(&ids, "batch_cancel_tasks")?;
    validate_optional_string_length(reason.as_deref(), "reason", MAX_SHORT_TEXT_LENGTH)?;
    let reason = sanitize_optional_user_text(reason, "reason", MAX_SHORT_TEXT_LENGTH)?;

    let before_tasks = fetch_tasks_json_batch(conn, &ids, "batch_cancel_tasks")?;
    if before_tasks.len() != ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_cancel_tasks requested {} task(s) but only {} found",
            ids.len(),
            before_tasks.len()
        )));
    }

    // partial-apply is NOT acceptable for batch
    // tools. CLAUDE.md says "short-circuit on validation failure for
    // the whole batch (atomicity), not partial-apply" — and
    // batch_complete_tasks already enforces this.
    // tool silently split into to_cancel + already_done and
    // proceeded with the partial set, which left the assistant
    // unable to distinguish "8 of 10 needed cancellation" from
    // "2 of 10 raced and were already cancelled by another path".
    // Reject the whole batch with a list of bad ids so the caller
    // can re-call with the right set.
    let mut already_done: Vec<String> = Vec::with_capacity(ids.len());
    let mut to_cancel: Vec<String> = Vec::with_capacity(ids.len());
    for id in &ids {
        let task = find_before_task(&before_tasks, id)?;
        let status = required_json_string_field(task, "status", "batch_cancel_tasks before-task")?;
        if status == STATUS_CANCELLED || status == STATUS_COMPLETED {
            already_done.push(id.clone());
        } else {
            to_cancel.push(id.clone());
        }
    }

    if !already_done.is_empty() {
        return Err(McpError::Validation(format!(
            "batch_cancel_tasks rejects partial application: {} of {} task(s) are already cancelled or completed: [{}]. \
             Re-call with the open subset.",
            already_done.len(),
            ids.len(),
            already_done.join(", ")
        )));
    }

    let cancel_series_flag = cancel_series.unwrap_or(false);
    let titles = to_cancel
        .iter()
        .map(|tid| -> Result<String, McpError> {
            let task = find_before_task(&before_tasks, tid)?;
            quoted_task_title(task, "batch_cancel_tasks before-task")
        })
        .collect::<Result<Vec<_>, McpError>>()?
        .join(", ");
    let reason_part = reason
        .as_ref()
        .map(|r| format!(" — {r}"))
        .unwrap_or_default();
    let summary = format!(
        "Cancelled {} task{}: {}{reason_part}",
        to_cancel.len(),
        plural_s(to_cancel.len()),
        titles,
    );

    // #2939-H3: aggregate before/after states for the parent
    // batch_cancel changelog row. `before_tasks` was loaded at the top
    // of the handler; the mutation output carries the post-mutation
    // snapshots for the response and audit row.
    let cancelled_before = filter_before_states(&before_tasks, &to_cancel);
    let tasks = to_cancel
        .iter()
        .map(|task_id| {
            let ai_notes_value = if let Some(reason_text) = reason.as_deref() {
                let task = find_before_task(&before_tasks, task_id)?;
                let before_ai_notes = task
                    .get("ai_notes")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                Some(if before_ai_notes.trim().is_empty() {
                    format!("Cancelled: {reason_text}")
                } else {
                    format!("{before_ai_notes}\n\nCancelled: {reason_text}")
                })
            } else {
                None
            };
            Ok(BatchCancelTaskInput {
                id: task_id.clone(),
                ai_notes_value,
            })
        })
        .collect::<Result<Vec<_>, McpError>>()?;
    let mutation = BatchCancelTasksMutation {
        tasks,
        before_tasks: cancelled_before,
        now: utc_now_iso(),
        cancel_series: cancel_series_flag,
        summary,
        transitions: RefCell::new(Vec::new()),
    };

    let ids_set: HashSet<&str> = to_cancel.iter().map(String::as_str).collect();
    let mut external_dep_affected: Vec<String> = Vec::new();
    let mut next_occurrences: Vec<Value> = Vec::new();
    let output = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "batch_cancel_tasks",
        to_cancel.clone(),
        McpError::from,
        |conn, _execution| {
            let mut all_dep_affected: HashSet<String> =
                HashSet::with_capacity(mutation.tasks.len());
            for (id, result) in mutation.take_transitions() {
                let external_affected_ids: Vec<String> = result
                    .affected_dependent_ids
                    .iter()
                    .filter(|dep_id| !ids_set.contains(dep_id.as_str()))
                    .cloned()
                    .collect();
                all_dep_affected.extend(external_affected_ids);

                let mut plan = LifecycleSyncPlan::from_cancel(&result);
                let no_affected_dependents: &[String] = &[];
                plan.status.affected_dependent_ids = no_affected_dependents;

                if let Some(successor_json) = crate::tasks::lifecycle::effects::flush_sync_plan(
                    conn,
                    plan,
                    LifecycleSyncLogContext {
                        mcp_tool: "batch_cancel_tasks",
                        spawned_successor_summary: Some(format!(
                            "Spawned recurrence successor of '{}' (skip-cancel)",
                            task_title_or_unknown(&before_tasks, &id)
                        )),
                        cancelled_successor_summary: None,
                        affected_dependent_reason: "cancelled tasks".to_string(),
                        successor_affected_reason: "cancelled successor".to_string(),
                        rewire_parent_task_id: Some(id),
                        rewire_parent_description: "cancelled recurring task",
                    },
                )? {
                    next_occurrences.push(successor_json);
                }
            }

            external_dep_affected = all_dep_affected.into_iter().collect();
            let dep_snapshot = crate::tasks::dependencies::DepAffectedSnapshot::from_ids_only(
                external_dep_affected.clone(),
            );
            sync_dep_affected_tasks(conn, &dep_snapshot, "cancelled tasks", "batch_cancel_tasks")
        },
    )?;
    let cancelled = output
        .after
        .get("after_states")
        .and_then(Value::as_array)
        .expect("Mutation contract: batch_cancel_tasks after_states stamped by apply")
        .clone();
    let dep_updated = fetch_existing_tasks_json(conn, &external_dep_affected)?;

    let response = serde_json::to_string(&json!({
        "cancelled_count": cancelled.len(),
        "cancelled": cancelled,
        "already_done": already_done,
        "dependency_updates": dep_updated,
        "next_occurrences": next_occurrences,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_cancel_tasks",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

#[cfg(test)]
mod tests;
