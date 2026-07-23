//! Connection-scoped write cores for the memory subsystem.
//!
//! Each `*_with_conn` function expects to run inside an
//! `IMMEDIATE` transaction owned by the Tauri command above it. The
//! cores share three contracts:
//!
//!   * Local writes always mint a fresh HLC through the
//!     [`crate::commands::shared::effects::execute_ipc_entity_mutation`]
//!     pipeline, so any LWW gate rejection ("stale write") means a
//!     peer applied a strictly-newer envelope between the mint and
//!     the UPDATE — surface that as a typed `Validation` error so
//!     the caller can re-stamp.
//!   * Every successful mutation enqueues a `memories` envelope plus
//!     a `memory_revisions` snapshot via the helpers in `enqueue`.
//!   * Human-owned reserved keys (currently `notes_for_ai`) route
//!     through dedicated cores; the generic `create` / `delete` cores
//!     reject them with a redirect error message.

use crate::commands::shared::effects::execute_ipc_entity_mutation;
use crate::commands::sync_timestamp_now;
use crate::error::AppError;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::memory::MEMORY_KEY_NOTES_FOR_AI;
use lorvex_domain::naming::{ENTITY_MEMORY, OP_DELETE, OP_UPSERT};
use lorvex_store::repositories::memory_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::enqueue::{
    enqueue_memory_delete_tombstone, enqueue_memory_revision_snapshot,
    enqueue_memory_upsert_snapshot,
};
use super::types::{
    CreateMemoryEntryResult, DeleteMemoryEntryResult, RestoreMemoryRevisionResult,
    SetNotesForAiResult,
};

/// Maximum character count for a user-supplied memory key. Kept tighter
/// than the MCP `MAX_KEY_LENGTH` (200) because human-seeded keys flow
/// through a short text field and are meant to stay readable as section
/// titles (#2415). Sourced from
/// `lorvex_domain::validation::MEMORY_KEY_MAX_CHARS` so the cap lives
/// next to the other KV-cap constants.
pub(super) const MAX_HUMAN_MEMORY_KEY_LENGTH: usize =
    lorvex_domain::validation::MEMORY_KEY_MAX_CHARS;

/// Key format: printable identifiers only. We reject whitespace,
/// slashes, and control chars so user-created keys stay safe to render
/// as section titles and to pass through MCP handlers that key-lookup
/// by string equality.
fn validate_human_memory_key(key: &str) -> Result<(), AppError> {
    if key.is_empty() {
        return Err(AppError::Validation(
            "Memory key must not be empty".to_string(),
        ));
    }
    if key.trim().len() != key.len() {
        return Err(AppError::Validation(
            "Memory key must not have leading or trailing whitespace".to_string(),
        ));
    }
    let char_count = key.chars().count();
    if char_count > MAX_HUMAN_MEMORY_KEY_LENGTH {
        return Err(AppError::Validation(format!(
            "Memory key exceeds maximum length ({char_count} chars, limit {MAX_HUMAN_MEMORY_KEY_LENGTH})"
        )));
    }
    for ch in key.chars() {
        if !(ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' || ch == '.') {
            return Err(AppError::Validation(
                "Memory key may only contain letters, numbers, '_', '-', or '.'".to_string(),
            ));
        }
    }
    if lorvex_domain::memory::is_human_owned_memory_key(key) {
        return Err(AppError::Validation(format!(
            "Use set_notes_for_ai to edit the reserved '{key}' key"
        )));
    }
    Ok(())
}

/// Descriptor for the `memories` upsert path. Wraps the
/// `memory_ops::upsert_memory_entry` workflow op and exposes the
/// resulting `revision_id` through `MutationOutput.after` so the
/// finalizer can enqueue both the materialized row and the
/// immutable revision snapshot.
struct UpsertMemoryEntryMutation<'a> {
    key: &'a str,
    content: &'a str,
    ownership: &'a str,
    now: &'a str,
}

impl<'a> Mutation for UpsertMemoryEntryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let result = lorvex_workflow::memory_ops::upsert_memory_entry(
            conn,
            self.key,
            self.content,
            self.ownership,
            &version,
            self.now,
        )?;
        match result {
            Some(result) => Ok(MutationOutput::new(
                serde_json::json!({
                    "key": self.key,
                    "revision_id": result.revision_id,
                    "applied": true,
                }),
                format!("Upserted memory entry '{}'", self.key),
            )),
            None => Ok(MutationOutput::new(
                serde_json::json!({ "key": self.key, "applied": false }),
                format!("Memory entry '{}' rejected by LWW gate", self.key),
            )),
        }
    }
}

