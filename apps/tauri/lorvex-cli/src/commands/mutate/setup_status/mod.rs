//! CLI handler for `setup-complete`, mirroring the MCP
//! `complete_setup` tool. Writes the three onboarding preferences
//! (`setup_completed`, `setup_summary`, `setup_state`) under one
//! immediate transaction.

use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::error::CliError;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::complete_setup_with_conn;

pub(crate) fn run_setup_complete(summary: &str, format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = complete_setup_with_conn(&mut conn, summary)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Marked Lorvex setup complete\nDB: {}\nSummary: {}\nSetup completed: {}\n",
            db_path.display(),
            result.summary,
            result.setup_completed,
        )),
        OutputFormat::Json => {
            render_mutation_envelope("setup.complete", &db_path, json!({ "result": result }))
        }
    }
}

#[cfg(test)]
mod tests;
