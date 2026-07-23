//! Surface-agnostic lifecycle wrappers.
//!
//! Both MCP and Tauri repeatedly built the same shape: mint an HLC
//! stamp for the reminder side-effects, then forward to the relevant
//! `apply_*_transition` orchestrator. Pull that pattern in here so
//! the two surfaces share one canonical implementation.
//!
//! Each helper takes a borrowed [`HlcSession`] (the per-mutation HLC
//! handle established at the surface boundary — Tauri's
//! `with_hlc_session`, the MCP `Mutation::apply` orchestrator, or the
//! CLI mutation executor). Surfaces convert the resulting
//! `StoreError` into their own error type at the call site via `?`.

use rusqlite::Connection;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::{naming::TaskStatus, TaskId};
use lorvex_store::StoreError;

use crate::lifecycle::{
    apply_cancel_transition, apply_completion_transition, apply_lifecycle_transition,
    apply_reopen_transition, CancelLifecycleTransitionResult, CompletionLifecycleTransitionResult,
    LifecycleTransitionResult, ReopenLifecycleTransitionResult,
};

pub fn run_completion(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    hlc: &HlcSession<'_>,
) -> Result<CompletionLifecycleTransitionResult, StoreError> {
    let reminder_ver = hlc.next_version_string();
    apply_completion_transition(conn, task_id, now, &reminder_ver)
}

pub fn run_cancel(
    conn: &Connection,
    task_id: &TaskId,
    now: &str,
    cancel_series: bool,
    hlc: &HlcSession<'_>,
) -> Result<CancelLifecycleTransitionResult, StoreError> {
    let reminder_ver = hlc.next_version_string();
    // The shared transition cannot choose App/MCP/CLI provenance itself.
    // When the caller requests a series stop, mint the recurrence-clear
    // version from the same surface HLC source before entering the store layer.
    let series_clear_ver = if cancel_series {
        Some(hlc.next_version_string())
    } else {
        None
    };
    apply_cancel_transition(
        conn,
        task_id,
        now,
        &reminder_ver,
        cancel_series,
        series_clear_ver.as_deref(),
    )
}

pub fn run_reopen(
    conn: &Connection,
    task_id: &TaskId,
    before_status: TaskStatus,
    now: &str,
    hlc: &HlcSession<'_>,
) -> Result<ReopenLifecycleTransitionResult, StoreError> {
    let reminder_ver = hlc.next_version_string();
    apply_reopen_transition(conn, task_id, before_status, now, &reminder_ver)
}

pub fn run_status_change(
    conn: &Connection,
    task_id: &TaskId,
    before_status: TaskStatus,
    next_status: TaskStatus,
    now: &str,
    hlc: &HlcSession<'_>,
) -> Result<LifecycleTransitionResult, StoreError> {
    let reminder_ver = hlc.next_version_string();
    apply_lifecycle_transition(
        conn,
        task_id,
        before_status,
        next_status,
        now,
        &reminder_ver,
    )
}
