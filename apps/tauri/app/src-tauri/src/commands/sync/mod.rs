//! Sync-domain Tauri commands: filesystem-bridge transport and the shared sync
//! runtime (outbox enqueue, apply pipeline, status readers, conflict log). The
//! parent `commands.rs` re-exports the public IPC entry points by name; deeper
//! helpers stay scoped behind the `sync::*` namespace so callers can't
//! accidentally reach into the wrong transport.
//!
//! Source: refactor for #3277 — sync_*.rs flat files at the
//! `commands/` root were folded under this single `sync/` namespace.

pub(crate) mod error_kind;
pub(crate) mod filesystem_bridge;
pub(crate) mod runtime;
