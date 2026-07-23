//! Task lifecycle mutations: the AI-driven and CLI-driven transitions
//! that flow through the canonical [`lorvex_workflow::lifecycle`]
//! engine. Also owns the patch-based field update path
//! (`update_task_with_conn`) and the trash / permanent-delete cascade.
//!
//! Executor-migrated entry points route the canonical lifecycle write
//! through the CLI mutation adapter, then flush sync side effects,
//! changelog rows, and local sequence bumps under the same HLC state.
//! The module deliberately keeps that orchestration in surface-level
//! adapters because the CLI audit/outbox/local-seq policy is part of
//! the transaction boundary.

use lorvex_domain::hlc_session::HlcSession;
#[cfg(test)]
use lorvex_domain::naming::is_valid_defer_reason;
use lorvex_domain::naming::{TaskStatus, ENTITY_TASK, ENTITY_TASK_REMINDER};
use lorvex_domain::TaskId;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::{task::read, task::write};
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::enqueue_entity_upsert;
use lorvex_workflow::lifecycle::{
    effects as workflow_lifecycle_effects, CancelLifecycleTransitionResult,
    CompletionLifecycleTransitionResult, ReopenLifecycleTransitionResult,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_deferral::{self, TaskDeferralResult};
use rusqlite::Connection;
use serde_json::Value;
use std::cell::RefCell;

use crate::hlc_guard::lock_shared;

use super::dependencies;
#[cfg(test)]
use crate::commands::shared::effects::date_plus_days_ymd_for_conn;
use crate::commands::shared::{
    execute_cli_mutation_with_finalizer, load_task_row, log_cli_changelog_with_state,
    CliChangelogParams,
};

mod canonical_flush;
mod effects;
mod trash;
mod update;
mod update_validation;
pub(crate) use trash::{
    archive_task_in_tx, permanent_delete_task_in_tx, restore_task_from_trash_in_tx,
    PermanentDeleteTaskResult,
};
#[cfg(test)]
pub(crate) use trash::{
    archive_task_with_conn, permanent_delete_task_with_conn, restore_task_from_trash_with_conn,
};
pub(crate) use update::update_task_with_conn;
pub(crate) use update_validation::TaskUpdateFields;

/// CLI lifecycle transition kind. Carries the per-variant inputs the
/// shared [`workflow_lifecycle_effects`] entry points need; the
/// [`Mutation`] adapter [`CliLifecycleMutation`] dispatches on this so
/// complete / cancel / reopen share one descriptor instead of three
/// near-identical wrappers.
enum CliLifecycleKind {
    Complete,
    Cancel { cancel_series: bool },
    Reopen { before_status: TaskStatus },
}

impl CliLifecycleKind {
    const fn operation(&self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Cancel { .. } => "cancel",
            Self::Reopen { .. } => "reopen",
        }
    }

    const fn summary_verb(&self) -> &'static str {
        match self {
            Self::Complete => "Completed",
            Self::Cancel { .. } => "Cancelled",
            Self::Reopen { .. } => "Reopened",
        }
    }

    const fn failure_phrase(&self) -> &'static str {
        match self {
            Self::Complete => "completed",
            Self::Cancel { .. } => "cancelled",
            Self::Reopen { .. } => "reopened",
        }
    }
}

/// Lifecycle transition result staged by [`CliLifecycleMutation::apply`]
/// so the finalizer can drive [`LifecycleSyncPlan`] uniformly.
enum CliLifecycleResult {
    Complete(CompletionLifecycleTransitionResult),
    Cancel(CancelLifecycleTransitionResult),
    Reopen(ReopenLifecycleTransitionResult),
}

impl CliLifecycleResult {
    const fn updated(&self) -> bool {
        match self {
            Self::Complete(r) => r.updated,
            Self::Cancel(r) => r.updated,
            Self::Reopen(r) => r.updated,
        }
    }
}

