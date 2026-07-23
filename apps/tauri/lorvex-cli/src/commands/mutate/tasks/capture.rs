use lorvex_runtime::resolve_db_path;

use crate::cli::OutputFormat;
use crate::commands::mutate::tasks::capture_effects::{
    create_captured_task_with_conn, CaptureTaskOptions,
};
use crate::render::render_task_action_result;
use crate::startup_maintenance::open_db_at_path;

pub(crate) fn run_capture(
    title: &str,
    options: CaptureTaskOptions<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let task_id = create_captured_task_with_conn(&mut conn, title, options)?;

    // bring task action envelopes under the canonical
    // `<domain>.<verb>` namespace shared with every other CLI mutation
    // surface (`list.delete`, `habit.complete`, `calendar.update`,
    // `focus.set`, etc.).
    // verbs like `"capture"`, `"complete"`, `"update"`, breaking the
    // discriminator pattern external consumers (jq pipelines,
    // multi-DB sync watchers) dispatch on `action`.
    render_task_action_result("task.capture", &task_id, title, &db_path, format)
}