/// Descriptor for `memory_ops::restore_memory_revision`. Mirrors the
/// `Upsert` shape — surfaces the resulting `revision_id` and the
/// `memory_key` the restore targeted so the finalizer can enqueue
/// both the upsert and the new revision snapshot.
struct RestoreMemoryRevisionMutation<'a> {
    revision_id: &'a str,
    ownership: &'a str,
    now: &'a str,
}

impl<'a> Mutation for RestoreMemoryRevisionMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }
    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let result = lorvex_workflow::memory_ops::restore_memory_revision(
            conn,
            self.revision_id,
            self.ownership,
            &version,
            self.now,
        )?;
        match result {
            Some(result) => Ok(MutationOutput::new(
                serde_json::json!({
                    "key": result.memory_key,
                    "revision_id": result.revision_id,
                    "applied": true,
                }),
                format!("Restored memory revision '{}'", self.revision_id),
            )),
            None => Ok(MutationOutput::new(
                serde_json::json!({ "applied": false }),
                format!(
                    "Memory revision '{}' rejected by LWW gate",
                    self.revision_id
                ),
            )),
        }
    }
}

/// Descriptor for the tombstone path. The pre-delete payload from
/// `memory_ops::delete_memory_entry` is surfaced through
/// `MutationOutput.after.pre_delete_payload` so the finalizer can
/// ship the typed `OP_DELETE` envelope with the canonical row shape
/// peers need to mint their own `before_json`.
struct DeleteMemoryEntryMutation<'a> {
    key: &'a str,
    ownership: &'a str,
    now: &'a str,
}

impl<'a> Mutation for DeleteMemoryEntryMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_MEMORY
    }
    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let result = lorvex_workflow::memory_ops::delete_memory_entry(
            conn,
            self.key,
            self.ownership,
            &version,
            self.now,
        )?;
        let Some(result) = result else {
            return Ok(MutationOutput::new(
                serde_json::json!({ "key": self.key, "deleted": false }),
                format!("Memory entry '{}' was already absent", self.key),
            ));
        };
        let pre_delete_payload = result.pre_delete_payload.clone().ok_or_else(|| {
            StoreError::Invariant(format!(
                "missing pre-delete memory payload for tombstone '{}'",
                result.memory_key
            ))
        })?;
        Ok(MutationOutput::new(
            serde_json::json!({
                "key": result.memory_key,
                "revision_id": result.revision_id,
                "pre_delete_payload": pre_delete_payload,
                "deleted": true,
            }),
            format!("Deleted memory entry '{}'", result.memory_key),
        ))
    }
}

pub(super) fn create_memory_entry_with_conn(
    conn: &rusqlite::Connection,
    key: &str,
    content: &str,
) -> Result<CreateMemoryEntryResult, AppError> {
    validate_human_memory_key(key)?;
    // Unicode hygiene (#2427) + length cap (#2429): mirror the checks
    // `set_notes_for_ai` applies so every human-authored memory entry —
    // whichever surface creates it — shares one validation pipeline.
    let content = lorvex_domain::sanitize_user_text(content);
    crate::invariants::validation::validate_memory_content(&content)?;

    // Reject creation over an existing key; callers should use a
    // dedicated update path if they want to overwrite. Keeps the UI
    // "+ Add memory" button predictable — it never silently replaces.
    if memory_repo::get_memory_entry(conn, key)
        .map_err(AppError::from)?
        .is_some()
    {
        return Err(AppError::Validation(format!(
            "Memory key '{key}' already exists"
        )));
    }

    let now = sync_timestamp_now();
    let mutation = UpsertMemoryEntryMutation {
        key,
        content: &content,
        ownership: "human",
        now: &now,
    };
    let output = execute_ipc_entity_mutation(conn, &mutation, |conn, execution| {
        if !execution
            .output
            .after
            .get("applied")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(());
        }
        enqueue_memory_upsert_snapshot(conn, key)?;
        let revision_id = execution
            .output
            .after
            .get("revision_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        enqueue_memory_revision_snapshot(conn, &revision_id)?;
        Ok(())
    })?;

    // the LWW gate rejects writes whose stamp is not
    // strictly newer than the stored row's version. Local writes always
    // generate a fresh HLC so the gate firing here means a peer applied
    // a strictly-newer envelope between this device's HLC mint and the
    // UPDATE — surface the typed stale error so the caller can re-stamp.
    if !output
        .after
        .get("applied")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        return Err(AppError::Validation(format!(
            "Memory key '{key}' was updated by another writer; please retry"
        )));
    }

    Ok(CreateMemoryEntryResult {
        key: key.to_string(),
        content,
        updated_at: now,
        ownership: "human".to_string(),
        created: true,
    })
}

