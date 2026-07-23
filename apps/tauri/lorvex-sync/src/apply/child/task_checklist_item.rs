use lorvex_domain::ids::{ChecklistItemId, TaskId};

use super::helpers::{optional_str, required_i64, required_str};
use super::*;

pub(crate) fn apply_task_checklist_item_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the PK and the task-id FK into typed
    // newtypes at handler entry. The PK comes from the dispatcher-
    // validated envelope id; the FK comes from the JSON payload (already
    // round-tripped through a peer's typed-write path) — both go through
    // `from_trusted` since the trust-boundary parse happened upstream.
    let id = ChecklistItemId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let task_id_str = required_str(&val, "task_id", "task_checklist_item")?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let position = required_i64(&val, "position", "task_checklist_item")?;
    // Unicode hygiene (#2427): checklist text is user-facing.
    let text_owned =
        lorvex_domain::sanitize_user_text(required_str(&val, "text", "task_checklist_item")?);
    let text: &str = &text_owned;
    let completed_at = optional_str(&val, "completed_at", "task_checklist_item")?;
    let created_at = required_str(&val, "created_at", "task_checklist_item")?;
    let updated_at = required_str(&val, "updated_at", "task_checklist_item")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "task_checklist_items",
        columns: &[
            "id",
            "task_id",
            "position",
            "text",
            "completed_at",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": &id,
        ":task_id": &task_id,
        ":position": position,
        ":text": text,
        ":completed_at": completed_at,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

pub(crate) fn apply_task_checklist_item_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the PK into a typed `ChecklistItemId`
    // at handler entry; the SQL bind threads it via the rusqlite ToSql
    // impl on the newtype.
    let id = ChecklistItemId::from_trusted(entity_id.to_string());
    // route through `lww_gated_delete` so the in-row
    // LWW guard parses the typed HLC instead of byte-comparing the
    // string directly. See `lww/mod.rs::lww_gated_delete` for the
    // discipline rationale.
    crate::apply::lww_gated_delete(
        conn,
        "task_checklist_items",
        &["id"],
        &[id.as_str()],
        version,
    )?;
    Ok(())
}
