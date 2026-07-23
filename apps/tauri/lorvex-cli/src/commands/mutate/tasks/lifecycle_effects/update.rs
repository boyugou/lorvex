//! CLI adapter for the canonical task-update workflow.
//!
//! Routes the single-row update through
//! [`lorvex_workflow::task_update::update_task`] — the same canonical
//! entry point MCP (`mcp-server/src/tasks/mutations/update/mod.rs`)
//! and Tauri (`app/src-tauri/src/commands/tasks/updates/command.rs`)
//! call — and flushes the resulting [`TaskUpdateSyncEffects`] via
//! [`CliTaskUpdateFlush`]. Every consumer surface therefore writes
//! byte-identical row, edge, and outbox state for the same patch.
//!
//! Surface conventions:
//!   * The CLI accepts incremental dependency patches
//!     (`depends_on_set` / `depends_on_add` / `depends_on_remove`) and
//!     forwards them directly to the canonical
//!     [`TaskUpdateInput`] (`depends_on` / `depends_on_add` /
//!     `depends_on_remove`). The canonical preparation layer owns the
//!     replace-vs-incremental precedence and the merge against the
//!     row's current edge set — every surface (MCP, Tauri, CLI)
//!     therefore produces byte-identical audit trails and undo bundles
//!     for the same patch.
//!   * The keyed task id is registered in `executor_handled_ids` so
//!     the flush backend does not double-enqueue when the canonical
//!     `task_upsert_ids` lists it.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::{Patch, TaskId};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::task::read;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::enqueue_entity_upsert;
use lorvex_workflow::task_update::{self, flush_with_backend, TaskUpdateInput};
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::hlc_guard::{lock_shared, CliHlcStateHandle};

use super::canonical_flush::CliTaskUpdateFlush;
use super::dependencies;
use super::update_validation::TaskUpdateFields;
use crate::commands::mutate::tags::effects as tags;
use crate::commands::shared::idempotency::{lookup_cli_idempotency, record_cli_idempotency};
use crate::commands::shared::{load_task_row, log_cli_changelog_with_state, CliChangelogParams};

