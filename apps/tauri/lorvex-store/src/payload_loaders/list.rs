use serde_json::{json, Value};

/// Render a `lists` row to its canonical sync wire shape.
///
/// Takes the in-memory [`crate::repositories::list_repo::ListRow`]
/// struct so callers that already loaded the row don't pay a second
/// SELECT.
/// sites inside `db_ops/lists/mod.rs`; routing through the spb
/// primitive keeps the upsert/delete envelope and the audit
/// `before_json` / `after_json` snapshots in lock-step.
pub fn list_payload(list: &crate::repositories::list_repo::ListRow) -> Value {
    json!({
        "id": list.id,
        "name": list.name,
        "color": list.color,
        "icon": list.icon,
        "description": list.description,
        "ai_notes": list.ai_notes,
        "created_at": list.created_at,
        "updated_at": list.updated_at,
        "version": list.version,
        "archived_at": list.archived_at,
        "position": list.position,
    })
}
