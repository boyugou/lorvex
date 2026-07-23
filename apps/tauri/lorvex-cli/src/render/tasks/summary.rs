//! `TaskRow → TaskSummary` projection shared by every JSON renderer
//! and the CLI mutation effects that need to serialize raw repository
//! rows back into the typed view layer.

use lorvex_store::repositories::task::read;

use crate::models::TaskSummary;

/// Convert a raw `read::TaskRow` into the typed `TaskSummary` view
/// that downstream renderers (and the JSON serialization paths) consume.
///
/// Used externally by `crate::commands::mutate` effects to project raw repository rows into
/// the CLI's view layer; kept here so the projection stays close to
/// the renderers that depend on its exact field set.
pub(crate) fn task_row_to_summary(row: read::TaskRow) -> TaskSummary {
    let (core, scheduling, _, _) = row.into_parts();
    let core = core.into_fields();
    let scheduling = scheduling.into_fields();
    TaskSummary {
        id: core.id,
        title: core.title,
        status: core.status,
        due_date: scheduling.due.date(),
        planned_date: scheduling.planned_date,
        priority: core.priority,
        list_id: core.list_id,
    }
}
