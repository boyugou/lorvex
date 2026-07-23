use rusqlite::{named_params, Connection};

use lorvex_domain::ids::{TagId, TaskId};

use super::super::{ApplyError, LwwTieBreak};
use super::helpers::{required_str, split_composite_id};

// ---------------------------------------------------------------------------
// task_tag (PK = task_id, tag_id)
// ---------------------------------------------------------------------------

pub(crate) fn apply_task_tag_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components into typed
    // newtypes at handler entry. The dispatch table fn-pointer signature
    // forces `entity_id: &str`, but every SQL bind site below threads the
    // typed ids via the rusqlite `ToSql` impl on the newtype (zero-copy).
    // Envelope ids are dispatcher-validated upstream; `from_trusted` skips
    // a redundant parse the dispatcher already gated.
    let (task_id_str, tag_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let tag_id = TagId::from_trusted(tag_id_str.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let created_at = required_str(&val, "created_at", "task_tag")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "task_tags",
        columns: &["task_id", "tag_id", "created_at", "version"],
        conflict: &["task_id", "tag_id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":task_id": &task_id,
        ":tag_id": &tag_id,
        ":created_at": created_at,
        ":version": version,
    })?;
    Ok(())
}

pub(crate) fn apply_task_tag_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components to typed ids
    // once at handler entry; the `lww_gated_delete` helper still takes
    // `&[&str]` so we thread `as_str()` through, but the typed binding
    // is the only path that flows into bookkeeping.
    let (task_id_str, tag_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let tag_id = TagId::from_trusted(tag_id_str.to_string());
    // route through `lww_gated_delete` so the in-row
    // LWW guard goes through the typed `Hlc::parse` + byte-compare
    // fallback used by every other edge/child delete handler. The
    // sign on a tainted local version (`'v1'`, `'seed'`) — ascii
    // letters lex above digits, so a tainted local row would
    // refuse a perfectly valid HLC delete envelope. `lww_gated_delete`
    // handles that case via `compare_versions_with_fallback`. Mirrors
    // the same hardening already applied to `apply_task_dependency_delete`
    // and the other composite-PK edge deletes.
    crate::apply::lww_gated_delete(
        conn,
        "task_tags",
        &["task_id", "tag_id"],
        &[task_id.as_str(), tag_id.as_str()],
        version,
    )?;
    Ok(())
}
