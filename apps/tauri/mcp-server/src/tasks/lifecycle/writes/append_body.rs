use crate::contract::{AppendToTaskBodyArgs, MAX_BODY_LENGTH};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{fetch_task_json, utc_now_iso};
use crate::tasks::validation::validate_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::note_summary::note_summary;
use rusqlite::Connection;
use serde_json::Value;

/// Mutation descriptor for the MCP `append_to_task_body` tool — Phase
/// 2 migration of #3452. Same shape as [`AddAiNotesMutation`]: the
/// `Mutation` impl owns the version mint, the gated UPDATE (delegated
/// to `lorvex_workflow::lifecycle::append_to_task_body`), the
/// post-fetch, and the audit summary; the surrounding handler keeps
/// validation, idempotency, and the audit-funnel call.
struct AppendToTaskBodyMutation<'a> {
    task_id: &'a str,
    text: &'a str,
    now: &'a str,
}

impl<'a> Mutation for AppendToTaskBodyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        fetch_task_json(conn, self.task_id)
            .map(Some)
            .map_err(|e| StoreError::Invariant(format!("fetch_task_json: {e}")))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let task_id_typed = lorvex_domain::TaskId::from_trusted(self.task_id.to_string());
        lorvex_workflow::lifecycle::append_to_task_body(
            conn,
            &task_id_typed,
            self.text,
            &version,
            self.now,
        )?;

        let after = fetch_task_json(conn, self.task_id)
            .map_err(|e| StoreError::Invariant(format!("fetch_task_json: {e}")))?;
        let title = after.get("title").and_then(Value::as_str).unwrap_or("task");
        let summary = note_summary("Appended note to", title, self.text);
        Ok(MutationOutput::new(after, summary))
    }
}

pub(crate) fn append_to_task_body(
    conn: &Connection,
    args: AppendToTaskBodyArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(id)` + raw-text length check.
    args.validate_shape()?;
    let AppendToTaskBodyArgs {
        id: task_id,
        text,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "append_to_task_body",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = task_id.trim().to_string();
    // Unicode hygiene (#2427): scrub bidi overrides / zero-width / line
    // separators and normalize to NFC before the emptiness check, so a string
    // consisting entirely of invisible controls is rejected as empty.
    let text = lorvex_domain::sanitize_user_text(&text).trim().to_string();
    if text.is_empty() {
        return Err(McpError::Validation("text must not be empty".to_string()));
    }
    validate_string_length(&text, "text", MAX_BODY_LENGTH)?;

    let now = utc_now_iso();

    let mutation = AppendToTaskBodyMutation {
        task_id: task_id.as_str(),
        text: text.as_str(),
        now: now.as_str(),
    };

    let output = execute_mcp_mutation(conn, &mutation, "append_to_task_body", task_id.clone())?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "append_to_task_body",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