pub(super) fn restore_memory_revision_with_conn(
    conn: &rusqlite::Connection,
    revision_id: &str,
) -> Result<RestoreMemoryRevisionResult, AppError> {
    let now = sync_timestamp_now();
    let mutation = RestoreMemoryRevisionMutation {
        revision_id,
        ownership: "human",
        now: &now,
    };
    let mut restored_key: Option<String> = None;
    let mut new_revision_id: Option<String> = None;
    let output = execute_ipc_entity_mutation(conn, &mutation, |conn, execution| {
        if !execution
            .output
            .after
            .get("applied")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(());
        }
        let key = execution
            .output
            .after
            .get("key")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        let rev = execution
            .output
            .after
            .get("revision_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        enqueue_memory_upsert_snapshot(conn, &key)?;
        enqueue_memory_revision_snapshot(conn, &rev)?;
        restored_key = Some(key);
        new_revision_id = Some(rev);
        Ok(())
    })?;

    if !output
        .after
        .get("applied")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        return Err(AppError::Validation(
            "Memory entry was updated by another writer; please retry the restore".to_string(),
        ));
    }

    Ok(RestoreMemoryRevisionResult {
        restored: true,
        key: restored_key.unwrap_or_default(),
        from_revision_id: revision_id.to_string(),
        new_revision_id: new_revision_id.unwrap_or_default(),
    })
}

pub(super) fn set_notes_for_ai_with_conn(
    conn: &rusqlite::Connection,
    content: &str,
) -> Result<SetNotesForAiResult, AppError> {
    // Unicode hygiene (#2427): scrub bidi overrides / zero-width / line
    // separators and NFC-normalize before storage. Notes flow to the
    // model at session start; invisible controls here would render
    // differently to the assistant than to the user.
    let content = lorvex_domain::sanitize_user_text(content);
    crate::invariants::validation::validate_memory_content(&content)?;
    let key = MEMORY_KEY_NOTES_FOR_AI;
    let now = sync_timestamp_now();
    let mutation = UpsertMemoryEntryMutation {
        key,
        content: &content,
        ownership: "human",
        now: &now,
    };
    let output = execute_ipc_entity_mutation(conn, &mutation, |conn, execution| {
        if !execution
            .output
            .after
            .get("applied")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(());
        }
        let revision_id = execution
            .output
            .after
            .get("revision_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        enqueue_memory_upsert_snapshot(conn, key)?;
        enqueue_memory_revision_snapshot(conn, &revision_id)?;
        Ok(())
    })?;

    if !output
        .after
        .get("applied")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        return Err(AppError::Validation(format!(
            "Memory key '{key}' was updated by another writer; please retry"
        )));
    }

    Ok(SetNotesForAiResult {
        key: key.to_string(),
        updated: true,
    })
}

fn delete_memory_entry_with_executor(
    conn: &rusqlite::Connection,
    key: &str,
) -> Result<DeleteMemoryEntryResult, AppError> {
    let now = sync_timestamp_now();
    let mutation = DeleteMemoryEntryMutation {
        key,
        ownership: "human",
        now: &now,
    };
    let output = execute_ipc_entity_mutation(conn, &mutation, |conn, execution| {
        if !execution
            .output
            .after
            .get("deleted")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(());
        }
        let memory_key = execution
            .output
            .after
            .get("key")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        let payload = execution
            .output
            .after
            .get("pre_delete_payload")
            .cloned()
            .ok_or_else(|| {
                AppError::Internal("missing pre-delete memory payload for tombstone".to_string())
            })?;
        let revision_id = execution
            .output
            .after
            .get("revision_id")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string();
        enqueue_memory_delete_tombstone(conn, &memory_key, &payload)?;
        enqueue_memory_revision_snapshot(conn, &revision_id)?;
        Ok(())
    })?;

    let deleted = output
        .after
        .get("deleted")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    Ok(DeleteMemoryEntryResult {
        key: key.to_string(),
        deleted,
    })
}

pub(super) fn delete_notes_for_ai_with_conn(
    conn: &rusqlite::Connection,
) -> Result<DeleteMemoryEntryResult, AppError> {
    delete_memory_entry_with_executor(conn, MEMORY_KEY_NOTES_FOR_AI)
}

pub(super) fn delete_ai_memory_entry_with_conn(
    conn: &rusqlite::Connection,
    key: &str,
) -> Result<DeleteMemoryEntryResult, AppError> {
    if lorvex_domain::memory::is_human_owned_memory_key(key) {
        return Err(AppError::Validation(format!(
            "Use delete_notes_for_ai to delete the '{key}' key"
        )));
    }
    delete_memory_entry_with_executor(conn, key)
}
