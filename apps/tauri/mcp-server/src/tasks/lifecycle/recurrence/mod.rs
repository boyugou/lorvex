use crate::contract::{
    AddTaskRecurrenceExceptionArgs, RemoveTaskRecurrenceExceptionArgs, SetRecurrenceArgs,
};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{fetch_task_json, reload_task_json, utc_now_iso};
use crate::tasks::validation::validate_uuid_arg;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_store::repositories::task::recurrence;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_recurrence::{self, SetTaskRecurrenceInput, TaskRecurrenceRuleInput};
use rusqlite::Connection;
use serde_json::Value;

struct SetTaskRecurrenceMutation {
    input: SetTaskRecurrenceInput,
}

impl Mutation for SetTaskRecurrenceMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        fetch_task_json(conn, self.input.task_id.as_str())
            .map(Some)
            .map_err(mcp_error_to_store)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = task_recurrence::set_task_recurrence(conn, hlc, self.input.clone())?;
        Ok(MutationOutput::new(result.after_task, result.summary))
    }
}

struct AddTaskRecurrenceExceptionMutation {
    task_id: String,
    exception_date: String,
}

impl Mutation for AddTaskRecurrenceExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        fetch_task_json(conn, &self.task_id)
            .map(Some)
            .map_err(mcp_error_to_store)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = utc_now_iso();
        let version = hlc.next_version_string();
        let typed_task_id = TaskId::from_trusted(self.task_id.clone());
        recurrence::add_task_recurrence_exception(
            conn,
            &typed_task_id,
            &self.exception_date,
            &version,
            &now,
        )?;

        let after = reload_task_json(conn, &self.task_id, "add_task_recurrence_exception")
            .map_err(mcp_error_to_store)?;
        Ok(MutationOutput::new(
            after,
            format!("Added recurrence exception {}", self.exception_date),
        ))
    }
}

struct RemoveTaskRecurrenceExceptionMutation {
    task_id: String,
    exception_date: String,
}

impl Mutation for RemoveTaskRecurrenceExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        fetch_task_json(conn, &self.task_id)
            .map(Some)
            .map_err(mcp_error_to_store)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = utc_now_iso();
        let version = hlc.next_version_string();
        let typed_task_id = TaskId::from_trusted(self.task_id.clone());
        recurrence::remove_task_recurrence_exception(
            conn,
            &typed_task_id,
            &self.exception_date,
            &version,
            &now,
        )?;

        let after = reload_task_json(conn, &self.task_id, "remove_task_recurrence_exception")
            .map_err(mcp_error_to_store)?;
        Ok(MutationOutput::new(
            after,
            format!("Removed recurrence exception {}", self.exception_date),
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

pub(crate) fn set_recurrence(
    conn: &Connection,
    args: SetRecurrenceArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // `set_recurrence` now consumes the same
    // structured `RecurrenceRuleArgs` shape every other write surface
    // accepts, so range/cardinality/UNTIL gates live entirely inside
    // the canonical `normalize_task_recurrence`. The only piece this
    // arm still owns is the "rule resulted in empty after
    // normalization" guard — `set_recurrence` REQUIRES a recurrence
    // (clearing happens via `update_task` with `recurrence: null`).
    let SetRecurrenceArgs {
        id,
        rule,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "set_recurrence",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = validate_uuid_arg(&id, "id")?;
    let mutation = SetTaskRecurrenceMutation {
        input: SetTaskRecurrenceInput {
            task_id: TaskId::from_trusted(task_id.clone()),
            rule: TaskRecurrenceRuleInput {
                freq: rule.freq.as_canonical_str().to_string(),
                interval: rule.interval,
                byday: rule.byday,
                bymonth: rule.bymonth,
                bymonthday: rule.bymonthday,
                bysetpos: rule.bysetpos,
                wkst: rule.wkst,
                until: rule.until,
                count: rule.count,
            },
        },
    };
    let output = execute_mcp_mutation(conn, &mutation, "set_recurrence", task_id)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "set_recurrence",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

// ---------------------------------------------------------------------------
// Recurrence exception helpers
// ---------------------------------------------------------------------------

pub(crate) fn add_task_recurrence_exception(
    conn: &Connection,
    args: AddTaskRecurrenceExceptionArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let AddTaskRecurrenceExceptionArgs {
        task_id,
        exception_date,
        idempotency_key,
    } = args;

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "add_task_recurrence_exception",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = validate_uuid_arg(&task_id, "task_id")?;

    // validate the YYYY-MM-DD shape at the trust
    // boundary BEFORE the writer transaction, mirroring the
    // calendar `add_event_exception` discipline (#2928-H8). The
    // store helper does eventually parse the date, but a malformed
    // input would otherwise reach the SQL layer and surface as a
    // confusing parse error far from the bug site.
    lorvex_domain::validation::validate_date_format(&exception_date)?;

    let mutation = AddTaskRecurrenceExceptionMutation {
        task_id: task_id.clone(),
        exception_date,
    };
    let output = execute_mcp_mutation(conn, &mutation, "add_task_recurrence_exception", task_id)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "add_task_recurrence_exception",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn remove_task_recurrence_exception(
    conn: &Connection,
    args: RemoveTaskRecurrenceExceptionArgs,
) -> Result<String, McpError> {
    // Capture the canonical idempotency fingerprint BEFORE destructure
    // so a retry returns the cached response instead of re-stamping
    // the parent task's version and emitting another `update`
    // changelog row. Aligns with `add_task_recurrence_exception`'s
    // discipline.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let RemoveTaskRecurrenceExceptionArgs {
        task_id,
        exception_date,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "remove_task_recurrence_exception",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = validate_uuid_arg(&task_id, "task_id")?;

    // validate the YYYY-MM-DD shape at the trust
    // boundary, same discipline as `add_task_recurrence_exception`.
    lorvex_domain::validation::validate_date_format(&exception_date)?;

    let mutation = RemoveTaskRecurrenceExceptionMutation {
        task_id: task_id.clone(),
        exception_date,
    };
    let output =
        execute_mcp_mutation(conn, &mutation, "remove_task_recurrence_exception", task_id)?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "remove_task_recurrence_exception",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests;
