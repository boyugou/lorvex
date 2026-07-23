//! Pre/post-mutation entity snapshot reads used by the change-tracking
//! funnel. Both the per-entity and batched IN-list variants live here,
//! plus the `simple_pk_plan` registry that maps `entity_type` →
//! (table, pk_col, projection).

use std::collections::HashMap;

use lorvex_domain::naming::{
    EntityKind, EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY,
    EDGE_TASK_TAG, ENTITY_CALENDAR_EVENT, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW,
    ENTITY_FOCUS_SCHEDULE, ENTITY_PREFERENCE,
};
use rusqlite::Connection;
use serde_json::Value;

use crate::error::McpError;
use crate::json_row::{query_all_as_json, query_one_as_json};
use crate::preferences::parse_preference_row_value;

/// Per-entity row projection for the simple-PK readers. `Star` projects
/// every column on the table; `Explicit` ships a fixed comma-separated
/// list for tables whose row shape carries synthesized or future columns
/// we deliberately do NOT round-trip through MCP snapshots.
#[derive(Copy, Clone)]
enum SimplePkProjection {
    Star,
    Explicit(&'static str),
}

impl SimplePkProjection {
    const fn as_columns(self) -> &'static str {
        match self {
            Self::Star => "*",
            Self::Explicit(cols) => cols,
        }
    }
}

/// Resolve `entity_type` to the (table, pk_col, projection) triple used
/// by both the per-entity and batch readers. `None` means the type is
/// not a simple-PK SELECT — caller routes through the per-type slow
/// path (composite-key edges, aggregate roots with embedded children,
/// preferences with custom row decoder).
fn simple_pk_plan(entity_type: &str) -> Option<(&'static str, &'static str, SimplePkProjection)> {
    let kind = EntityKind::parse(entity_type)?;
    // Aggregate roots ride the canonical aggregate-payload builder so
    // their embedded children round-trip through every snapshot path.
    if matches!(
        kind,
        EntityKind::CurrentFocus
            | EntityKind::DailyReview
            | EntityKind::CalendarEvent
            | EntityKind::FocusSchedule
            | EntityKind::Preference
    ) {
        return None;
    }
    let (table, pk_col) = kind.table_pk()?;
    let projection = match kind {
        EntityKind::CalendarSubscription => SimplePkProjection::Explicit(
            "id, name, url, color, enabled, version, created_at, updated_at",
        ),
        _ => SimplePkProjection::Star,
    };
    Some((table, pk_col, projection))
}

/// Defense-in-depth identifier guards for the `format!`-built SQL
/// strings produced by both the per-entity and batch simple-PK readers.
fn assert_simple_pk_identifiers(
    table: &'static str,
    pk_col: &'static str,
    projection: SimplePkProjection,
) {
    lorvex_domain::assert_safe_sql_identifier(table);
    lorvex_domain::assert_safe_sql_identifier(pk_col);
    for col in projection.as_columns().split(',') {
        let col = col.trim();
        if col == "*" {
            continue;
        }
        lorvex_domain::assert_safe_sql_identifier(col);
    }
}

fn build_simple_pk_select(
    table: &'static str,
    pk_col: &'static str,
    projection: SimplePkProjection,
) -> String {
    assert_simple_pk_identifiers(table, pk_col, projection);
    let columns = projection.as_columns();
    format!("SELECT {columns} FROM {table} WHERE {pk_col} = ?")
}

