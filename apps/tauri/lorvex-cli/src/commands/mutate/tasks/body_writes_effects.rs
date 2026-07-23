//! CLI mirrors of MCP task-mutation tools that don't fit
//! the patch-oriented `update_task_with_conn` model — appending to a
//! task's body, adding/appending AI notes
//! tool concatenates with a date prefix), and managing recurrence
//! exceptions on a recurring task.
//!
//! Each helper opens an immediate transaction, mints a single HLC
//! version, performs the row mutation through the canonical
//! `lorvex-store` helper, enqueues the parent task entity upsert
//! envelope (so peers see the row change via sync), writes the
//! `ai_changelog` audit row with before/after task snapshots, and
//! bumps `local_change_seq` so UI watchers tick.

use crate::commands::shared::{execute_cli_entity_mutation_map_store_error, load_task_row};
use crate::error::CliError;
use crate::hlc_guard::lock_shared;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_runtime::get_or_create_device_id;
use lorvex_store::repositories::task::read;
use lorvex_store::repositories::task::recurrence;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::TASK_ROW;
use lorvex_workflow::note_summary::note_summary;
use rusqlite::Connection;
use serde_json::Value;

// #3493: every CLI task descriptor in this file loads the in-tx
// post-mutation row inside `apply`, serializes it once, and stamps
// both `output.after` (for the audit funnel) and
// `output.extra[TASK_ROW]` (for the surface adapter to deserialize
// back into a typed `read::TaskRow` for the IPC return). The
// commit, which used the outer connection (not the just-committed
// `tx`) and could therefore see peer-arrived updates committed
// between our tx and the read — surfacing a row that was no longer
// the version we just wrote. Round-tripping through `extra` keeps
// the typed return semantically pinned to `output.after` and
// eliminates the extra SELECT.

fn map_task_stale_version(error: StoreError) -> CliError {
    match error {
        StoreError::StaleVersion { id, .. } => CliError::Conflict(format!(
            "task '{id}' was updated concurrently; please retry"
        )),
        other => CliError::from(other),
    }
}

/// MCP `append_to_task_body` analogue. Appends `text` to the task's
/// existing body separated by a blank line. Empty/whitespace-only
/// `text` is rejected before any DB write.
///
/// Phase 2 of #3452: routes the parent task UPDATE through the
/// `Mutation<T>` orchestrator. The descriptor owns the version mint,
/// the gated UPDATE, and the audit summary; the surrounding function
/// keeps transaction policy, the entity-upsert outbox enqueue, the
/// audit row write, and the `local_change_seq` bump.
struct AppendToTaskBodyMutation<'a> {
    task_id: &'a TaskId,
    text: &'a str,
    now: &'a str,
    title: &'a str,
    before_row: &'a read::TaskRow,
}

impl<'a> Mutation for AppendToTaskBodyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        serde_json::to_value(self.before_row)
            .map(Some)
            .map_err(|e| StoreError::Serialization(e.to_string()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        lorvex_workflow::lifecycle::append_to_task_body(
            conn,
            self.task_id,
            self.text,
            &version,
            self.now,
        )?;
        let after_row = load_task_row(conn, self.task_id).map_err(|e| match e {
            CliError::Store(err) => *err,
            other => StoreError::Invariant(format!("load_task_row: {other}")),
        })?;
        let after = serde_json::to_value(&after_row)
            .map_err(|e| StoreError::Serialization(e.to_string()))?;
        let summary = note_summary("Appended note to", self.title, self.text);
        let mut output = MutationOutput::new(after.clone(), summary);
        output.set_extra(&TASK_ROW, after);
        Ok(output)
    }
}

