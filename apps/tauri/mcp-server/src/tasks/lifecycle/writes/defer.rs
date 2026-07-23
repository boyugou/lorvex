use crate::contract::{DeferTaskArgs, MAX_SHORT_TEXT_LENGTH};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_task_reminder_syncs, execute_mcp_mutation_with_audit_finalizer,
};
use crate::system::handler_support::{
    fetch_task_json, reload_task_json, required_json_i64_field, required_json_string_field,
    utc_now_iso,
};
use crate::tasks::validation::sanitize_optional_user_text;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::TASK_SHIFTED_REMINDER_IDS;
use lorvex_workflow::task_deferral;
use rusqlite::Connection;
use serde_json::Value;

struct DeferTaskMutation {
    task_id: TaskId,
    normalized_until_date: String,
    reason: Option<String>,
    structured_reason: Option<String>,
    before: Value,
    before_ai_notes: String,
    new_ai_notes: String,
    now: String,
}

impl Mutation for DeferTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "defer"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let ai_notes_changed = self.new_ai_notes != self.before_ai_notes;
        let patch = task_deferral::TaskDeferralPatch {
            planned_date: Some(&self.normalized_until_date),
            ai_notes: ai_notes_changed.then_some(self.new_ai_notes.as_str()),
            last_defer_reason: self.structured_reason.as_deref(),
        };
        let result =
            task_deferral::defer_task(conn, &self.task_id, &patch, &version, &self.now, || {
                Ok::<String, StoreError>(hlc.next_version_string())
            })?;
        if !result.updated {
            return Err(StoreError::StaleVersion {
                entity: ENTITY_TASK,
                id: self.task_id.to_string(),
            });
        }

        let title = required_json_string_field(&self.before, "title", "defer_task before-task")
            .map_err(StoreError::Validation)?;
        let reason_part = self
            .reason
            .as_ref()
            .map(|r| format!(" — {r}"))
            .unwrap_or_default();
        let summary = format!(
            "Deferred '{title}' until {}{reason_part}",
            self.normalized_until_date
        );
        let after = reload_task_json(conn, self.task_id.as_str(), "task after defer (pre-stamp)")
            .map_err(mcp_error_to_store)?;
        let mut output = MutationOutput::new(after, summary);
        output.set_extra(
            &TASK_SHIFTED_REMINDER_IDS,
            Value::Array(
                result
                    .shifted_reminder_ids
                    .into_iter()
                    .map(Value::String)
                    .collect(),
            ),
        );
        Ok(output)
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

fn shifted_reminder_ids(execution: &MutationExecution) -> Result<Vec<String>, McpError> {
    let ids = execution
        .output
        .get_extra(&TASK_SHIFTED_REMINDER_IDS)
        .and_then(Value::as_array)
        .expect("Mutation contract: shifted reminder ids stamped by apply");
    ids.iter()
        .map(|value| {
            value.as_str().map(str::to_string).ok_or_else(|| {
                McpError::Internal(
                    "defer_task shifted reminder id extra contained a non-string value".to_string(),
                )
            })
        })
        .collect()
}

pub(crate) fn defer_task(conn: &Connection, args: DeferTaskArgs) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(id)` + `validate_optional_string_length(reason,
    // MAX_SHORT_TEXT_LENGTH)` calls. `structured_reason` enum check is
    // domain-membership and remains hand-rolled below.
    args.validate_shape()?;
    let DeferTaskArgs {
        id,
        until_date,
        reason,
        structured_reason,
        idempotency_key,
    } = args;
    let reason = sanitize_optional_user_text(reason, "reason", MAX_SHORT_TEXT_LENGTH)?;

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "defer_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let id = id.trim().to_string();
    if let Some(ref sr) = structured_reason {
        if !lorvex_domain::naming::is_valid_defer_reason(sr) {
            return Err(McpError::Validation(format!(
                "Invalid structured_reason '{}'. Valid values: {}",
                sr,
                lorvex_domain::naming::ALL_DEFER_REASONS.join(", ")
            )));
        }
    }
    let before = fetch_task_json(conn, &id)?;

    let before_status = required_json_string_field(&before, "status", "defer_task before-task")?;
    if before_status == STATUS_COMPLETED || before_status == STATUS_CANCELLED {
        return Err(McpError::Validation(format!(
            "Cannot defer a task with status '{before_status}'"
        )));
    }

    let before_defer_count =
        required_json_i64_field(&before, "defer_count", "defer_task before-task")?;
    let before_ai_notes = before
        .get("ai_notes")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string();

    let normalized_until_date =
        crate::tasks::support::normalize_due_date_input_for_conn(conn, until_date)?;

    let now = utc_now_iso();
    let new_defer_count = before_defer_count + 1;

    // MCP-specific: build ai_notes BEFORE the shared op so it's included atomically
    let new_ai_notes = reason.as_ref().map_or_else(
        || before_ai_notes.clone(),
        |reason_text| {
            let defer_note = format!("Deferred (#{new_defer_count}): {reason_text}");
            if before_ai_notes.trim().is_empty() {
                defer_note
            } else {
                format!("{before_ai_notes}\n\n{defer_note}")
            }
        },
    );

    let mutation = DeferTaskMutation {
        task_id: TaskId::from_trusted(id.clone()),
        normalized_until_date,
        reason,
        structured_reason,
        before,
        before_ai_notes,
        new_ai_notes,
        now,
    };
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "defer_task",
        id.clone(),
        McpError::from,
        |conn, execution| {
            let ids = shifted_reminder_ids(execution)?;
            enqueue_task_reminder_syncs(conn, &ids)
        },
    )?;

    let after = reload_task_json(conn, &id, "task after defer")?;
    let response = serde_json::to_string(&after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "defer_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
