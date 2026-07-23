//! Typed IPC contract for the memory surface.
//!
//! Every memory write/read returns a typed `serde::Serialize` struct
//! rather than an untyped `serde_json::Value`, so a rename or removed
//! field is a compile error rather than a silent JSON drift caught
//! only by the hand-written TS interfaces. The structs here mirror
//! `app/src/lib/ipc/memory.ts` 1:1.

/// Single entry returned by `get_ai_memory`. Ownership is derived from
/// the most recent non-delete revision's actor (mirrors the SELECT
/// expression in the read query) so the UI can visually distinguish
/// AI-authored entries from user-seeded ones.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct AiMemoryEntry {
    pub key: String,
    pub content: String,
    pub updated_at: String,
    /// `"human"` or `"ai"`. Kept as `String` rather than an enum so
    /// the repository's `latest_actor` column can flow through without
    /// an extra mapping step at this boundary; validation lives in
    /// `is_human_owned_memory_key`.
    pub ownership: String,
}

/// Single revision row returned by `get_ai_memory_history.revisions`.
/// Mirrors `memory_revisions` schema columns the UI surfaces.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct MemoryRevisionEntry {
    pub id: String,
    pub memory_key: String,
    pub content: Option<String>,
    pub operation: String,
    pub source_revision_id: Option<String>,
    pub actor: String,
    pub version: String,
    pub created_at: String,
}

/// Envelope returned by `get_ai_memory_history`. `count` mirrors
/// `revisions.len()` for callers that don't want to recount on the
/// other side of the IPC boundary.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct MemoryRevisionList {
    pub key: String,
    pub count: usize,
    pub revisions: Vec<MemoryRevisionEntry>,
}

/// Result of `restore_memory_revision`. The new revision id is
/// returned alongside the source so the UI can chain a follow-up
/// "view history" without re-querying.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct RestoreMemoryRevisionResult {
    pub restored: bool,
    pub key: String,
    pub from_revision_id: String,
    pub new_revision_id: String,
}

/// Result of `create_memory_entry`. `created` is always `true` on
/// the success path — duplicates surface as a typed `Validation`
/// error before the result is constructed.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct CreateMemoryEntryResult {
    pub key: String,
    pub content: String,
    pub updated_at: String,
    /// Hard-coded to `"human"` (this command is the user-seeded path);
    /// MCP-side AI-authored writes use a different command.
    pub ownership: String,
    pub created: bool,
}

/// Result of `set_notes_for_ai`. `updated` is always `true` on the
/// success path — the LWW gate's stale rejection is surfaced as a
/// typed error, not a `false` payload.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct SetNotesForAiResult {
    pub key: String,
    pub updated: bool,
}

/// Result of `delete_notes_for_ai` and `delete_ai_memory_entry`.
/// `deleted = false` is the documented no-op path (the row was already
/// gone), distinct from a typed error.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct DeleteMemoryEntryResult {
    pub key: String,
    pub deleted: bool,
}