pub(crate) fn update_task_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    // Pass by reference: every field on `TaskUpdateFields` is a small
    // `Option<&'a str>` / `Patch<…>` / `Option<bool>`, so the body doesn't
    // need to consume the struct — and at ~328 bytes, moving the struct
    // by value triggers clippy's `large_types_passed_by_value` on the
    // pedantic profile. Borrowing copies an 8-byte pointer instead.
    fields: &TaskUpdateFields<'_>,
) -> Result<read::TaskRow, crate::error::CliError> {
    if !fields.has_any_patch() {
        return Err(crate::error::CliError::Validation(
            "update requires at least one field flag".to_string(),
        ));
    }

    // Reject the both-shapes-in-one-patch combo at the CLI boundary so
    // the error message names CLI flags rather than canonical field
    // names. Canonical itself enforces the same invariants but with
    // generic field-named messages.
    tags::validate_task_tag_count(fields.tags_set)?;
    tags::validate_task_tag_count(fields.tags_add)?;
    tags::validate_task_tag_count(fields.tags_remove)?;
    dependencies::validate_task_dependency_count(fields.depends_on_set)?;
    dependencies::validate_task_dependency_count(fields.depends_on_add)?;
    dependencies::validate_task_dependency_count(fields.depends_on_remove)?;
    if fields.depends_on_set.is_some()
        && (fields.depends_on_add.is_some() || fields.depends_on_remove.is_some())
    {
        return Err(crate::error::CliError::Validation(
            "use either --depends-on-set/--clear-depends-on or --depends-on-add/--depends-on-remove, not both".to_string(),
        ));
    }

    let device_id = get_or_create_device_id(conn)?;
    let request_repr = update_request_repr(task_id, fields)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;

    // Mirror the MCP `update_task` cache: a retry with the same key
    // returns the cached row instead of replaying the additive
    // `tags_add` / `depends_on_add` patches and writing a second
    // audit row for one logical edit.
    if let Some(cached) =
        lookup_cli_idempotency(&tx, "update_task", fields.idempotency_key, &request_repr)?
    {
        let cached_row: read::TaskRow = serde_json::from_str(&cached).map_err(|e| {
            crate::error::CliError::Validation(format!(
                "cached update_task response could not be decoded: {e}"
            ))
        })?;
        tx.rollback()?;
        return Ok(cached_row);
    }

    let input = TaskUpdateInput {
        id: task_id.as_str().to_string(),
        // The CLI surface does not expose a "clear" gesture for any of
        // these (status/list_id/title are NOT NULL columns; raw_input
        // is nullable but the CLI offers no flag to clear it today), so
        // every `Some` maps to `Patch::Set` and `None` maps to
        // `Patch::Unset`. The canonical workflow rejects `Patch::Clear`
        // for title/status/list_id at the validator boundary.
        title: fields
            .title
            .map(str::to_string)
            .map(Patch::Set)
            .unwrap_or(Patch::Unset),
        body: fields.body.clone().map(str::to_string),
        raw_input: fields
            .raw_input
            .map(str::to_string)
            .map(Patch::Set)
            .unwrap_or(Patch::Unset),
        ai_notes: fields.ai_notes.clone().map(str::to_string),
        status: fields
            .status
            .map(str::to_string)
            .map(Patch::Set)
            .unwrap_or(Patch::Unset),
        list_id: fields
            .list_id
            .map(str::to_string)
            .map(Patch::Set)
            .unwrap_or(Patch::Unset),
        tags_set: fields.tags_set.map(<[String]>::to_vec),
        tags_add: fields.tags_add.map(<[String]>::to_vec),
        tags_remove: fields.tags_remove.map(<[String]>::to_vec),
        priority: fields.priority.clone().try_map(|value| {
            u8::try_from(value).map_err(|_| {
                crate::error::CliError::Validation(format!("priority must be 0..=4, got {value}"))
            })
        })?,
        due_date: fields.due_date.clone().map(str::to_string),
        due_time: fields.due_time.clone().map(str::to_string),
        estimated_minutes: minutes_patch("estimated_minutes", &fields.estimated_minutes)?,
        recurrence: parse_recurrence_patch(&fields.recurrence)?,
        depends_on: fields.depends_on_set.map(<[String]>::to_vec),
        depends_on_add: fields.depends_on_add.map(<[String]>::to_vec),
        depends_on_remove: fields.depends_on_remove.map(<[String]>::to_vec),
        planned_date: fields.planned_date.clone().map(str::to_string),
    };

    let mut hlc_guard = lock_shared(&tx)?;
    let outcome = {
        let handle = CliHlcStateHandle::new(&mut hlc_guard);
        let session = HlcSession::new(&handle);
        task_update::update_task(&tx, &session, input).map_err(map_update_store_error)?
    };

    let task_id_string = task_id.as_str().to_string();
    let executor_handled_ids = vec![task_id_string.clone()];
    {
        let backend = CliTaskUpdateFlush::new(&device_id, &executor_handled_ids, &mut hlc_guard);
        flush_with_backend(&tx, &outcome.sync_effects, &backend)?;
    }

    enqueue_entity_upsert(
        &tx,
        ENTITY_TASK,
        &task_id_string,
        &mut hlc_guard,
        &device_id,
    )?;
    log_cli_changelog_with_state(
        &tx,
        &mut hlc_guard,
        CliChangelogParams {
            operation: "update",
            entity_type: ENTITY_TASK,
            entity_id: &task_id_string,
            summary: &outcome.summary,
            before_json: Some(outcome.before_task.clone()),
            after_json: Some(outcome.updated_task.clone()),
        },
    )?;
    bump_local_change_seq(&tx)?;
    drop(hlc_guard);
    let updated = load_task_row(&tx, task_id)?;
    let response = serde_json::to_string(&updated).map_err(|e| {
        crate::error::CliError::Validation(format!(
            "update_task response could not be serialized: {e}"
        ))
    })?;
    record_cli_idempotency(
        &tx,
        "update_task",
        fields.idempotency_key,
        &request_repr,
        &response,
    )?;
    tx.commit()?;
    Ok(updated)
}