/// Unified CLI lifecycle [`Mutation`] descriptor for complete / cancel /
/// reopen. Replaces the three near-identical per-verb wrappers — the
/// only variation across verbs is which `workflow_lifecycle_effects::run_*`
/// entry point fires, captured by [`CliLifecycleKind`].
struct CliLifecycleMutation {
    kind: CliLifecycleKind,
    task_id: TaskId,
    before: Value,
    title: String,
    result: RefCell<Option<CliLifecycleResult>>,
}

impl Mutation for CliLifecycleMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        self.kind.operation()
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = lorvex_domain::sync_timestamp_now();
        let result = match &self.kind {
            CliLifecycleKind::Complete => CliLifecycleResult::Complete(
                workflow_lifecycle_effects::run_completion(conn, &self.task_id, &now, hlc)?,
            ),
            CliLifecycleKind::Cancel { cancel_series } => {
                CliLifecycleResult::Cancel(workflow_lifecycle_effects::run_cancel(
                    conn,
                    &self.task_id,
                    &now,
                    *cancel_series,
                    hlc,
                )?)
            }
            CliLifecycleKind::Reopen { before_status } => {
                CliLifecycleResult::Reopen(workflow_lifecycle_effects::run_reopen(
                    conn,
                    &self.task_id,
                    *before_status,
                    &now,
                    hlc,
                )?)
            }
        };
        if !result.updated() {
            return Err(StoreError::Invariant(format!(
                "task '{}' could not be {}",
                self.task_id.as_str(),
                self.kind.failure_phrase()
            )));
        }
        let after = load_task_row_after_lifecycle_apply(conn, &self.task_id)?;
        let summary = format!("{} task: {}", self.kind.summary_verb(), self.title);
        self.result.replace(Some(result));
        Ok(MutationOutput::new(serde_json::to_value(&after)?, summary))
    }
}

struct DeferCliTaskMutation {
    task_id: TaskId,
    before: Value,
    title: String,
    days: Option<i64>,
    reason_sanitized: Option<String>,
    structured_reason: Option<String>,
    planned_date: Option<String>,
    before_defer_count: i64,
    before_ai_notes: String,
    result: RefCell<Option<TaskDeferralResult>>,
}

impl Mutation for DeferCliTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "defer"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = lorvex_domain::sync_timestamp_now();
        let version = hlc.next_version_string();
        let new_defer_count = self.before_defer_count + 1;
        let new_ai_notes = self.reason_sanitized.as_ref().map(|reason_text| {
            let defer_note = format!("Deferred (#{new_defer_count}): {reason_text}");
            if self.before_ai_notes.trim().is_empty() {
                defer_note
            } else {
                format!("{}\n\n{defer_note}", self.before_ai_notes)
            }
        });
        let patch = task_deferral::TaskDeferralPatch {
            planned_date: self.planned_date.as_deref(),
            ai_notes: new_ai_notes.as_deref(),
            last_defer_reason: self.structured_reason.as_deref(),
        };
        let result =
            task_deferral::defer_task(conn, &self.task_id, &patch, &version, &now, || {
                Ok::<String, StoreError>(hlc.next_version_string())
            })?;
        if !result.updated {
            return Err(StoreError::StaleVersion {
                entity: ENTITY_TASK,
                id: self.task_id.as_str().to_string(),
            });
        }
        let after = load_task_row_after_lifecycle_apply(conn, &self.task_id)?;
        self.result.replace(Some(result));
        Ok(MutationOutput::new(
            serde_json::to_value(&after)?,
            defer_summary(self.days, self.reason_sanitized.as_deref(), &self.title),
        ))
    }
}

