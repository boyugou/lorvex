use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::memory_repo;
use lorvex_store::repositories::memory_revision_repo;

use crate::cli::OutputFormat;
use crate::render::{render_memory_collection, render_memory_detail, render_memory_history};

fn normalize_memory_query_key(key: &str) -> Result<String, crate::error::CliError> {
    let normalized = lorvex_domain::memory::normalize_memory_key(key);
    if normalized.is_empty() {
        return Err(crate::error::CliError::Validation(
            "memory key must not be empty".to_string(),
        ));
    }
    Ok(normalized)
}

pub(crate) fn run_memory_list(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let mut stmt = conn.prepare(
        "SELECT key, content, version, updated_at FROM memories ORDER BY updated_at DESC",
    )?;
    // route through the shared row parser so the
    // typed `SyncTimestamp::parse` invariant is owned by the repo.
    let entries: Vec<memory_repo::MemoryEntry> = stmt
        .query_map([], memory_repo::row_to_memory_entry)?
        .collect::<Result<Vec<_>, _>>()?;

    render_memory_collection(&db_path, &entries, format)
}

pub(crate) fn run_memory_show(
    key: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let key = normalize_memory_query_key(key)?;

    let entry = memory_repo::get_memory_entry(&conn, &key)?;
    entry.map_or_else(
        || {
            Err(crate::error::CliError::NotFound(format!(
                "memory key '{key}' not found"
            )))
        },
        |entry| render_memory_detail(&db_path, &entry, format),
    )
}

pub(crate) fn run_memory_history(
    key: &str,
    limit: u32,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let key = normalize_memory_query_key(key)?;

    let typed_key = lorvex_domain::MemoryKey::from_trusted(key.clone());
    let revisions = memory_revision_repo::get_revisions_for_key(&conn, &typed_key, limit.min(100))?;
    render_memory_history(&db_path, &key, &revisions, format)
}
