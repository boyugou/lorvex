use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;

pub(crate) mod effects;
use effects::rename_tag_with_conn;

pub(crate) fn run_tag_rename(
    old_name: &str,
    new_name: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = rename_tag_with_conn(&mut conn, old_name, new_name)?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Renamed Lorvex tag\nDB: {}\nOld: {}\nNew: {}\nTasks updated: {}\n",
            db_path.display(),
            result.old_name,
            result.new_name,
            result.tasks_updated
        )),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("tag.rename", &db_path, json!({ "tag_rename": result }))
        }
    }
}
