use rusqlite::{named_params, Connection};

use lorvex_domain::ids::{EventId, TaskId};

use super::super::{ApplyError, LwwTieBreak};
use super::helpers::{required_str, split_composite_id};

// ---------------------------------------------------------------------------
// task_calendar_event_link (PK = task_id, calendar_event_id)
// ---------------------------------------------------------------------------

pub(crate) fn apply_task_calendar_event_link_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components into typed
    // newtypes at handler entry. SQL bind sites use the rusqlite ToSql
    // impl on the newtype (zero-copy). Dispatcher-validated upstream so
    // `from_trusted` skips a redundant parse.
    let (task_id_str, calendar_event_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let calendar_event_id = EventId::from_trusted(calendar_event_id_str.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let created_at = required_str(&val, "created_at", "task_calendar_event_link")?;
    let updated_at = required_str(&val, "updated_at", "task_calendar_event_link")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "task_calendar_event_links",
        columns: &[
            "task_id",
            "calendar_event_id",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["task_id", "calendar_event_id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":task_id": &task_id,
        ":calendar_event_id": &calendar_event_id,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

pub(crate) fn apply_task_calendar_event_link_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the composite components to typed ids
    // once at handler entry. `lww_gated_delete` still takes `&[&str]`
    // so we feed `as_str()` through.
    let (task_id_str, calendar_event_id_str) = split_composite_id(entity_id)?;
    let task_id = TaskId::from_trusted(task_id_str.to_string());
    let calendar_event_id = EventId::from_trusted(calendar_event_id_str.to_string());
    // defense-in-depth in-row LWW guard. See `lww_gated_delete` for
    // the typed-comparator discipline this routes through.
    crate::apply::lww_gated_delete(
        conn,
        "task_calendar_event_links",
        &["task_id", "calendar_event_id"],
        &[task_id.as_str(), calendar_event_id.as_str()],
        version,
    )?;
    Ok(())
}
