//! UI-shell Tauri commands: dock badge counter, MCP runtime status
//! pill, and generic window-management commands.
//!
//! Source: refactor for #3277 — flat `commands/{badge,
//! runtime_status,window_commands}.rs` were folded under this single
//! `ui/` namespace.

pub(crate) mod badge;
pub(crate) mod runtime_status;
pub(crate) mod window_commands;
