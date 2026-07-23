use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::{delete_preference_with_conn, set_preference_with_conn};

pub(crate) fn run_preference_set(
    key: &str,
    value_json: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let result = set_preference_with_conn(&mut conn, key, value_json)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Set Lorvex preference\nDB: {}\nKey: {}\nValue: {}\nOperation: {}\n",
            db_path.display(),
            result.key,
            result.value,
            result.operation,
        )),
        // canonical mutation envelope. Verb is
        // `preference.set` so it parallels `preference.delete` below.
        OutputFormat::Json => render_mutation_envelope(
            "preference.set",
            &db_path,
            json!({
                "key": result.key,
                "value": result.value,
                "version": result.version,
                "updated_at": result.updated_at,
                "operation": result.operation,
            }),
        ),
    }
}

pub(crate) fn run_preference_delete(
    key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let result = delete_preference_with_conn(&mut conn, key)?;
    match format {
        OutputFormat::Text => {
            if result.deleted {
                Ok(format!(
                    "Deleted Lorvex preference\nDB: {}\nKey: {}\n",
                    db_path.display(),
                    result.key,
                ))
            } else {
                Ok(format!(
                    "Lorvex preference not found\nDB: {}\nKey: {}\n",
                    db_path.display(),
                    result.key,
                ))
            }
        }
        // canonical CLI delete envelope shape.
        // `deleted` is the captured pre-delete row or `null`;
        // `existed` reports whether the key was present.
        OutputFormat::Json => render_mutation_envelope(
            "preference.delete",
            &db_path,
            json!({
                "key": result.key,
                "existed": result.deleted,
                "deleted": result.deleted.then(|| json!({ "key": result.key })),
            }),
        ),
    }
}
