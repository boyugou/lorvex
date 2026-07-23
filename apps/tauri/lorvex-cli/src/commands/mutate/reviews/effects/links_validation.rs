//! Daily review task/list link validators.
//!
//! Each daily review carries two child link sets — `daily_review_task_links`
//! and `daily_review_list_links` — capped at 500 ids each per the
//! file-level contract on the parent module. The validators turn each
//! cap-bounded set into a single `IN (...)` scan instead of N point
//! lookups. Read-side child enrichment is owned by
//! `lorvex_store::daily_review_ops`.

use rusqlite::Connection;

pub(super) fn validate_review_task_links(
    conn: &Connection,
    task_ids: &[String],
) -> Result<(), crate::error::CliError> {
    if task_ids.is_empty() {
        return Ok(());
    }
    // One IN-list scan instead of N point-queries; the link set is
    // capped at 500 (per the file-level contract) so the previous
    // shape ran up to 500 round trips per review write. The HashSet
    // lookup preserves the order of `task_ids` in the diagnostic so
    // a typo'd id surfaces with the same wording the per-row helper
    // produced.
    let placeholders = lorvex_domain::sql_csv_placeholders(task_ids.len());
    let sql = format!("SELECT id FROM tasks WHERE id IN ({placeholders}) AND archived_at IS NULL");
    let mut stmt = conn.prepare(&sql)?;
    let found: std::collections::HashSet<String> = stmt
        .query_map(rusqlite::params_from_iter(task_ids.iter()), |row| {
            row.get::<_, String>(0)
        })?
        .collect::<rusqlite::Result<_>>()?;
    if let Some(missing) = task_ids.iter().find(|id| !found.contains(id.as_str())) {
        return Err(crate::error::CliError::NotFound(format!(
            "task '{missing}' not found"
        )));
    }
    Ok(())
}

pub(super) fn validate_review_list_links(
    conn: &Connection,
    list_ids: &[String],
) -> Result<(), crate::error::CliError> {
    if list_ids.is_empty() {
        return Ok(());
    }
    // One IN-list scan instead of N `list_repo::get_list` round-trips;
    // capped at 500 ids per file-level contract. `tasks` and `lists`
    // are uniquely-keyed so a single SELECT suffices.
    let placeholders = lorvex_domain::sql_csv_placeholders(list_ids.len());
    let sql = format!("SELECT id FROM lists WHERE id IN ({placeholders})");
    let mut stmt = conn.prepare(&sql)?;
    let found: std::collections::HashSet<String> = stmt
        .query_map(rusqlite::params_from_iter(list_ids.iter()), |row| {
            row.get::<_, String>(0)
        })?
        .collect::<rusqlite::Result<_>>()?;
    if let Some(missing) = list_ids.iter().find(|id| !found.contains(id.as_str())) {
        return Err(crate::error::CliError::NotFound(format!(
            "list '{missing}' not found"
        )));
    }
    Ok(())
}
