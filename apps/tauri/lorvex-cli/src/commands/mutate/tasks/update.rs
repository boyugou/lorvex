use lorvex_domain::TaskId;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::mutate::tasks::lifecycle_effects::{update_task_with_conn, TaskUpdateFields};
use crate::startup_maintenance::open_db_at_path;

pub(crate) fn run_update_task(
    task_id: &str,
    fields: &TaskUpdateFields<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let task = update_task_with_conn(&mut conn, &task_id, fields)?;
    match format {
        OutputFormat::Text => Ok(crate::render::render_task_detail(&task, &db_path, None)),
        // wrap the bare task row in an `{action, db_path,
        // task}` envelope so consumers can share parsing logic across
        // mutating commands (multi-DB tooling, jq pipelines that
        // discriminate by `.action`).
        // namespace the action verb as `task.update`
        // for parity with every other mutation surface.
        // route through the canonical
        // `render_mutation_envelope` helper so the {action, db_path,
        // ...payload} contract stays in one place.
        // hand-built the JSON map, which silently drifted from the
        // helper whenever the helper picked up new behavior (e.g.
        // overriding caller-supplied `action`/`db_path` keys).
        OutputFormat::Json => crate::commands::shared::render_mutation_envelope(
            "task.update",
            &db_path,
            json!({ "task": task }),
        ),
    }
}
