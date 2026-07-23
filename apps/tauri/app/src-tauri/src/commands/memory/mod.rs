//! Memory subsystem of `commands`.
//!
//! The Tauri-side memory surface has four loosely coupled concerns;
//! each lives in its own sibling so they can be reasoned about
//! independently:
//!
//!   * `types` — wire structs surfaced over IPC (the seven result
//!     payloads `get_ai_memory`, `get_ai_memory_history`,
//!     `create_memory_entry`, `set_notes_for_ai`, `restore_memory_revision`,
//!     and the two delete commands return).
//!   * `enqueue` — sync-outbox helpers that fan out a successful
//!     mutation into a `memories` upsert/delete envelope plus a
//!     `memory_revisions` snapshot, so peers converge on both the
//!     materialized state and the immutable history.
//!   * `crud` — connection-scoped `*_with_conn` write cores that
//!     run inside the `IMMEDIATE` transaction owned by each command,
//!     handle LWW stale-rejection translation, and call the enqueue
//!     helpers on the success path. Houses the human-key validator
//!     and `MAX_HUMAN_MEMORY_KEY_LENGTH` (#2415, #2429).
//!   * `commands` — `#[tauri::command]` entry points that face the
//!     UI: open the connection, gate on `memory_lock`, drive the
//!     core inside `with_immediate_transaction`, drop diagnostics
//!     breadcrumbs for irreversible mutations, and emit the
//!     `AiMemory` data-changed event.
//!
//! `mod.rs` owns the `pub use commands::{…}` re-exports the parent
//! `commands.rs` barrel pulls forward to `lib.rs`.

pub(crate) mod commands;
mod crud;
mod enqueue;
mod types;

#[cfg(test)]
mod tests;