pub(crate) fn append_to_task_body_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    text: &str,
) -> Result<read::TaskRow, CliError> {
    // Sanitize bidi/zero-width chars before the emptiness check so a
    // string of invisible controls is rejected as empty (parity with
    // `mcp-server/src/tasks/lifecycle/writes/append_body.rs`).
    let text = lorvex_domain::sanitize_user_text(text).trim().to_string();
    if text.is_empty() {
        return Err(CliError::Validation("text must not be empty".to_string()));
    }
    lorvex_domain::validation::validate_body(&text)?;

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = load_task_row(&tx, task_id)?;
    let now = lorvex_domain::sync_timestamp_now();

    let mut hlc_guard = lock_shared(&tx)?;
    let title = before.core().title().to_string();
    let mutation = AppendToTaskBodyMutation {
        task_id,
        text: text.as_str(),
        now: now.as_str(),
        title: title.as_str(),
        before_row: &before,
    };

    let mut output = execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        task_id.as_str(),
        map_task_stale_version,
    )?;
    drop(hlc_guard);
    tx.commit()?;

    // #3493: round-trip the in-tx row stamped on `output.extra[TASK_ROW]`
    // back into a typed `TaskRow` instead of issuing a second SELECT
    // against `conn` after commit. The serialized snapshot is the
    // pre-stamp version we just wrote — no peer-arrived updates can
    // shadow it the way the old `load_task_row(conn, ...)` reload
    // path could.
    let row_json = output
        .take_extra(&TASK_ROW)
        .expect("Mutation contract: TASK_ROW stamped by apply");
    let after_row: read::TaskRow =
        serde_json::from_value(row_json).map_err(|e| StoreError::Serialization(e.to_string()))?;
    Ok(after_row)
}

/// Mutation descriptor for the CLI `add_ai_notes` write path.
///
/// Phase-1 migration of issue #3369: this is the first CLI write that
/// flows through the `lorvex_workflow::mutation` orchestrator. The
/// `apply` method owns the LWW-gated UPDATE and the post-fetch — the
/// surrounding `add_ai_notes_with_conn` keeps responsibility for the
/// transaction policy, the entity-payload outbox enqueue, the audit
/// row write, and the `local_change_seq` bump. Phase 2 will absorb
/// those steps into the orchestrator itself.
struct AddAiNotesMutation<'a> {
    task_id: &'a TaskId,
    /// Already-merged `{date}: {notes}` blob (the existing `ai_notes`
    /// concatenated with the new note + separator). Computed by the
    /// caller because the merge needs the pre-row body and the
    /// `Mutation` trait deliberately reserves `apply` for the SQL
    /// emission step.
    new_notes: &'a str,
    now: &'a str,
    title: &'a str,
    /// Trimmed, sanitized note build the audit summary
    /// preview. Threaded through the descriptor so the trait's
    /// `apply` does not re-derive it from `new_notes`.
    note_preview_source: &'a str,
    /// Pre-mutation row; reused by `pre_snapshot` so the orchestrator
    /// does not re-issue the SELECT the caller already paid for.
    before_row: &'a read::TaskRow,
}

impl<'a> Mutation for AddAiNotesMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        // The caller already loaded the pre-row to merge `ai_notes`;
        // reuse it rather than issuing a second SELECT inside the
        // orchestrator. `serde_json` errors map to `Serialization`.
        serde_json::to_value(self.before_row)
            .map(Some)
            .map_err(|e| StoreError::Serialization(e.to_string()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        lorvex_workflow::task_ai_notes::set_ai_notes_op(
            conn,
            self.task_id,
            Some(self.new_notes),
            &version,
            self.now,
        )?;

        let after_row = load_task_row(conn, self.task_id).map_err(|e| match e {
            CliError::Store(err) => *err,
            other => StoreError::Invariant(format!("load_task_row: {other}")),
        })?;
        let after = serde_json::to_value(&after_row)
            .map_err(|e| StoreError::Serialization(e.to_string()))?;
        let summary = note_summary("Added AI notes to", self.title, self.note_preview_source);
        let mut output = MutationOutput::new(after.clone(), summary);
        output.set_extra(&TASK_ROW, after);
        Ok(output)
    }
}

