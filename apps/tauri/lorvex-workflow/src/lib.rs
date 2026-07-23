// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-workflow` — shared cross-surface workflow operations.
//!
//! This crate sits between the storage layer (`lorvex-store`) and the
//! surface adapters that consume it (Tauri commands, MCP server tools,
//! CLI handlers, sync apply pipeline). It owns the canonical SQL
//! mutations and business rules — validation, status side-effects,
//! version stamping via the caller-provided HLC, changelog projection
//! payloads — that every surface must share to stay convergent.
//!
//! Layering:
//!
//! ```text
//! lorvex-domain  →  lorvex-store  →  lorvex-workflow  ←  {tauri, mcp, cli, sync}
//! ```
//!
//! A handful of SQL primitives intentionally remain in `lorvex-store`
//! (`current_focus_items`, `daily_review_ops`, `focus_schedule_blocks`)
//! because the store's own import/aggregate paths call them directly;
//! moving them up would create a `store ↔ workflow` dependency cycle.

pub mod calendar_event;
pub mod calendar_normalization;
pub mod calendar_recurrence_scope;
pub mod calendar_subscription;
pub mod current_focus;
pub mod daily_review_date;
pub mod dependency_validation;
pub mod habit_reminder_ops;
pub mod habit_reminder_policy;
pub mod lifecycle;
pub mod list_reorganize;
pub mod memory_ops;
pub mod mutation;
pub mod mutation_extras;
pub mod note_summary;
pub mod overview;
pub mod recurrence_config;
pub mod reminder_anchor;
pub mod reseed;
pub mod status_side_effects;
pub mod task_ai_notes;
pub mod task_archive;
pub mod task_batch_cancel;
pub mod task_batch_create;
pub mod task_batch_update;
pub mod task_checklist;
pub mod task_create;
pub mod task_deferral;
pub mod task_dependency_edges;
pub mod task_enrichment;
pub mod task_lifecycle_undo;
pub mod task_permanent_delete;
pub mod task_recurrence;
pub mod task_reminders;
pub mod task_response;
pub mod task_update;
pub mod timezone;
pub mod weekly_review;