pub(super) fn read_current_entity_snapshot(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<Value>, McpError> {
    if let Some((table, pk_col, projection)) = simple_pk_plan(entity_type) {
        let sql = build_simple_pk_select(table, pk_col, projection);
        return Ok(query_one_as_json(conn, &sql, [entity_id.to_string()])?);
    }

    match entity_type {
        ENTITY_CURRENT_FOCUS
        | ENTITY_DAILY_REVIEW
        | ENTITY_CALENDAR_EVENT
        | ENTITY_FOCUS_SCHEDULE => {
            // Every aggregate root that owns embedded children
            // (focus_schedule.blocks, current_focus.task_ids,
            // daily_review.linked_*_ids, calendar_event.attendees) goes
            // through the canonical store-side builder so the MCP
            // changelog snapshot, the Tauri app's outbox seeder, the
            // CLI lifecycle paths, and the generic
            // `enqueue_entity_upsert` path all ship the same payload
            // shape. Without the central builder, MCP previously
            // enriched these but `enqueue_entity_upsert` did not,
            // producing silent cross-device drift on the child
            // collections.
            Ok(
                lorvex_sync::payload_build::aggregate::build_aggregate_payload(
                    conn,
                    entity_type,
                    entity_id,
                )?,
            )
        }
        ENTITY_PREFERENCE => {
            let row = query_one_as_json(
                conn,
                "SELECT key, value, updated_at FROM preferences WHERE key = ?",
                [entity_id.to_string()],
            )?;
            row.map_or(Ok(None), |r| parse_preference_row_value(r).map(Some))
        }
        EDGE_TASK_CALENDAR_EVENT_LINK => Ok(query_one_as_json(
            conn,
            "SELECT * FROM task_calendar_event_links WHERE task_id || ':' || calendar_event_id = ?",
            [entity_id.to_string()],
        )?),
        EDGE_HABIT_COMPLETION => {
            // entity_id for habit_completion is "habit_id:completed_date"
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() == 2 {
                Ok(query_one_as_json(
                    conn,
                    "SELECT * FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
                    [parts[0].to_string(), parts[1].to_string()],
                )?)
            } else {
                Ok(None)
            }
        }
        EDGE_TASK_TAG => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() == 2 {
                Ok(query_one_as_json(
                    conn,
                    "SELECT task_id, tag_id, created_at
                     FROM task_tags
                     WHERE task_id = ? AND tag_id = ?",
                    [parts[0].to_string(), parts[1].to_string()],
                )?)
            } else {
                Ok(None)
            }
        }
        EDGE_TASK_DEPENDENCY => {
            let parts: Vec<&str> = entity_id.splitn(2, ':').collect();
            if parts.len() == 2 {
                Ok(query_one_as_json(
                    conn,
                    "SELECT task_id, depends_on_task_id, created_at
                     FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?",
                    [parts[0].to_string(), parts[1].to_string()],
                )?)
            } else {
                Ok(None)
            }
        }
        _ => Ok(None),
    }
}

/// Batched variant of [`read_current_entity_snapshot`]. The funnel-loop
/// in `log_change` SELECT-in-loop'd one row per entity;
/// this helper takes the entire id slice and emits a single
/// `WHERE pk IN (?, ?, …)` query per entity_type, returning a HashMap
/// keyed by `entity_id`.
pub(super) fn read_current_entity_snapshots(
    conn: &Connection,
    entity_type: &str,
    entity_ids: &[String],
) -> Result<HashMap<String, Value>, McpError> {
    if entity_ids.is_empty() {
        return Ok(HashMap::new());
    }

    let Some((table, pk_col, projection)) = simple_pk_plan(entity_type) else {
        // Aggregate roots, preferences, composite-key edges, and unknown
        // entity_types all return an empty map; the caller routes those
        // through the per-entity reader.
        return Ok(HashMap::new());
    };

    // Deduplicate ids so the IN clause has minimal placeholder count.
    let mut seen: std::collections::HashSet<&str> = std::collections::HashSet::new();
    let unique_ids: Vec<&String> = entity_ids
        .iter()
        .filter(|id| seen.insert(id.as_str()))
        .collect();

    assert_simple_pk_identifiers(table, pk_col, projection);
    let columns = projection.as_columns();
    let placeholders = lorvex_domain::sql_in_placeholders(unique_ids.len(), 0);
    let sql = format!("SELECT {columns} FROM {table} WHERE {pk_col} IN ({placeholders})");
    let params: Vec<&dyn rusqlite::types::ToSql> = unique_ids
        .iter()
        .map(|id| *id as &dyn rusqlite::types::ToSql)
        .collect();
    let rows = query_all_as_json(conn, &sql, params.as_slice())?;

    let mut by_id: HashMap<String, Value> = HashMap::with_capacity(rows.len());
    for row in rows {
        if let Some(id_val) = row.get(pk_col).and_then(Value::as_str) {
            by_id.insert(id_val.to_string(), row);
        }
    }
    Ok(by_id)
}

/// Criterion bench harness wrapper for the per-entity snapshot reader.
/// Bench-only — production callers go through the funnel.
pub(crate) fn read_current_entity_snapshot_for_bench(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Option<Value>, McpError> {
    read_current_entity_snapshot(conn, entity_type, entity_id)
}

/// Criterion bench harness wrapper for the batched IN-list snapshot
/// reader.
pub(crate) fn read_current_entity_snapshots_for_bench(
    conn: &Connection,
    entity_type: &str,
    entity_ids: &[String],
) -> Result<HashMap<String, Value>, McpError> {
    read_current_entity_snapshots(conn, entity_type, entity_ids)
}