/// CLI AI-notes write. Concatenates `notes` onto the task's
/// existing `ai_notes`, dated with today's UTC date in `YYYY-MM-DD`
/// form, separated from any prior block with `\n\n---\n`.
pub(crate) fn add_ai_notes_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    notes: &str,
) -> Result<read::TaskRow, CliError> {
    let notes = lorvex_domain::sanitize_user_text(notes);
    let trimmed = notes.trim().to_string();
    if trimmed.is_empty() {
        return Err(CliError::Validation("notes must not be empty".to_string()));
    }
    // Length-cap the incoming note before concatenating.
    let char_count = notes.chars().count();
    if char_count > lorvex_domain::validation::MAX_BODY_LENGTH {
        return Err(CliError::Validation(format!(
            "notes too long ({char_count} chars, max {})",
            lorvex_domain::validation::MAX_BODY_LENGTH
        )));
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = load_task_row(&tx, task_id)?;

    let now = lorvex_domain::sync_timestamp_now();
    let date_part = now.split('T').next().unwrap_or("");
    let existing = before.core().ai_notes().unwrap_or_default();
    let new_notes = if existing.trim().is_empty() {
        format!("{date_part}: {notes}")
    } else {
        format!("{existing}\n\n---\n{date_part}: {notes}")
    };
    // Cap the combined body so peers don't see an over-length notes
    // field (parity with the MCP path which validates after merge).
    let combined_len = new_notes.chars().count();
    if combined_len > lorvex_domain::validation::MAX_BODY_LENGTH {
        return Err(CliError::Validation(format!(
            "ai_notes after append would be too long ({combined_len} chars, max {})",
            lorvex_domain::validation::MAX_BODY_LENGTH
        )));
    }

    let mut hlc_guard = lock_shared(&tx)?;
    let title = before.core().title().to_string();
    let mutation = AddAiNotesMutation {
        task_id,
        new_notes: new_notes.as_str(),
        now: now.as_str(),
        title: title.as_str(),
        note_preview_source: trimmed.as_str(),
        before_row: &before,
    };

    let mut output = execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        task_id.as_str(),
        map_task_stale_version,
    )?;
    drop(hlc_guard);
    tx.commit()?;

    // #3493: round-trip the in-tx row stamped on `output.extra[TASK_ROW]`
    // back into a typed `TaskRow` instead of issuing a second SELECT
    // against `conn` after commit. The serialized snapshot is the
    // pre-stamp version we just wrote — no peer-arrived updates can
    // shadow it the way the old `load_task_row(conn, ...)` reload
    // path could.
    let row_json = output
        .take_extra(&TASK_ROW)
        .expect("Mutation contract: TASK_ROW stamped by apply");
    let after_row: read::TaskRow =
        serde_json::from_value(row_json).map_err(|e| StoreError::Serialization(e.to_string()))?;
    Ok(after_row)
}

/// Add vs. remove discriminator for [`RecurrenceExceptionMutation`].
///
/// (`AddRecurrenceExceptionMutation` / `RemoveRecurrenceExceptionMutation`)
/// that only differed in the store helper they called and the verb in
/// the audit summary. Collapsed onto a single descriptor parameterized
/// by this enum so future tweaks (e.g. summary refinement, validation
/// changes) only have to land once.
#[derive(Clone, Copy, Debug)]
enum RecurrenceExceptionOp {
    Add,
    Remove,
}

/// Mutation descriptor for managing a task's recurrence exception set
/// via the CLI. Routes the parent task UPDATE through the orchestrator
/// so the version mint, the gated UPDATE, and the audit summary all
/// share the same path as the other CLI task writes (#3469).
///
/// #3479: a single descriptor handles both add and remove, branching on
/// `op` for the underlying store call and the audit verb.
struct RecurrenceExceptionMutation<'a> {
    op: RecurrenceExceptionOp,
    task_id: &'a TaskId,
    exception_date: &'a str,
    now: &'a str,
    title: &'a str,
    before_row: &'a read::TaskRow,
}

