//! Shared task enrichment pipeline.
//!
//! Both the Tauri app and MCP server need to enrich task objects with derived
//! data (tags, dependencies, checklist items, lateness state) after loading
//! the base task row from SQLite. The SQL queries are identical; only the
//! target data representation differs.
//!
//! This module exposes a single [`compute_enrichments`] entry point that
//! returns an [`Enrichment`] map keyed on `task_id`. Each surface
//! (typed `Task` struct in the Tauri host, `serde_json::Value` in the MCP
//! server) walks its own task collection and merges the derived fields in
//! whatever shape it stores them. Routing through one return value keeps
//! the SQL — and the per-batch query budget — in one place without forcing
//! a trait abstraction onto an inert two-impl call site.

use std::collections::HashMap;

use rusqlite::{params_from_iter, Connection};

use lorvex_domain::sql_in_placeholders;
use lorvex_store::StoreError;

// ── Checklist item data transfer object ─────────────────────────────

/// A plain data struct representing a row from `task_checklist_items`.
///
/// Consumers can convert this into their own representation (e.g. a typed
/// struct or a `serde_json::Value`).
#[derive(Debug, Clone)]
pub struct ChecklistItemData {
    pub id: String,
    pub task_id: String,
    pub position: i64,
    pub text: String,
    pub completed_at: Option<String>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
}

// ── Enrichment side-table ───────────────────────────────────────────

/// Derived fields computed for a single task during a batch enrichment
/// pass. Each adapter folds the relevant fields back into its own task
/// representation.
#[derive(Debug, Default, Clone)]
pub struct Enrichment {
    pub tags: Option<Vec<String>>,
    pub depends_on: Option<Vec<String>>,
    pub checklist_items: Option<Vec<ChecklistItemData>>,
    pub lateness: Option<lorvex_domain::TaskLateness>,
}

// ── Single-pass batch enrichment ────────────────────────────────────

/// Compute every enrichment (tags, deps, checklist items, lateness)
/// for the supplied tasks in one batch pass per derived field. The
/// return map is keyed on `task_id`; absent keys mean "no enrichments
/// applied" (default-zeroed `Enrichment`).
///
/// Each callsite reads `planned_date` + `due_date` off its own task
/// representation up-front and supplies them via the `dates` slice; that
/// keeps this module unaware of the surface-specific task DTO shapes.
pub fn compute_enrichments(
    conn: &Connection,
    dates: &[(&str, Option<chrono::NaiveDate>, Option<chrono::NaiveDate>)],
    today: &str,
) -> Result<HashMap<String, Enrichment>, StoreError> {
    let mut out: HashMap<String, Enrichment> = HashMap::with_capacity(dates.len());
    if dates.is_empty() {
        return Ok(out);
    }

    let task_ids: Vec<&str> = dates.iter().map(|(id, _, _)| *id).collect();

    let today_date = lorvex_domain::time::parse_iso_date(today).map_err(|e| {
        StoreError::Validation(format!(
            "invalid today date '{today}' for lateness enrichment: {e}"
        ))
    })?;
    for (id, planned, due) in dates {
        let lateness = lorvex_domain::derive_open_task_lateness(*planned, *due, today_date);
        if lateness.is_some() {
            out.entry((*id).to_string()).or_default().lateness = lateness;
        }
    }

    // Tags
    {
        let placeholders = sql_in_placeholders(task_ids.len(), 0);
        let sql = format!(
            "SELECT tt.task_id, json_group_array(t.display_name) as tags \
             FROM task_tags tt \
             JOIN tags t ON t.id = tt.tag_id \
             WHERE tt.task_id IN ({placeholders}) \
             GROUP BY tt.task_id"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(task_ids.iter()), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (tid, tags_json) = row?;
            let parsed: Vec<String> = serde_json::from_str(&tags_json)?;
            out.entry(tid).or_default().tags = Some(parsed);
        }
    }

    // depends_on
    {
        let placeholders = sql_in_placeholders(task_ids.len(), 0);
        let sql = format!(
            "SELECT task_id, json_group_array(depends_on_task_id) as deps \
             FROM task_dependencies \
             WHERE task_id IN ({placeholders}) \
             GROUP BY task_id"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(task_ids.iter()), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (tid, deps_json) = row?;
            let parsed: Vec<String> = serde_json::from_str(&deps_json)?;
            out.entry(tid).or_default().depends_on = Some(parsed);
        }
    }

    // Checklist items
    {
        let placeholders = sql_in_placeholders(task_ids.len(), 0);
        let sql = format!(
            "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at \
             FROM task_checklist_items WHERE task_id IN ({placeholders}) \
             ORDER BY task_id ASC, position ASC, created_at ASC, id ASC"
        );
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(task_ids.iter()), |row| {
            Ok(ChecklistItemData {
                id: row.get(0)?,
                task_id: row.get(1)?,
                position: row.get(2)?,
                text: row.get(3)?,
                completed_at: row.get(4)?,
                version: row.get(5)?,
                created_at: row.get(6)?,
                updated_at: row.get(7)?,
            })
        })?;
        for row in rows {
            let item = row?;
            let task_id = item.task_id.clone();
            out.entry(task_id)
                .or_default()
                .checklist_items
                .get_or_insert_with(Vec::new)
                .push(item);
        }
    }

    Ok(out)
}

#[cfg(test)]
mod tests;