fn load_task_row_after_lifecycle_apply(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<read::TaskRow, StoreError> {
    read::get_task(conn, task_id)?.ok_or_else(|| StoreError::NotFound {
        entity: ENTITY_TASK,
        id: task_id.as_str().to_string(),
    })
}

fn defer_summary(days: Option<i64>, reason_sanitized: Option<&str>, title: &str) -> String {
    match (days, reason_sanitized) {
        (Some(d), Some(r)) => format!("Deferred task by {d} days: {title} ({r})"),
        (Some(d), None) => format!("Deferred task by {d} days: {title}"),
        (None, Some(r)) => format!("Deferred task: {title} ({r})"),
        (None, None) => format!("Deferred task: {title}"),
    }
}

/// Owned-tx wrapper. Production callers use `*_in_tx` so each per-id
/// CLI batch helper composes its own savepoint inside the outer
/// transaction; this wrapper exists for tests that exercise a single
/// id outside the batch envelope.
#[cfg(test)]
pub(crate) fn complete_task_with_conn(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<String, crate::error::CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        complete_task_in_tx(conn, task_id)
    })
}

/// Inside-transaction body for `complete_task_with_conn`.
///
/// Factored out so the CLI batch path can wrap each per-id call in a
/// SAVEPOINT inside one outer immediate transaction (see
/// `run_task_batch_action`'s `with_immediate_transaction` envelope).
/// The per-id failure rolls back only that savepoint and the loop
/// continues; the outer transaction commits every successful per-id
/// savepoint atomically when the loop returns.
pub(crate) fn complete_task_in_tx(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<String, crate::error::CliError> {
    run_lifecycle_transition_in_tx(conn, task_id, CliLifecycleKind::Complete)
}

/// Owned-tx wrapper. See `complete_task_with_conn` for the rationale.
#[cfg(test)]
pub(crate) fn cancel_task_with_conn(
    conn: &Connection,
    task_id: &TaskId,
    cancel_series: bool,
) -> Result<String, crate::error::CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        cancel_task_in_tx(conn, task_id, cancel_series)
    })
}

/// Inside-transaction body for `cancel_task_with_conn` (#3019-H3).
pub(crate) fn cancel_task_in_tx(
    conn: &Connection,
    task_id: &TaskId,
    cancel_series: bool,
) -> Result<String, crate::error::CliError> {
    run_lifecycle_transition_in_tx(conn, task_id, CliLifecycleKind::Cancel { cancel_series })
}

/// Owned-tx wrapper. See `complete_task_with_conn` for the rationale.
#[cfg(test)]
pub(crate) fn reopen_task_with_conn(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<String, crate::error::CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        reopen_task_in_tx(conn, task_id)
    })
}

