//! Tauri command entry points for the memory surface.
//!
//! Each handler is the thin IPC shell over a `*_with_conn` core in
//! `crud`: open the connection, gate on `memory_lock`, run the core
//! inside an `IMMEDIATE` transaction, optionally drop a diagnostics
//! breadcrumb, and emit the `AiMemory` data-changed event so the UI
//! refetches. The breadcrumb path is intentionally narrow — only
//! irreversible mutations (delete, restore) write to `error_logs`,
//! since the AI-only `ai_changelog` rule (CLAUDE.md) skips this
//! surface and a user reporting "my memory entry vanished" otherwise
//! finds nothing in Diagnostics.

use crate::commands::{sanitize_db_error, with_immediate_transaction};
use crate::db::{get_conn, get_read_conn};
use crate::event_bus;
use lorvex_domain::memory::MEMORY_KEY_NOTES_FOR_AI;

use super::crud::{
    create_memory_entry_with_conn, delete_ai_memory_entry_with_conn, delete_notes_for_ai_with_conn,
    restore_memory_revision_with_conn, set_notes_for_ai_with_conn,
};
use super::types::{
    AiMemoryEntry, CreateMemoryEntryResult, DeleteMemoryEntryResult, MemoryRevisionEntry,
    MemoryRevisionList, RestoreMemoryRevisionResult, SetNotesForAiResult,
};

/// emit an `info`-level breadcrumb to `error_logs`
/// for every irreversible Tauri-side memory mutation. The AI-only
/// `ai_changelog` rule (CLAUDE.md) is correctly skipped here, but
/// without a structured breadcrumb a user reporting "my memory entry
/// vanished" finds nothing in Diagnostics. This mirrors the
/// info-level pattern used in `commands/calendar_events/...` for
/// DST-ambiguity warnings.
fn log_memory_breadcrumb(conn: &rusqlite::Connection, action: &str, detail: &str) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "commands.memory",
        &format!("{action}: {detail}"),
        None,
        Some("info".to_string()),
    );
}

#[tauri::command]
pub fn get_ai_memory() -> Result<Vec<AiMemoryEntry>, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let conn = get_read_conn()?;

    // Ownership is derived from the actor of the most recent non-delete
    // revision. The `memories` table has no ownership column and the
    // reserved `notes_for_ai` key is always human-authored, so joining
    // against `memory_revisions` lets the UI distinguish assistant-
    // authored entries from ones the user seeded via create_memory_entry
    // without touching the schema (#2415).
    let mut stmt = conn
        .prepare(
            "SELECT m.key, m.content, m.updated_at, ( \
                 SELECT r.actor FROM memory_revisions r \
                 WHERE r.memory_key = m.key AND r.operation != 'delete' \
                 ORDER BY r.created_at DESC, r.id DESC \
                 LIMIT 1 \
             ) AS latest_actor \
             FROM memories m \
             ORDER BY m.key",
        )
        .map_err(|e| sanitize_db_error(&e))?;
    let entries: Vec<AiMemoryEntry> = stmt
        .query_map([], |row| {
            let key: String = row.get(0)?;
            let content: String = row.get(1)?;
            let updated_at: String = row.get(2)?;
            let latest_actor: Option<String> = row.get(3)?;
            let ownership = if lorvex_domain::memory::is_human_owned_memory_key(&key) {
                "human"
            } else {
                match latest_actor.as_deref() {
                    Some("human") => "human",
                    _ => "ai",
                }
            };
            Ok(AiMemoryEntry {
                key,
                content,
                updated_at,
                ownership: ownership.to_string(),
            })
        })
        .map_err(|e| sanitize_db_error(&e))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| sanitize_db_error(&e))?;
    Ok(entries)
}

#[tauri::command]
pub fn get_ai_memory_history(
    key: String,
    limit: Option<u32>,
) -> Result<MemoryRevisionList, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let conn = get_read_conn()?;
    let effective_limit = limit.unwrap_or(20).min(100);
    let typed_key = lorvex_domain::MemoryKey::from_trusted(key.clone());
    let revisions = lorvex_store::repositories::memory_revision_repo::get_revisions_for_key(
        &conn,
        &typed_key,
        effective_limit,
    )
    .map_err(|e| sanitize_db_error(&e))?;

    let revision_entries: Vec<MemoryRevisionEntry> = revisions
        .into_iter()
        .map(|r| MemoryRevisionEntry {
            id: r.id,
            memory_key: r.memory_key,
            content: r.content,
            operation: r.operation,
            source_revision_id: r.source_revision_id,
            actor: r.actor,
            version: r.version,
            created_at: r.created_at.as_string(),
        })
        .collect();

    Ok(MemoryRevisionList {
        key,
        count: revision_entries.len(),
        revisions: revision_entries,
    })
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn restore_memory_revision(revision_id: String) -> Result<RestoreMemoryRevisionResult, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    // revision ids are UUIDv7 — shape-check before the
    // writer so malformed values are rejected at the IPC boundary
    // instead of falling through to a "revision not found" path that
    // can't distinguish "id was wrong shape" from "no such row".
    let revision_id = crate::commands::shared::validate_uuid_id(&revision_id, "revision_id")?;
    let conn = get_conn()?;

    let result = with_immediate_transaction(&conn, |conn| {
        restore_memory_revision_with_conn(conn, &revision_id)
    })
    .map_err(String::from)?;
    log_memory_breadcrumb(&conn, "restore_memory_revision", &revision_id);
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    Ok(result)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn create_memory_entry(
    key: String,
    content: String,
) -> Result<CreateMemoryEntryResult, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let conn = get_conn()?;

    let result = with_immediate_transaction(&conn, |conn| {
        create_memory_entry_with_conn(conn, &key, &content)
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    Ok(result)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn set_notes_for_ai(content: String) -> Result<SetNotesForAiResult, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let conn = get_conn()?;

    let result =
        with_immediate_transaction(&conn, |conn| set_notes_for_ai_with_conn(conn, &content))
            .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    Ok(result)
}

#[tauri::command]
pub fn delete_notes_for_ai() -> Result<DeleteMemoryEntryResult, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    let conn = get_conn()?;

    let result =
        with_immediate_transaction(&conn, delete_notes_for_ai_with_conn).map_err(String::from)?;
    log_memory_breadcrumb(&conn, "delete_notes_for_ai", MEMORY_KEY_NOTES_FOR_AI);
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    Ok(result)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_ai_memory_entry(key: String) -> Result<DeleteMemoryEntryResult, String> {
    crate::memory_lock::require_unlocked()
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    if lorvex_domain::memory::is_human_owned_memory_key(&key) {
        return Err(format!("Use delete_notes_for_ai to delete the '{key}' key"));
    }
    let conn = get_conn()?;

    let result =
        with_immediate_transaction(&conn, |conn| delete_ai_memory_entry_with_conn(conn, &key))
            .map_err(String::from)?;
    log_memory_breadcrumb(&conn, "delete_ai_memory_entry", &key);
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    Ok(result)
}
