use lorvex_domain::naming::EntityKind;
use rusqlite::Row;
use serde_json::{json, Value};

use crate::error::StoreError;

/// Canonical SELECT column projection for `ai_changelog`. Delegated
/// to `repositories::columns::AI_CHANGELOG.select_clause`, which
/// carries the correlated `json_group_array` subquery that rebuilds
/// the wire-form `entity_ids` JSON array from
/// `ai_changelog_entities`. The tuple position of `entity_ids` stays
/// `row.get(N)`-keyed mapper below continues to read the same indices.
pub const AI_CHANGELOG_SELECT_COLUMNS: &str =
    crate::repositories::columns::AI_CHANGELOG.select_clause;

/// Primitive shared by the row-mapper and any in-memory writer that
/// inserts a changelog row + emits the sync envelope in a single call
/// without round-tripping through a SELECT (e.g. `startup_trash_purge::audit`).
/// Centralizing the literal closes a drift gap where the audit path
/// omitted `undo_token` and `is_preview` from the wire shape.
pub struct AiChangelogPayload<'a> {
    pub id: &'a str,
    pub timestamp: &'a str,
    pub operation: &'a str,
    pub entity_type: EntityKind,
    pub entity_id: Option<&'a str>,
    pub entity_ids: Option<&'a str>,
    pub summary: &'a str,
    pub initiated_by: &'a str,
    pub mcp_tool: Option<&'a str>,
    pub source_device_id: Option<&'a str>,
    pub before_json: Option<&'a str>,
    pub after_json: Option<&'a str>,
    pub undo_token: Option<&'a str>,
    pub is_preview: bool,
}

pub fn ai_changelog_payload(row: AiChangelogPayload<'_>) -> Value {
    json!({
        "id": row.id,
        "timestamp": row.timestamp,
        "operation": row.operation,
        "entity_type": row.entity_type.as_str(),
        "entity_id": row.entity_id,
        "entity_ids": row.entity_ids,
        "summary": row.summary,
        "initiated_by": row.initiated_by,
        "mcp_tool": row.mcp_tool,
        "source_device_id": row.source_device_id,
        // #2373: structured before/after JSON snapshots for update
        // operations; NULL for legacy / non-update rows.
        "before_json": row.before_json,
        "after_json": row.after_json,
        "undo_token": row.undo_token,
        // #3033-M4: preview rows are filtered upstream of the mapper,
        // but the column round-trips so peers see the same shape this
        // device persisted.
        "is_preview": row.is_preview,
    })
}

pub fn ai_changelog_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let id: String = row.get(0)?;
    let timestamp: String = row.get(1)?;
    let operation: String = row.get(2)?;
    let entity_type_raw: String = row.get(3)?;
    let entity_type = EntityKind::parse(&entity_type_raw).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            3,
            rusqlite::types::Type::Text,
            Box::new(StoreError::Validation(format!(
                "invalid ai_changelog.entity_type column value: {entity_type_raw}"
            ))),
        )
    })?;
    let entity_id: Option<String> = row.get(4)?;
    let entity_ids: Option<String> = row.get(5)?;
    let summary: String = row.get(6)?;
    let initiated_by: String = row.get(7)?;
    let mcp_tool: Option<String> = row.get(8)?;
    let source_device_id: Option<String> = row.get(9)?;
    let before_json: Option<String> = row.get(10)?;
    let after_json: Option<String> = row.get(11)?;
    let undo_token: Option<String> = row.get(12)?;
    let is_preview: i64 = row.get(13)?;
    Ok(ai_changelog_payload(AiChangelogPayload {
        id: &id,
        timestamp: &timestamp,
        operation: &operation,
        entity_type,
        entity_id: entity_id.as_deref(),
        entity_ids: entity_ids.as_deref(),
        summary: &summary,
        initiated_by: &initiated_by,
        mcp_tool: mcp_tool.as_deref(),
        source_device_id: source_device_id.as_deref(),
        before_json: before_json.as_deref(),
        after_json: after_json.as_deref(),
        undo_token: undo_token.as_deref(),
        is_preview: is_preview != 0,
    }))
}