impl<'a> Mutation for RecurrenceExceptionMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        serde_json::to_value(self.before_row)
            .map(Some)
            .map_err(|e| StoreError::Serialization(e.to_string()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        match self.op {
            RecurrenceExceptionOp::Add => {
                recurrence::add_task_recurrence_exception(
                    conn,
                    self.task_id,
                    self.exception_date,
                    &version,
                    self.now,
                )?;
            }
            RecurrenceExceptionOp::Remove => {
                recurrence::remove_task_recurrence_exception(
                    conn,
                    self.task_id,
                    self.exception_date,
                    &version,
                    self.now,
                )?;
            }
        }
        let after_row = load_task_row(conn, self.task_id).map_err(|e| match e {
            CliError::Store(err) => *err,
            other => StoreError::Invariant(format!("load_task_row: {other}")),
        })?;
        let after = serde_json::to_value(&after_row)
            .map_err(|e| StoreError::Serialization(e.to_string()))?;
        let (verb, preposition) = match self.op {
            RecurrenceExceptionOp::Add => ("Added", "on"),
            RecurrenceExceptionOp::Remove => ("Removed", "from"),
        };
        let summary = format!(
            "{verb} recurrence exception {} {preposition} '{}'",
            self.exception_date, self.title
        );
        let mut output = MutationOutput::new(after.clone(), summary);
        output.set_extra(&TASK_ROW, after);
        Ok(output)
    }
}

/// MCP `add_task_recurrence_exception` analogue. Validates the date
/// shape at the trust boundary, then delegates to the canonical store
/// helper which enforces the rest (date is an actual occurrence, etc.).
pub(crate) fn add_task_recurrence_exception_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    exception_date: &str,
) -> Result<read::TaskRow, CliError> {
    lorvex_domain::validation::validate_date_format(exception_date)?;

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = load_task_row(&tx, task_id)?;
    let now = lorvex_domain::sync_timestamp_now();

    let mut hlc_guard = lock_shared(&tx)?;
    let title = before.core().title().to_string();
    let mutation = RecurrenceExceptionMutation {
        op: RecurrenceExceptionOp::Add,
        task_id,
        exception_date,
        now: now.as_str(),
        title: title.as_str(),
        before_row: &before,
    };

    let mut output = execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        task_id.as_str(),
        map_task_stale_version,
    )?;
    drop(hlc_guard);
    tx.commit()?;

    // #3493: round-trip the in-tx row stamped on `output.extra[TASK_ROW]`
    // back into a typed `TaskRow` instead of issuing a second SELECT
    // against `conn` after commit. The serialized snapshot is the
    // pre-stamp version we just wrote — no peer-arrived updates can
    // shadow it the way the old `load_task_row(conn, ...)` reload
    // path could.
    let row_json = output
        .take_extra(&TASK_ROW)
        .expect("Mutation contract: TASK_ROW stamped by apply");
    let after_row: read::TaskRow =
        serde_json::from_value(row_json).map_err(|e| StoreError::Serialization(e.to_string()))?;
    Ok(after_row)
}

/// MCP `remove_task_recurrence_exception` analogue.
pub(crate) fn remove_task_recurrence_exception_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    exception_date: &str,
) -> Result<read::TaskRow, CliError> {
    lorvex_domain::validation::validate_date_format(exception_date)?;

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = load_task_row(&tx, task_id)?;
    let now = lorvex_domain::sync_timestamp_now();

    let mut hlc_guard = lock_shared(&tx)?;
    let title = before.core().title().to_string();
    let mutation = RecurrenceExceptionMutation {
        op: RecurrenceExceptionOp::Remove,
        task_id,
        exception_date,
        now: now.as_str(),
        title: title.as_str(),
        before_row: &before,
    };

    let mut output = execute_cli_entity_mutation_map_store_error(
        &tx,
        &mut hlc_guard,
        &device_id,
        &mutation,
        task_id.as_str(),
        map_task_stale_version,
    )?;
    drop(hlc_guard);
    tx.commit()?;

    // #3493: round-trip the in-tx row stamped on `output.extra[TASK_ROW]`
    // back into a typed `TaskRow` instead of issuing a second SELECT
    // against `conn` after commit. The serialized snapshot is the
    // pre-stamp version we just wrote — no peer-arrived updates can
    // shadow it the way the old `load_task_row(conn, ...)` reload
    // path could.
    let row_json = output
        .take_extra(&TASK_ROW)
        .expect("Mutation contract: TASK_ROW stamped by apply");
    let after_row: read::TaskRow =
        serde_json::from_value(row_json).map_err(|e| StoreError::Serialization(e.to_string()))?;
    Ok(after_row)
}
