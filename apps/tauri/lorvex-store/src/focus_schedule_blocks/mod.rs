//! Shared materialization for the `focus_schedule_blocks` sub-table.
//!
//! The single canonical DELETE-then-INSERT loop. All callers (MCP, Tauri,
//! sync-apply, import) should delegate here instead of owning independent SQL.

use rusqlite::Connection;

/// A normalized schedule block entry with times already converted to
/// minute-of-day integers. Callers parse HH:MM strings or JSON into this
/// intermediate representation before calling [`materialize_schedule_blocks`].
#[derive(Debug, Clone)]
pub struct ScheduleBlockEntry {
    pub block_type: String,
    pub start_minutes: i64,
    pub end_minutes: i64,
    pub task_id: Option<String>,
    pub event_id: Option<String>,
    pub title: Option<String>,
}

/// Materialize schedule blocks for a given date.
///
/// Deletes all existing blocks for `schedule_date`, then inserts `blocks`
/// with sequential positions.
pub fn materialize_schedule_blocks(
    conn: &Connection,
    schedule_date: &str,
    blocks: &[ScheduleBlockEntry],
) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("DELETE FROM focus_schedule_blocks WHERE schedule_date = ?1")?
        .execute([schedule_date])?;

    let mut stmt = conn.prepare_cached(
        "INSERT INTO focus_schedule_blocks \
         (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
    )?;

    for (position, block) in blocks.iter().enumerate() {
        // Clamp to valid range [0, 1440] and ensure start <= end.
        let start = block.start_minutes.clamp(0, 1440);
        let end = block.end_minutes.clamp(start, 1440);
        stmt.execute(rusqlite::params![
            schedule_date,
            position as i64,
            block.block_type,
            start,
            end,
            block.task_id,
            block.event_id,
            block.title,
        ])?;
    }

    Ok(())
}

/// Update only the timestamp of an existing `focus_schedule` row.
/// Timezone is immutable — only `updated_at` is modified.
pub fn touch_focus_schedule_header(
    conn: &Connection,
    date: &str,
    now: &str,
) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("UPDATE focus_schedule SET updated_at = ?1 WHERE date = ?2")?
        .execute(rusqlite::params![now, date])?;
    Ok(())
}

/// Create or update the `focus_schedule` parent row.
///
/// **Timezone immutability**: the ON CONFLICT clause omits timezone,
/// so it is only set on initial INSERT and preserved on subsequent updates.
///
/// the conflict UPDATE is gated on
/// `excluded.version > focus_schedule.version` so a stale local stamp
/// racing an in-flight peer write cannot regress the row's HLC. Returns
/// `true` if a row was inserted or the LWW gate accepted the UPDATE;
/// `false` if the existing row's version was strictly newer than `version`
/// and the upsert became a no-op.
pub fn upsert_focus_schedule_header(
    conn: &Connection,
    date: &str,
    rationale: Option<&str>,
    timezone: &str,
    version: &str,
    now: &str,
) -> Result<bool, rusqlite::Error> {
    let changes = conn
        .prepare_cached(
            "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(date) DO UPDATE SET \
                rationale = excluded.rationale, \
                version = excluded.version, \
                updated_at = excluded.updated_at \
             WHERE excluded.version > focus_schedule.version",
        )?
        .execute(rusqlite::params![date, rationale, timezone, version, now, now])?;
    Ok(changes > 0)
}

/// Comparator used by sync-apply LWW upserts. The
/// previous shape took a `&str` and interpolated it into the WHERE
/// clause, which made it possible (in principle, though no caller
/// actually did so) to inject SQL via a misuse like
/// `version_cmp = "!= 0; DROP TABLE x; --"`. The enum constrains the
/// surface to the only two semantically valid comparators we need
/// today and gives one canonical place to add a third (e.g. `=` for
/// idempotent re-emit) if the LWW protocol ever needs it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncVersionCmp {
    /// Strict greater-than — the standard LWW "newer wins" gate.
    Greater,
    /// Greater-than-or-equal — used by replay / shadow-promote paths
    /// where re-applying an envelope at the same version must be a
    /// silent rehydrate rather than a no-op.
    GreaterOrEqual,
}

#[cfg(test)]
impl SyncVersionCmp {
    /// SQL operator for embedding in an LWW WHERE clause. Test-only
    /// because production callers now reach the cached SQL via the
    /// dual-`OnceLock` match in [`sync_upsert_focus_schedule`]; the
    /// raw operator is preserved here so existing assertions covering
    /// the enum's surface continue to compile.
    pub(crate) fn as_sql(self) -> &'static str {
        match self {
            Self::Greater => ">",
            Self::GreaterOrEqual => ">=",
        }
    }
}

/// Sync-mode upsert: full-entity replacement from another device.
///
/// Unlike local writes, this **does** overwrite `timezone` and `created_at`
/// because the remote envelope is authoritative.
///
/// Returns `true` if a row was inserted or updated, `false` if the
/// existing row was newer.
#[allow(clippy::too_many_arguments)]
pub fn sync_upsert_focus_schedule(
    conn: &Connection,
    date: &str,
    rationale: Option<&str>,
    timezone: Option<&str>,
    version: &str,
    created_at: &str,
    updated_at: &str,
    version_cmp: SyncVersionCmp,
) -> Result<bool, rusqlite::Error> {
    // `format!`-built but `version_cmp.as_sql()` returns one of two
    // `&'static str` values, so the rendered string takes one of two
    // stable shapes for the process lifetime — cache both shapes in
    // `OnceLock` slots so every sync upsert envelope pays its
    // `format!` cost exactly once.
    static SQL_GT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    static SQL_GTE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let render = |op: &str| {
        format!(
            "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(date) DO UPDATE SET \
                rationale=excluded.rationale, timezone=excluded.timezone, \
                created_at=excluded.created_at, updated_at=excluded.updated_at, \
                version=excluded.version \
             WHERE excluded.version {op} focus_schedule.version"
        )
    };
    let sql = match version_cmp {
        SyncVersionCmp::Greater => SQL_GT.get_or_init(|| render(">")),
        SyncVersionCmp::GreaterOrEqual => SQL_GTE.get_or_init(|| render(">=")),
    };
    let changes = conn.prepare_cached(sql)?.execute(rusqlite::params![
        date, rationale, timezone, version, created_at, updated_at
    ])?;
    Ok(changes > 0)
}

#[cfg(test)]
mod tests;
