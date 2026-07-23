//! CLI handler for `error-logs`. Reads the `error_logs`
//! table directly (no merge-with-redaction policy — see the parent
//! issue for the full `get_recent_logs` mirror, which is tracked
//! separately).

use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::list_recent_error_logs_with_conn;

pub(crate) fn run_error_logs(
    source: Option<&str>,
    limit: u32,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let rows = list_recent_error_logs_with_conn(&conn, limit, source)?;

    match format {
        OutputFormat::Text => {
            let mut out = format!(
                "Lorvex Error Logs\nDB: {}\nRows: {}\n",
                db_path.display(),
                rows.len()
            );
            if rows.is_empty() {
                out.push_str("  - none\n");
            } else {
                for row in &rows {
                    let _ = writeln!(
                        out,
                        "  [{}] {} {} {} {}",
                        row.created_at, row.source, row.level, row.id, row.message
                    );
                }
            }
            Ok(out)
        }
        OutputFormat::Json => render_query_envelope(
            "query.error_logs.list",
            &db_path,
            json!({
                "source": source,
                "limit": limit,
                "rows": rows,
            }),
        ),
    }
}
