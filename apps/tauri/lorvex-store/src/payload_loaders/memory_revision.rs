use lorvex_domain::{MemoryKey, MemoryRevisionId};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const MEMORY_REVISION_SELECT_COLUMNS: &str =
    "id, memory_key, content, operation, source_revision_id, actor, version, created_at";

struct MemoryRevisionPayload<'a> {
    id: &'a MemoryRevisionId,
    memory_key: &'a MemoryKey,
    content: Option<&'a str>,
    operation: &'a str,
    source_revision_id: Option<&'a MemoryRevisionId>,
    actor: &'a str,
    version: &'a str,
    created_at: &'a str,
}

fn memory_revision_payload(row: MemoryRevisionPayload<'_>) -> Value {
    json!({
        "id": row.id,
        "memory_key": row.memory_key,
        "content": row.content,
        "operation": row.operation,
        "source_revision_id": row.source_revision_id,
        "actor": row.actor,
        "version": row.version,
        "created_at": row.created_at,
    })
}

pub fn memory_revision_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let id: MemoryRevisionId = row.get(0)?;
    let memory_key: MemoryKey = row.get(1)?;
    let content: Option<String> = row.get(2)?;
    let operation: String = row.get(3)?;
    let source_revision_id: Option<MemoryRevisionId> = row.get(4)?;
    let actor: String = row.get(5)?;
    let version: String = row.get(6)?;
    let created_at: String = row.get(7)?;
    Ok(memory_revision_payload(MemoryRevisionPayload {
        id: &id,
        memory_key: &memory_key,
        content: content.as_deref(),
        operation: &operation,
        source_revision_id: source_revision_id.as_ref(),
        actor: &actor,
        version: &version,
        created_at: &created_at,
    }))
}

pub fn load_memory_revision_sync_payload(
    conn: &Connection,
    revision_id: &MemoryRevisionId,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("SELECT {MEMORY_REVISION_SELECT_COLUMNS} FROM memory_revisions WHERE id = ?1")
    });
    Ok(conn
        .query_row(sql, params![revision_id], memory_revision_payload_from_row)
        .optional()?)
}
