use lorvex_runtime::resolve_db_path;

use crate::cli::OutputFormat;
use crate::commands::mutate::lists::effects::move_tasks_to_list_with_conn;
use crate::render::render_task_collection;
use crate::startup_maintenance::open_db_at_path;

pub(crate) fn run_move_tasks(
    list_id: &str,
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let tasks = move_tasks_to_list_with_conn(&mut conn, list_id, task_ids)?;
    render_task_collection("Moved tasks", &db_path, tasks, format)
}
