//! Recurrence skeleton + EXDATE-preserving patch for a single-row task
//! update.
//!
//! [`apply_recurrence_patch`] forwards the prepared recurrence /
//! due-date / due-time three-state patch to
//! [`crate::recurrence_config::apply_recurrence_change`], which owns the
//! co-application rules between the recurring skeleton and the
//! anchoring `due_at` plus the EXDATE list preservation policy.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::Connection;

use super::preparation::PreparedTaskUpdate;

pub(in crate::task_update) fn apply_recurrence_patch(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    prepared: &PreparedTaskUpdate,
    now: &str,
) -> Result<(), StoreError> {
    use crate::recurrence_config::DueAtPatch;
    let today = crate::timezone::today_ymd_for_conn(conn)?;
    let version = hlc.next_version_string();
    crate::recurrence_config::apply_recurrence_change(
        conn,
        task_id,
        prepared.new_recurrence.clone(),
        DueAtPatch::new(
            prepared.pending_due_date_patch.clone(),
            prepared.pending_due_time_patch.clone(),
        ),
        &today,
        &version,
        now,
    )
    .map(|_| ())
    .map_err(recurrence_change_error_to_store)
}

pub(in crate::task_update) const fn recurrence_patch_present(
    prepared: &PreparedTaskUpdate,
) -> bool {
    prepared.new_recurrence.is_set_or_clear()
        || prepared.pending_due_date_patch.is_set_or_clear()
        || prepared.pending_due_time_patch.is_set_or_clear()
}

fn recurrence_change_error_to_store(
    error: crate::recurrence_config::RecurrenceChangeError,
) -> StoreError {
    match error {
        crate::recurrence_config::RecurrenceChangeError::ClearDueDateOnRecurring => {
            StoreError::Validation("recurring tasks must have a due_date".to_string())
        }
        crate::recurrence_config::RecurrenceChangeError::DueTimeWithoutDueDate => {
            StoreError::Validation(
                "due_time without due_date is invalid: a clock time requires a calendar day"
                    .to_string(),
            )
        }
        crate::recurrence_config::RecurrenceChangeError::Db(error) => StoreError::from(error),
        crate::recurrence_config::RecurrenceChangeError::TransactionWrap(message) => {
            StoreError::Invariant(format!("transaction wrapper failure: {message}"))
        }
        crate::recurrence_config::RecurrenceChangeError::StaleVersion { task_id } => {
            StoreError::StaleVersion {
                entity: ENTITY_TASK,
                id: task_id,
            }
        }
    }
}