/// Inside-transaction body for `reopen_task_with_conn` (#3019-H3).
pub(crate) fn reopen_task_in_tx(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<String, crate::error::CliError> {
    let before_status_text = load_task_row(conn, task_id)?.core().status().to_string();
    let before_status = write::parse_task_status_for_update(task_id.as_str(), &before_status_text)?;
    run_lifecycle_transition_in_tx(conn, task_id, CliLifecycleKind::Reopen { before_status })
}

/// Shared body for the complete / cancel / reopen CLI lifecycle verbs.
///
/// Builds the unified [`CliLifecycleMutation`] descriptor, runs it
/// through [`execute_cli_mutation_with_finalizer`] so the per-surface
/// outbox + `ai_changelog` + `local_change_seq` finalizer fires under
/// the same HLC counter run as the workflow transition, and flushes
/// the lifecycle sync plan via [`LifecycleSyncPlan`] regardless of
/// verb.
fn run_lifecycle_transition_in_tx(
    conn: &Connection,
    task_id: &TaskId,
    kind: CliLifecycleKind,
) -> Result<String, crate::error::CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let before = load_task_row(conn, task_id)?;
    let title = before.core().title().to_string();
    let mutation = CliLifecycleMutation {
        kind,
        task_id: task_id.clone(),
        before: serde_json::to_value(&before)?,
        title: title.clone(),
        result: RefCell::new(None),
    };

    let mut hlc_guard = lock_shared(conn)?;
    execute_cli_mutation_with_finalizer(
        conn,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                conn,
                execution.entity_kind,
                task_id.as_str(),
                hlc_state,
                &device_id,
            )?;
            {
                let result_ref = mutation.result.borrow();
                let result = result_ref
                    .as_ref()
                    .expect("Mutation contract: CLI lifecycle result staged by apply");
                match result {
                    CliLifecycleResult::Complete(result) => {
                        effects::flush_completion_effects_with_state(
                            conn, &device_id, result, hlc_state,
                        )?;
                    }
                    CliLifecycleResult::Cancel(result) => {
                        effects::flush_cancel_effects_with_state(
                            conn, &device_id, result, hlc_state,
                        )?;
                    }
                    CliLifecycleResult::Reopen(result) => {
                        effects::flush_reopen_effects_with_state(
                            conn, &device_id, result, hlc_state,
                        )?;
                    }
                }
            }
            log_cli_changelog_with_state(
                conn,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: task_id.as_str(),
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(conn)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    Ok(title)
}

/// Owned-tx wrapper. See `complete_task_with_conn` for the rationale.
#[cfg(test)]
pub(crate) fn defer_task_with_conn(
    conn: &Connection,
    task_id: &TaskId,
    days: Option<i64>,
    reason: Option<&str>,
    structured_reason: Option<&str>,
) -> Result<String, crate::error::CliError> {
    // Validation + planned-date math happens before the tx opens;
    // the inside-tx body owns the actual mutation and is also the
    // batch reuse target.
    if let Some(value) = structured_reason {
        if !is_valid_defer_reason(value) {
            return Err(crate::error::CliError::Validation(format!(
                "invalid structured defer reason '{value}'"
            )));
        }
    }
    if let Some(value) = days {
        if value < 1 {
            return Err(crate::error::CliError::Validation(
                "defer days must be >= 1".to_string(),
            ));
        }
    }
    let reason_sanitized = reason.map(lorvex_domain::sanitize_user_text);
    if let Some(value) = reason_sanitized.as_deref() {
        lorvex_domain::validation::validate_body(value)?;
    }
    let planned_date = days
        .map(|offset| date_plus_days_ymd_for_conn(conn, offset))
        .transpose()?;

    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        defer_task_in_tx(
            conn,
            task_id,
            days,
            reason_sanitized.as_deref(),
            structured_reason,
            planned_date.as_deref(),
        )
    })
}

/// Inside-transaction body for `defer_task_with_conn` (#3019-H3).
///
/// Validation, sanitization, and planned-date math run in the caller
/// because the planned-date helper consults the timezone preference
/// outside any active write transaction. The batch path passes the
/// already-validated inputs straight through.
pub(crate) fn defer_task_in_tx(
    conn: &Connection,
    task_id: &TaskId,
    days: Option<i64>,
    reason_sanitized: Option<&str>,
    structured_reason: Option<&str>,
    planned_date: Option<&str>,
) -> Result<String, crate::error::CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let before = load_task_row(conn, task_id)?;
    let before_title = before.core().title().to_string();
    let mutation = DeferCliTaskMutation {
        task_id: task_id.clone(),
        before: serde_json::to_value(&before)?,
        title: before_title.clone(),
        days,
        reason_sanitized: reason_sanitized.map(str::to_string),
        structured_reason: structured_reason.map(str::to_string),
        planned_date: planned_date.map(str::to_string),
        before_defer_count: before.scheduling().defer_count(),
        before_ai_notes: before.core().ai_notes().unwrap_or_default().to_string(),
        result: RefCell::new(None),
    };

    let mut hlc_guard = lock_shared(conn)?;
    execute_cli_mutation_with_finalizer(
        conn,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                conn,
                execution.entity_kind,
                task_id.as_str(),
                hlc_state,
                &device_id,
            )?;
            {
                let result_ref = mutation.result.borrow();
                let result = result_ref
                    .as_ref()
                    .expect("Mutation contract: CLI task deferral result staged by apply");
                for reminder_id in &result.shifted_reminder_ids {
                    enqueue_entity_upsert(
                        conn,
                        ENTITY_TASK_REMINDER,
                        reminder_id,
                        hlc_state,
                        &device_id,
                    )?;
                }
            }
            log_cli_changelog_with_state(
                conn,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: task_id.as_str(),
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(conn)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    Ok(before_title)
}

#[cfg(test)]
mod tests;
