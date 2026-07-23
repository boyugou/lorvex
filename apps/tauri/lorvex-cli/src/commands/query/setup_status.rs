//! CLI handler for `setup-status`, mirroring the MCP
//! `get_setup_status` tool. Pure read — no DB writes, no changelog row.

use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::mutate::setup_status::effects::get_setup_status_with_conn;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::render::yes_no;

pub(crate) fn run_setup_status(format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let snapshot = get_setup_status_with_conn(&conn)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Lorvex Setup Status\n\
             DB: {}\n\
             Lists: {} (ready: {})\n\
             Default list: {} (ready: {})\n\
             Working hours configured: {}\n\
             Normal task creation ready: {}\n\
             Prerequisites ready: {}\n\
             Explicit setup completed: {}\n\
             Setup completed: {}\n\
             Tasks: {}\n",
            db_path.display(),
            snapshot.list_count,
            yes_no(snapshot.status.lists_ready),
            // `as_deref().unwrap_or("none")` borrows the id in place
            // — the format! call only needs a `&str`, so the previous
            // `clone().unwrap_or_else(|| "none".to_string())` was a
            // dead allocation.
            snapshot.status.default_list_id.as_deref().unwrap_or("none"),
            yes_no(snapshot.status.default_list_ready),
            yes_no(snapshot.status.working_hours_ready),
            yes_no(snapshot.status.normal_task_creation_ready),
            yes_no(snapshot.status.prerequisites_ready),
            yes_no(snapshot.status.explicit_setup_completed),
            yes_no(snapshot.status.setup_completed),
            snapshot.task_count,
        )),
        OutputFormat::Json => render_query_envelope(
            "query.setup_status",
            &db_path,
            json!({ "snapshot": snapshot }),
        ),
    }
}