/// Canonicalize the request shape so a retry with the same flags
/// produces a byte-identical checksum. Mirrors the MCP server's
/// `canonical_request_repr` for `update_task` — only field-bearing
/// flags are included, in serde-canonical order.
fn update_request_repr(
    task_id: &TaskId,
    fields: &TaskUpdateFields<'_>,
) -> Result<String, crate::error::CliError> {
    let mut args = serde_json::Map::new();
    args.insert("id".to_string(), json!(task_id.as_str()));
    if let Some(value) = fields.title {
        args.insert("title".to_string(), json!(value));
    }
    insert_patch_str(&mut args, "body", &fields.body);
    insert_patch_str(&mut args, "ai_notes", &fields.ai_notes);
    if let Some(value) = fields.status {
        args.insert("status".to_string(), json!(value));
    }
    if let Some(value) = fields.raw_input {
        args.insert("raw_input".to_string(), json!(value));
    }
    if let Some(value) = fields.list_id {
        args.insert("list_id".to_string(), json!(value));
    }
    insert_patch_i64(&mut args, "priority", &fields.priority);
    insert_patch_str(&mut args, "due_date", &fields.due_date);
    insert_patch_str(&mut args, "due_time", &fields.due_time);
    insert_patch_str(&mut args, "planned_date", &fields.planned_date);
    insert_patch_i64(&mut args, "estimated_minutes", &fields.estimated_minutes);
    insert_patch_str(&mut args, "recurrence", &fields.recurrence);
    if let Some(value) = fields.tags_set {
        args.insert("tags_set".to_string(), json!(value));
    }
    if let Some(value) = fields.tags_add {
        args.insert("tags_add".to_string(), json!(value));
    }
    if let Some(value) = fields.tags_remove {
        args.insert("tags_remove".to_string(), json!(value));
    }
    if let Some(value) = fields.depends_on_set {
        args.insert("depends_on".to_string(), json!(value));
    }
    if let Some(value) = fields.depends_on_add {
        args.insert("depends_on_add".to_string(), json!(value));
    }
    if let Some(value) = fields.depends_on_remove {
        args.insert("depends_on_remove".to_string(), json!(value));
    }
    if let Some(value) = fields.idempotency_key {
        args.insert("idempotency_key".to_string(), json!(value));
    }
    lorvex_domain::canonical_json::canonicalize_json(&Value::Object(args)).map_err(|e| {
        crate::error::CliError::Validation(format!(
            "idempotency request canonicalization failed: {e}"
        ))
    })
}

fn insert_patch_str(args: &mut serde_json::Map<String, Value>, key: &str, patch: &Patch<&str>) {
    match patch {
        Patch::Set(value) => {
            args.insert(key.to_string(), json!(*value));
        }
        Patch::Clear => {
            args.insert(key.to_string(), Value::Null);
        }
        Patch::Unset => {}
    }
}

fn insert_patch_i64(args: &mut serde_json::Map<String, Value>, key: &str, patch: &Patch<i64>) {
    match patch {
        Patch::Set(value) => {
            args.insert(key.to_string(), json!(*value));
        }
        Patch::Clear => {
            args.insert(key.to_string(), Value::Null);
        }
        Patch::Unset => {}
    }
}

/// Decode the CLI's `--recurrence` / `--clear-recurrence` flags into
/// the canonical [`Patch<Value>`]. The JSON string is parsed into a
/// structured `serde_json::Value`; the canonical preparation layer
/// runs the `normalize_task_recurrence` gate against it.
fn parse_recurrence_patch(patch: &Patch<&str>) -> Result<Patch<Value>, crate::error::CliError> {
    match patch {
        Patch::Set(raw) => {
            let parsed: Value = serde_json::from_str(raw).map_err(|e| {
                crate::error::CliError::Validation(format!(
                    "--recurrence must be a JSON object describing a RecurrenceRuleArgs: {e}"
                ))
            })?;
            if !parsed.is_object() {
                return Err(crate::error::CliError::Validation(
                    "--recurrence must be a JSON object (e.g. {\"freq\":\"weekly\",\"interval\":2,\"byday\":[\"MO\"]})".to_string(),
                ));
            }
            Ok(Patch::Set(parsed))
        }
        Patch::Clear => Ok(Patch::Clear),
        Patch::Unset => Ok(Patch::Unset),
    }
}

fn minutes_patch(
    field: &'static str,
    value: &Patch<i64>,
) -> Result<Patch<u32>, crate::error::CliError> {
    value.clone().try_map(|minutes| {
        u32::try_from(minutes).map_err(|_| {
            crate::error::CliError::Validation(format!(
                "{field} must be a non-negative integer (got {minutes})"
            ))
        })
    })
}

fn map_update_store_error(error: StoreError) -> crate::error::CliError {
    match error {
        StoreError::Validation(message) => crate::error::CliError::Validation(message),
        other => crate::error::CliError::from(other),
    }
}
