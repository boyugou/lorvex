use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::{delete_memory_with_conn, restore_memory_with_conn, write_memory_with_conn};

pub(crate) fn run_memory_write(
    key: &str,
    content: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let result = write_memory_with_conn(&mut conn, key, content)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Wrote Lorvex memory\nDB: {}\nKey: {}\nOperation: {}\nRevision: {}\n",
            db_path.display(),
            result.key,
            result.operation,
            result.revision_id,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "memory.write",
            &db_path,
            json!({
                "key": result.key,
                "content": result.content,
                "version": result.version,
                "updated_at": result.updated_at,
                "revision_id": result.revision_id,
                "operation": result.operation,
            }),
        ),
    }
}

pub(crate) fn run_memory_delete(
    key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let result = delete_memory_with_conn(&mut conn, key)?;
    match format {
        OutputFormat::Text => {
            if result.deleted {
                Ok(format!(
                    "Deleted Lorvex memory\nDB: {}\nKey: {}\nRevision: {}\n",
                    db_path.display(),
                    result.key,
                    result.revision_id.as_deref().unwrap_or(""),
                ))
            } else {
                Ok(format!(
                    "Lorvex memory not found\nDB: {}\nKey: {}\n",
                    db_path.display(),
                    result.key,
                ))
            }
        }
        // canonical CLI delete envelope shape.
        // `deleted` is the captured pre-delete row (when the key
        // existed) or `null` (no-op, key not found). The boolean
        // `deleted: true/false` was renamed to `existed` so the
        // canonical `deleted` slot stays a row-or-null.
        OutputFormat::Json => render_mutation_envelope(
            "memory.delete",
            &db_path,
            json!({
                "key": result.key,
                "existed": result.deleted,
                "deleted": result.deleted.then(|| json!({
                    "key": result.key,
                    "revision_id": result.revision_id,
                    "before_content": result.before_content,
                    "before_updated_at": result.before_updated_at,
                })),
            }),
        ),
    }
}

pub(crate) fn run_memory_restore(
    revision_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let result = restore_memory_with_conn(&mut conn, revision_id)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Restored Lorvex memory\nDB: {}\nKey: {}\nFrom revision: {}\nNew revision: {}\n",
            db_path.display(),
            result.key,
            result.from_revision_id,
            result.new_revision_id,
        )),
        // canonical mutation envelope.
        OutputFormat::Json => render_mutation_envelope(
            "memory.restore",
            &db_path,
            json!({
                "restored": true,
                "key": result.key,
                "from_revision_id": result.from_revision_id,
                "new_revision_id": result.new_revision_id,
            }),
        ),
    }
}
