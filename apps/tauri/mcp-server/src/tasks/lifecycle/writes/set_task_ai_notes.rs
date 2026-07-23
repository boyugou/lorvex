use crate::contract::{SetTaskAiNotesArgs, MAX_AI_NOTES_LENGTH};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{fetch_task_json, utc_now_iso};
use crate::tasks::validation::validate_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::note_summary::note_summary;
use rusqlite::Connection;
use serde_json::Value;

/// Mutation descriptor for the MCP `set_task_ai_notes` tool.
struct SetTaskAiNotesMutation<'a> {
    task_id: &'a TaskId,
    notes: &'a str,
    now: &'a str,
}

impl<'a> Mutation for SetTaskAiNotesMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        // The MCP error surface is wider than `StoreError`; map the
        // `fetch_task_json` failure into a store invariant so the trait
        // stays pinned to a single error type. The call site preserves
        // typed store variants such as `StaleVersion` instead of
        // flattening them into an internal error.
        fetch_task_json(conn, self.task_id.as_str())
            .map(Some)
            .map_err(|e| StoreError::Invariant(format!("fetch_task_json: {e}")))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        // Mint the parent-row HLC stamp through the shared session so
        // peers' LWW reconciliation accepts the change.
        // call went through the surface-specific `generate_hlc_version`
        // helper which re-locked the process-wide mutex per stamp.
        let version = hlc.next_version().to_string();
        let trimmed = self.notes.trim();
        let notes = if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        };
        lorvex_workflow::task_ai_notes::set_ai_notes_op(
            conn,
            self.task_id,
            notes,
            &version,
            self.now,
        )?;

        let after = fetch_task_json(conn, self.task_id.as_str())
            .map_err(|e| StoreError::Invariant(format!("fetch_task_json: {e}")))?;
        let title = after.get("title").and_then(Value::as_str).unwrap_or("task");
        let summary = if trimmed.is_empty() {
            note_summary("Cleared AI context for", title, "")
        } else {
            note_summary("Updated AI context for", title, self.notes)
        };
        Ok(MutationOutput::new(after, summary))
    }
}

pub(crate) fn set_task_ai_notes(
    conn: &Connection,
    args: SetTaskAiNotesArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation at the trust boundary
    // covers the prior hand-rolled `validate_uuid_arg(id)` +
    // `validate_string_length(notes, MAX_AI_NOTES_LENGTH)` calls.
    args.validate_shape()?;
    let SetTaskAiNotesArgs {
        id: task_id,
        notes,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "set_task_ai_notes",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = task_id.trim().to_string();
    // Unicode hygiene (#2427): scrub bidi overrides / zero-width / line
    // separators and normalize to NFC before storage.
    let notes = lorvex_domain::sanitize_user_text(&notes);
    // sanitize_user_text may NFC-normalize, changing byte length;
    // re-validate to catch this edge case (#3683). A pre-sanitize
    // length check is insufficient because NFC composition can grow
    // OR shrink the byte length depending on the input grapheme set,
    // so we re-anchor the cap on the post-sanitize string the DB
    // actually stores.
    validate_string_length(&notes, "notes", MAX_AI_NOTES_LENGTH)?;

    let now = utc_now_iso();
    let typed_task_id = TaskId::from_trusted(task_id.clone());
    let mutation = SetTaskAiNotesMutation {
        task_id: &typed_task_id,
        notes: notes.as_str(),
        now: now.as_str(),
    };

    let output = execute_mcp_mutation(conn, &mutation, "set_task_ai_notes", task_id)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "set_task_ai_notes",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
