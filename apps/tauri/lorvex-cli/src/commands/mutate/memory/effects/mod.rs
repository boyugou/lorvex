//! Memory section CRUD with revision history.
//!
//! Memory sections are key/value text snippets that the AI maintains
//! across sessions. Each write produces a `memory_revisions` row so a
//! later turn can restore an earlier value. Human-owned keys (see
//! [`is_human_owned_memory_key`]) are reserved for the user's UI and
//! must not be overwritten through CLI mutations — `validate_memory_key`
//! rejects them up-front.
//!
//! The three top-level entry points (write / delete / restore) live in
//! sibling submodules; this `mod.rs` owns the shared result types,
//! validators, and outbox helpers they all reach for.

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::memory::{
    is_human_owned_memory_key, normalize_memory_key, MAX_MEMORY_CONTENT_LENGTH,
};
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION};
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use rusqlite::Connection;

mod delete;
mod restore;
mod write;

pub(crate) use delete::delete_memory_with_conn;
pub(crate) use restore::restore_memory_with_conn;
pub(crate) use write::write_memory_with_conn;

const MAX_MEMORY_KEY_LENGTH: usize = 200;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MemoryWriteResult {
    pub(crate) key: String,
    pub(crate) content: String,
    pub(crate) version: String,
    pub(crate) updated_at: String,
    pub(crate) revision_id: String,
    pub(crate) operation: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MemoryDeleteResult {
    pub(crate) key: String,
    pub(crate) deleted: bool,
    pub(crate) revision_id: Option<String>,
    pub(crate) before_content: Option<String>,
    pub(crate) before_updated_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MemoryRestoreResult {
    pub(crate) key: String,
    pub(crate) from_revision_id: String,
    pub(crate) new_revision_id: String,
}

/// Sanitize → trim → validate, mirroring `validate_habit_name`
/// (`commands::mutate::habits::effects`). The pipeline runs over the
/// sanitized input — bidi overrides, ZWSP, and other invisibles must
/// not pass through to the DB key column, where they would collide
/// visually with canonical AI-owned keys (`preferences.tone` vs
/// `preferences​.tone` with a ZWSP between `s` and `.`) while mismatching
/// on byte equality.
/// Returns the sanitized + trimmed key for the caller to persist
/// rather than the raw input.
pub(super) fn validate_memory_key(key: &str) -> Result<String, crate::error::CliError> {
    let normalized = normalize_memory_key(key);
    if normalized.is_empty() {
        return Err(crate::error::CliError::Validation(
            "memory key must not be empty".to_string(),
        ));
    }
    let char_count = normalized.chars().count();
    if char_count > MAX_MEMORY_KEY_LENGTH {
        return Err(crate::error::CliError::Validation(format!(
            "memory key exceeds maximum length ({char_count} chars, limit {MAX_MEMORY_KEY_LENGTH})"
        )));
    }
    if is_human_owned_memory_key(&normalized) {
        return Err(crate::error::CliError::Validation(format!(
            "memory key '{normalized}' is human-owned and cannot be changed through CLI memory commands"
        )));
    }
    Ok(normalized)
}

pub(super) fn validate_memory_content(content: &str) -> Result<String, crate::error::CliError> {
    let sanitized = lorvex_domain::sanitize_user_text(content);
    let char_count = sanitized.chars().count();
    if char_count > MAX_MEMORY_CONTENT_LENGTH {
        return Err(crate::error::CliError::Validation(format!(
            "memory content exceeds maximum length ({char_count} chars, limit {MAX_MEMORY_CONTENT_LENGTH})"
        )));
    }
    Ok(sanitized)
}

pub(super) fn enqueue_memory_upsert(
    conn: &Connection,
    device_id: &str,
    key: &str,
    content: &str,
    version: &str,
    updated_at: &str,
) -> Result<(), crate::error::CliError> {
    let payload = lorvex_store::payload_loaders::memory_payload(key, content, version, updated_at);
    enqueue_payload_upsert(
        conn,
        ENTITY_MEMORY,
        key,
        &payload,
        crate::commands::shared::bare_outbox_ctx(version, device_id),
    )?;
    Ok(())
}

pub(super) fn enqueue_memory_delete(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    key: &str,
    before_content: &str,
    before_version: &str,
    before_updated_at: &str,
) -> Result<(), crate::error::CliError> {
    let sync_version = hlc_state.generate().to_string();
    let payload = lorvex_store::payload_loaders::memory_payload(
        key,
        before_content,
        before_version,
        before_updated_at,
    );
    enqueue_payload_delete(
        conn,
        ENTITY_MEMORY,
        key,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&sync_version, device_id),
    )?;
    Ok(())
}

pub(crate) fn enqueue_memory_revision_upsert(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    revision_id: &str,
) -> Result<(), crate::error::CliError> {
    let typed_revision_id = lorvex_domain::MemoryRevisionId::from_trusted(revision_id.to_string());
    let payload =
        lorvex_store::payload_loaders::load_memory_revision_sync_payload(conn, &typed_revision_id)?
            .ok_or_else(|| {
                crate::error::CliError::NotFound(format!(
                    "memory revision '{revision_id}' not found for sync upsert"
                ))
            })?;
    // mint a FRESH HLC for the outbox envelope
    // distinct from the revision row's stored `version`.
    // site reused `version` for both the payload's identity field
    // and the outbox's coalescing key — but the outbox uses
    // `(entity_type, entity_id, version)` to dedupe in-flight
    // envelopes against late retries. Reusing the row's HLC meant a
    // subsequent CLI invocation that re-enqueued the same revision_id
    // (e.g. after a partial transport failure) would collide on
    // version, and the outbox would silently drop the retry as a
    // duplicate. Fresh HLC for the envelope keeps the row identity
    // (`payload.version`) and the transport identity
    // (`OutboxWriteContext.version`) on independent monotonic axes.
    let envelope_version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        ENTITY_MEMORY_REVISION,
        revision_id,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&envelope_version, device_id),
    )?;
    Ok(())
}
