//! MCP-side executor adapter for [`lorvex_workflow::mutation::Mutation`].
//!
//! The workflow crate owns the mutation descriptor and ordering
//! contract; this adapter owns MCP-specific finalization: HLC session
//! creation, audit logging, sync enqueue, widget refresh, rate limiting,
//! and `local_change_seq` bump through `log_change`.
//!
//! # Internal architecture
//!
//! One core executor — [`execute_with`] — drives every single-emit MCP
//! write tool. It runs the [`lorvex_workflow::mutation::Mutation`]
//! inside an [`super::with_hlc_session`] transaction, lets the caller
//! compose the audit row via a `params_builder:
//! FnOnce(&MutationExecution) -> LogChangeParams`, and threads three
//! knobs through [`ExecuteOptions`]:
//!
//! - tombstone payloads (with the matching finalize-before-audit ordering
//!   and `deleted == false` short-circuit),
//! - conditional audit emission (for idempotent-link no-ops),
//! - finalize ordering.
//!
//! Multi-emit mutations — currently `batch_link_tasks_to_event` /
//! `batch_unlink_tasks_from_event` — route through the sibling
//! [`execute_with_audit_entries`], which loops the per-entry audit
//! writes inside the same HLC envelope.
//!
//! # Per-shape delegates
//!
//! The [`delegates`] sibling exposes per-shape names
//! (`execute_mcp_mutation`, `*_with_audit_finalizer`,
//! `*_with_tombstone_audit_finalizer`, …) that compose [`execute_with`]
//! with the appropriate [`ExecuteOptions`] and params builder. Call
//! sites read at face value as a single named operation while the audit
//! / finalize / tombstone semantics live in one place. Under the hood
//! every delegate is a one-call wrapper.
//!
//! # File layout
//!
//! - [`audit_entry`] — `MutationAuditEntry` (per-entity audit row for
//!   multi-emit mutations).
//! - [`options`] — `ExecuteOptions`, `TombstonePayloads`, and the
//!   canonical `TOMBSTONE_DELETED_KEY` gate.
//! - [`core`] — the three core executor entry points.
//! - [`delegates`] — per-shape delegate fns kept on top of [`core`].
//! - [`params`] — shared `LogChangeParams` builders.

mod audit_entry;
mod core;
mod delegates;
mod options;
mod params;

pub(crate) use audit_entry::MutationAuditEntry;
pub(crate) use core::execute_mcp_mutation_with_finalizer;
pub(crate) use delegates::{
    execute_mcp_batch_mutation_with_audit_finalizer,
    execute_mcp_batch_mutation_with_undo_audit_finalizer, execute_mcp_mutation,
    execute_mcp_mutation_with_audit_entries_finalizer, execute_mcp_mutation_with_audit_finalizer,
    execute_mcp_mutation_with_dynamic_audit_finalizer,
    execute_mcp_mutation_with_skip_sync_audit_finalizer,
    execute_mcp_mutation_with_skippable_audit_finalizer,
    execute_mcp_mutation_with_tombstone_audit_finalizer,
    execute_mcp_mutation_with_undo_tombstone_audit_finalizer,
};
