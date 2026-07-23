//! Shared invariant helpers used across Tauri IPC commands.
//!
//! ## ai_changelog ownership
//!
//! Tauri command write paths intentionally **do not** write to
//! `ai_changelog`. That table is reserved for AI/MCP-authored history
//! so the activity feed reflects assistant operations rather than
//! routine human UI actions. If a future surface needs an audit-trail
//! entry from a human-originated write, prefer the assistant pathway
//! (drive the change through MCP) so the existing AI changelog
//! invariants apply.
//!
//! All helpers under this module are called from Tauri command write
//! paths.

pub mod validation;
