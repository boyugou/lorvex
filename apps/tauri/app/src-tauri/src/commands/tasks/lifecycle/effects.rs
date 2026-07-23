use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::TaskId;
use lorvex_store::repositories::task::write;
use lorvex_workflow::lifecycle::{effects as workflow_effects, ReopenLifecycleTransitionResult};
use rusqlite::Connection;

use super::super::AppError;

/// Tauri-surface wrapper around `lorvex_workflow::lifecycle::effects::run_reopen`
/// that parses the `before_status` string into the typed `TaskStatus`
/// at the surface boundary and binds `StoreError` into the local
/// `AppError`. The other lifecycle transitions (completion, cancel,
/// status-change) consume `workflow_effects::*` directly from their
/// command modules because they already hold typed status arguments by
/// the time they reach the apply step; the reopen path receives the
/// pre-mutation status as a raw string from the DB row and parses here
/// so the typed contract surfaces at the seam closest to that read.
pub(in crate::commands::tasks) fn run_reopen(
    conn: &Connection,
    task_id: &TaskId,
    before_status: &str,
    now: &str,
    hlc: &HlcSession<'_>,
) -> Result<ReopenLifecycleTransitionResult, AppError> {
    let before_status = write::parse_task_status_for_update(task_id.as_str(), before_status)?;
    Ok(workflow_effects::run_reopen(
        conn,
        task_id,
        before_status,
        now,
        hlc,
    )?)
}
