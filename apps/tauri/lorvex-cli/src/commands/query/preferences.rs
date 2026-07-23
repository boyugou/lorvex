use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use rusqlite::OptionalExtension;
use serde_json::{json, Value};
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;

#[derive(Debug, Clone)]
struct PreferenceView {
    key: String,
    value: Value,
    updated_at: String,
}

fn parse_preference_value(key: &str, raw: &str) -> Result<Value, crate::error::CliError> {
    serde_json::from_str(raw).map_err(|error| {
        crate::error::CliError::Internal(format!(
            "preference '{key}' contains malformed JSON: {error}"
        ))
    })
}

pub(crate) fn run_preferences(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let mut stmt =
        conn.prepare_cached("SELECT key, value, updated_at FROM preferences ORDER BY key")?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let preferences = rows
        .into_iter()
        .map(|(key, raw, updated_at)| {
            parse_preference_value(&key, &raw).map(|value| PreferenceView {
                key,
                value,
                updated_at,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    match format {
        OutputFormat::Text => {
            let mut rendered = format!("Lorvex Preferences\nDB: {}\n", db_path.display());
            if preferences.is_empty() {
                rendered.push_str("  - none\n");
            } else {
                for pref in &preferences {
                    let _ = writeln!(
                        rendered,
                        "  - {} = {} (updated {})",
                        pref.key, pref.value, pref.updated_at
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.preferences.list",
            &db_path,
            json!({
                "preferences": preferences
                    .into_iter()
                    .map(|pref| json!({
                        "key": pref.key,
                        "value": pref.value,
                        "updated_at": pref.updated_at,
                    }))
                    .collect::<Vec<_>>(),
            }),
        ),
    }
}

pub(crate) fn run_preference_get(
    key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let row: Option<(String, String)> = conn
        .query_row(
            "SELECT value, updated_at FROM preferences WHERE key = ?1",
            [key],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((raw, updated_at)) = row else {
        return match format {
            OutputFormat::Text => Ok(format!(
                "Lorvex Preference\nDB: {}\nKey: {}\nValue: not set\n",
                db_path.display(),
                key,
            )),
            OutputFormat::Json => Ok("null".to_string()),
        };
    };
    let value = parse_preference_value(key, &raw)?;

    match format {
        OutputFormat::Text => Ok(format!(
            "Lorvex Preference\nDB: {}\nKey: {}\nValue: {}\nUpdated: {}\n",
            db_path.display(),
            key,
            value,
            updated_at,
        )),
        OutputFormat::Json => render_query_envelope(
            "query.preferences.get",
            &db_path,
            json!({
                "key": key,
                "value": value,
                "updated_at": updated_at,
            }),
        ),
    }
}
