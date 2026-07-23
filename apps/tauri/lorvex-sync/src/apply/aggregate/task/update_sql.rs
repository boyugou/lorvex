//! SQL string builders for the task aggregate apply path.
//!
//! Holds the two render-once-per-process SQL templates the upsert
//! pipeline emits — the partial-update UPDATE (one shape per
//! [`LwwTieBreak`] flavor) and the matching INSERT for fresh rows.
//! Both shapes are byte-stable for any given input: the UPDATE
//! template only varies in its trailing version comparator (`>` vs
//! `>=`), and the INSERT template is fully static.
//!
//! Keeping the SQL in its own module keeps the parent file focused on
//! payload parsing + dispatch, and lets `update_sql/tests.rs` assert
//! the byte shape of the rendered string without booting a SQLite
//! connection.
//!
//! No extraction-driven SQL change: the rendered bytes here are
//! bit-identical to the pre-extraction `task_update_sql` builder in
//! `task.rs`. The render-once `OnceLock` cache also lives here so
//! the per-flavor `format!` allocation continues to amortize across
//! every task upsert envelope.

use std::sync::OnceLock;

use super::super::super::LwwTieBreak;
use super::super::helpers::version_cmp;

/// Render-once-and-share the task-upsert UPDATE SQL for each
/// [`LwwTieBreak`] flavor. The 44-line SQL is byte-identical for every
/// envelope of a given tie-break policy — caching the rendered string
/// in a `OnceLock` per flavor eliminates the per-envelope
/// `format!` + `String` allocation on the highest-volume apply path.
pub(super) fn task_update_sql(tie_break: LwwTieBreak) -> &'static str {
    static REJECT_EQUAL: OnceLock<String> = OnceLock::new();
    static ALLOW_EQUAL: OnceLock<String> = OnceLock::new();
    let slot = match tie_break {
        LwwTieBreak::RejectEqual => &REJECT_EQUAL,
        LwwTieBreak::AllowEqual => &ALLOW_EQUAL,
    };
    slot.get_or_init(|| {
        format!(
            "UPDATE tasks SET
                 title = :title,
                 body = CASE WHEN :body_present THEN :body ELSE tasks.body END,
                 raw_input = CASE WHEN :raw_input_present THEN :raw_input ELSE tasks.raw_input END,
                 ai_notes = CASE WHEN :ai_notes_present THEN :ai_notes ELSE tasks.ai_notes END,
                 status = :status,
                 list_id = :list_id,
                 priority = CASE WHEN :priority_present THEN :priority ELSE tasks.priority END,
                 due_date = CASE WHEN :due_date_present THEN :due_date ELSE tasks.due_date END,
                 due_time = CASE WHEN :due_time_present THEN :due_time ELSE tasks.due_time END,
                 estimated_minutes = CASE WHEN :estimated_minutes_present
                     THEN :estimated_minutes ELSE tasks.estimated_minutes END,
                 recurrence = CASE WHEN :recurrence_present
                     THEN :recurrence ELSE tasks.recurrence END,
                 spawned_from = CASE WHEN :spawned_from_present
                     THEN :spawned_from ELSE tasks.spawned_from END,
                 recurrence_group_id = CASE WHEN :recurrence_group_id_present
                     THEN :recurrence_group_id ELSE tasks.recurrence_group_id END,
                 canonical_occurrence_date = CASE WHEN :canonical_occurrence_date_present
                     THEN :canonical_occurrence_date ELSE tasks.canonical_occurrence_date END,
                 created_at = :created_at,
                 updated_at = :updated_at,
                 completed_at = CASE WHEN :completed_at_present
                     THEN :completed_at ELSE tasks.completed_at END,
                 last_deferred_at = CASE WHEN :last_deferred_at_present
                     THEN :last_deferred_at ELSE tasks.last_deferred_at END,
                 last_defer_reason = CASE WHEN :last_defer_reason_present
                     THEN :last_defer_reason ELSE tasks.last_defer_reason END,
                 planned_date = CASE WHEN :planned_date_present
                     THEN :planned_date ELSE tasks.planned_date END,
                 available_from = CASE WHEN :available_from_present
                     THEN :available_from ELSE tasks.available_from END,
                 defer_count = CASE WHEN :defer_count_present
                     THEN :defer_count ELSE tasks.defer_count END,
                 recurrence_instance_key = CASE WHEN :recurrence_instance_key_present
                     THEN :recurrence_instance_key ELSE tasks.recurrence_instance_key END,
                 archived_at = CASE WHEN :archived_at_present
                     THEN :archived_at ELSE tasks.archived_at END,
                 version = :version
             WHERE id = :id AND :version {} version",
            version_cmp(tie_break)
        )
    })
    .as_str()
}

/// INSERT template for the fresh-row path. Pure static string —
/// every bound parameter appears in the column list and the VALUES
/// list in the same order. Defined here so its shape lives next to
/// the UPDATE template.
pub(super) const TASK_INSERT_SQL: &str = "INSERT INTO tasks (id, title, body, raw_input, ai_notes,
                        status, list_id,
                        priority, due_date, due_time, estimated_minutes,
                        recurrence, spawned_from,
                        recurrence_group_id,
                        canonical_occurrence_date,
                        created_at, updated_at, completed_at, last_deferred_at,
                        last_defer_reason,
                        planned_date, defer_count, recurrence_instance_key, version,
                        archived_at, available_from)
     VALUES (:id, :title, :body, :raw_input, :ai_notes,
             :status, :list_id,
             :priority, :due_date, :due_time, :estimated_minutes,
             :recurrence, :spawned_from,
             :recurrence_group_id,
             :canonical_occurrence_date,
             :created_at, :updated_at, :completed_at, :last_deferred_at,
             :last_defer_reason,
             :planned_date, :defer_count, :recurrence_instance_key, :version,
             :archived_at, :available_from)";

#[cfg(test)]
mod tests;
