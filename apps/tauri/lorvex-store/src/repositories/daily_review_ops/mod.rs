//! Shared parent-row operations for the `daily_reviews` table.
//!
//! The single canonical upsert with immutable timezone semantics.
//! Both MCP and Tauri delegate here instead of owning independent SQL.

use crate::StoreError;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;
use rusqlite::{Connection, OptionalExtension};
use serde::Serialize;

pub const DAILY_REVIEW_ROW_COLUMNS: &[&str] = &[
    "date",
    "summary",
    "mood",
    "energy_level",
    "wins",
    "blockers",
    "learnings",
    "ai_synthesis",
    "timezone",
    "version",
    "created_at",
    "updated_at",
];

pub const DAILY_REVIEW_ROW_COLS: &str = "date, summary, mood, energy_level, wins, blockers, \
     learnings, ai_synthesis, timezone, version, created_at, updated_at";

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct DailyReviewRow {
    pub date: String,
    pub summary: String,
    pub mood: Option<i64>,
    pub energy_level: Option<i64>,
    pub wins: Option<String>,
    pub blockers: Option<String>,
    pub learnings: Option<String>,
    pub ai_synthesis: Option<String>,
    pub timezone: Option<String>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
    pub linked_task_ids: Vec<String>,
    pub linked_list_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DailyReviewHistoryQuery<'a> {
    pub since: Option<&'a str>,
    pub limit: u32,
    pub offset: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DailyReviewHistoryPage {
    pub rows: Vec<DailyReviewRow>,
    pub total_matching: i64,
}

pub fn get_daily_review_row(
    conn: &Connection,
    date: &str,
) -> Result<Option<DailyReviewRow>, StoreError> {
    let mut stmt = conn.prepare_cached(&format!(
        "SELECT {DAILY_REVIEW_ROW_COLS} FROM daily_reviews WHERE date = ?1"
    ))?;
    let row = stmt
        .query_row([date], daily_review_row_from_sql_row)
        .optional()?;
    let Some(row) = row else {
        return Ok(None);
    };
    let mut rows = enrich_daily_review_rows(conn, vec![row])?;
    Ok(rows.pop())
}

pub fn list_daily_review_rows(
    conn: &Connection,
    query: DailyReviewHistoryQuery<'_>,
) -> Result<DailyReviewHistoryPage, StoreError> {
    let total_matching: i64 = if let Some(since) = query.since {
        conn.query_row(
            "SELECT COUNT(*) FROM daily_reviews WHERE date >= ?1",
            [since],
            |row| row.get(0),
        )?
    } else {
        conn.query_row("SELECT COUNT(*) FROM daily_reviews", [], |row| row.get(0))?
    };
    let limit = i64::from(query.limit);
    let offset = i64::from(query.offset);
    let dates = if let Some(since) = query.since {
        let mut stmt = conn.prepare_cached(
            "SELECT date FROM daily_reviews WHERE date >= ?1 ORDER BY date DESC LIMIT ?2 OFFSET ?3",
        )?;
        let rows = stmt
            .query_map(rusqlite::params![since, limit, offset], |row| row.get(0))?
            .collect::<Result<Vec<String>, _>>()?;
        rows
    } else {
        let mut stmt = conn.prepare_cached(
            "SELECT date FROM daily_reviews ORDER BY date DESC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt
            .query_map(rusqlite::params![limit, offset], |row| row.get(0))?
            .collect::<Result<Vec<String>, _>>()?;
        rows
    };

    Ok(DailyReviewHistoryPage {
        rows: load_daily_review_rows_for_dates(conn, dates)?,
        total_matching,
    })
}

fn load_daily_review_rows_for_dates(
    conn: &Connection,
    dates: Vec<String>,
) -> Result<Vec<DailyReviewRow>, StoreError> {
    if dates.is_empty() {
        return Ok(Vec::new());
    }
    let placeholders = lorvex_domain::sql_csv_placeholders(dates.len());
    let sql =
        format!("SELECT {DAILY_REVIEW_ROW_COLS} FROM daily_reviews WHERE date IN ({placeholders})");
    let mut stmt = conn.prepare(&sql)?;
    let mut rows_by_date: std::collections::HashMap<String, DailyReviewRow> = stmt
        .query_map(rusqlite::params_from_iter(dates.iter()), |row| {
            let review = daily_review_row_from_sql_row(row)?;
            Ok((review.date.clone(), review))
        })?
        .collect::<Result<_, _>>()?;
    drop(stmt);

    attach_daily_review_links(conn, &dates, &mut rows_by_date)?;

    dates
        .into_iter()
        .map(|date| {
            rows_by_date.remove(&date).ok_or_else(|| {
                StoreError::Invariant(format!(
                    "daily review '{date}' disappeared while loading history"
                ))
            })
        })
        .collect()
}

fn daily_review_row_from_sql_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<DailyReviewRow> {
    Ok(DailyReviewRow {
        date: row.get(0)?,
        summary: row.get(1)?,
        mood: row.get(2)?,
        energy_level: row.get(3)?,
        wins: row.get(4)?,
        blockers: row.get(5)?,
        learnings: row.get(6)?,
        ai_synthesis: row.get(7)?,
        timezone: row.get(8)?,
        version: row.get(9)?,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
        linked_task_ids: Vec::new(),
        linked_list_ids: Vec::new(),
    })
}

fn enrich_daily_review_rows(
    conn: &Connection,
    mut rows: Vec<DailyReviewRow>,
) -> Result<Vec<DailyReviewRow>, StoreError> {
    if rows.is_empty() {
        return Ok(rows);
    }
    let dates: Vec<String> = rows.iter().map(|row| row.date.clone()).collect();
    let mut rows_by_date: std::collections::HashMap<String, DailyReviewRow> =
        rows.drain(..).map(|row| (row.date.clone(), row)).collect();
    attach_daily_review_links(conn, &dates, &mut rows_by_date)?;
    dates
        .into_iter()
        .map(|date| {
            rows_by_date.remove(&date).ok_or_else(|| {
                StoreError::Invariant(format!(
                    "daily review '{date}' disappeared while enriching links"
                ))
            })
        })
        .collect()
}

fn attach_daily_review_links(
    conn: &Connection,
    dates: &[String],
    rows_by_date: &mut std::collections::HashMap<String, DailyReviewRow>,
) -> Result<(), StoreError> {
    for (review_date, task_id) in
        query_review_links(conn, "daily_review_task_links", "task_id", dates)?
    {
        if let Some(row) = rows_by_date.get_mut(&review_date) {
            row.linked_task_ids.push(task_id);
        }
    }
    for (review_date, list_id) in
        query_review_links(conn, "daily_review_list_links", "list_id", dates)?
    {
        if let Some(row) = rows_by_date.get_mut(&review_date) {
            row.linked_list_ids.push(list_id);
        }
    }
    Ok(())
}

fn query_review_links(
    conn: &Connection,
    table: &'static str,
    id_column: &'static str,
    dates: &[String],
) -> Result<Vec<(String, String)>, StoreError> {
    if dates.is_empty() {
        return Ok(Vec::new());
    }
    debug_assert!(matches!(
        (table, id_column),
        ("daily_review_task_links", "task_id") | ("daily_review_list_links", "list_id")
    ));
    let placeholders = lorvex_domain::sql_csv_placeholders(dates.len());
    let sql = format!(
        "SELECT review_date, {id_column} FROM {table} \
         WHERE review_date IN ({placeholders}) \
         ORDER BY review_date ASC, created_at ASC, {id_column} ASC"
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt
        .query_map(rusqlite::params_from_iter(dates.iter()), |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// Parameters for upserting a daily review.
///
/// All optional fields use COALESCE semantics on update: a new non-NULL
/// value overwrites the existing value, but NULL preserves the existing value.
#[derive(Debug, Clone)]
pub struct UpsertDailyReviewParams<'a> {
    pub date: &'a str,
    pub summary: &'a str,
    pub mood: Option<i64>,
    pub energy_level: Option<i64>,
    pub wins: Option<&'a str>,
    pub blockers: Option<&'a str>,
    pub learnings: Option<&'a str>,
    pub ai_synthesis: Option<&'a str>,
    pub timezone: &'a str,
    pub version: &'a str,
    pub now: &'a str,
}

/// Create or update a daily review.
///
/// **Timezone immutability**: the ON CONFLICT clause intentionally excludes
/// `timezone` and `created_at`, so both are only set on initial INSERT and
/// preserved on subsequent updates.
///
/// Optional fields (`mood`, `energy_level`, `wins`, `blockers`, `learnings`,
/// `ai_synthesis`) use COALESCE semantics: a new non-NULL value wins, but
/// NULL preserves the existing value.
///
/// the conflict UPDATE is gated on
/// `excluded.version > daily_reviews.version` so a stale local stamp racing
/// an in-flight peer write cannot regress the row's HLC. Returns `true`
/// when a row was inserted or the LWW gate accepted the UPDATE; `false`
/// when the existing row's version was strictly newer than `params.version`
/// and the upsert became a no-op.
pub fn upsert_daily_review(
    conn: &Connection,
    params: &UpsertDailyReviewParams<'_>,
) -> Result<bool, rusqlite::Error> {
    // NOTE: The ON CONFLICT clause intentionally excludes `timezone` and
    // `created_at` to preserve day-scoped aggregate immutability.  The
    // timezone is anchored at row-creation time and must never change on
    // subsequent updates.  Do NOT add `timezone = ...` or `created_at = ...`
    // to the DO UPDATE SET clause.
    let changes = conn
        .prepare_cached(
            "INSERT INTO daily_reviews \
            (date, summary, mood, energy_level, wins, blockers, learnings, \
             ai_synthesis, timezone, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11) \
         ON CONFLICT(date) DO UPDATE SET \
            summary = excluded.summary, \
            mood = COALESCE(excluded.mood, daily_reviews.mood), \
            energy_level = COALESCE(excluded.energy_level, daily_reviews.energy_level), \
            wins = COALESCE(excluded.wins, daily_reviews.wins), \
            blockers = COALESCE(excluded.blockers, daily_reviews.blockers), \
            learnings = COALESCE(excluded.learnings, daily_reviews.learnings), \
            ai_synthesis = COALESCE(excluded.ai_synthesis, daily_reviews.ai_synthesis), \
            version = excluded.version, \
            updated_at = excluded.updated_at \
         WHERE excluded.version > daily_reviews.version",
        )?
        .execute(rusqlite::params![
            params.date,
            params.summary,
            params.mood,
            params.energy_level,
            params.wins,
            params.blockers,
            params.learnings,
            params.ai_synthesis,
            params.timezone,
            params.version,
            params.now,
        ])?;
    Ok(changes > 0)
}

/// Convert the local daily-review LWW bool contract into the typed
/// stale-version error boundary every writer surface expects.
///
/// The repository functions return `false` for LWW no-ops so sync/import
/// callers can choose their own merge behavior. Local writers must fail
/// closed before rebuilding child links, audit rows, or outbox payloads.
pub fn require_daily_review_write_applied(applied: bool, date: &str) -> Result<(), StoreError> {
    if applied {
        return Ok(());
    }
    Err(StoreError::StaleVersion {
        entity: ENTITY_DAILY_REVIEW,
        id: date.to_string(),
    })
}

/// Sync-mode upsert: full-entity replacement from another device.
///
/// Unlike local writes, this **does** overwrite `timezone` and `created_at`
/// because the remote envelope is authoritative. It also performs direct
/// field assignment (no COALESCE) since sync payloads carry the complete
/// canonical state.
///
/// `version_cmp` should be `">"` for normal sync or `">="` when the
/// capability negotiation allows equal-version acceptance.
///
/// Returns `true` if a row was inserted or updated, `false` if the
/// existing row was newer.
#[allow(clippy::too_many_arguments)]
pub fn sync_upsert_daily_review(
    conn: &Connection,
    date: &str,
    summary: &str,
    mood: Option<i64>,
    energy_level: Option<i64>,
    wins: Option<&str>,
    blockers: Option<&str>,
    learnings: Option<&str>,
    ai_synthesis: Option<&str>,
    timezone: Option<&str>,
    version: &str,
    created_at: &str,
    updated_at: &str,
    version_cmp: &str,
) -> Result<bool, rusqlite::Error> {
    // SQL takes one of two shapes (`>` or `>=`); cache both so the
    // sync-apply path pays its `format!` cost exactly once. See
    // `current_focus_items::sync_upsert_current_focus` for the
    // sibling pattern.
    static SQL_GT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    static SQL_GTE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let render = |op: &str| {
        format!(
            "INSERT INTO daily_reviews \
                (date, summary, mood, energy_level, wins, blockers, learnings, \
                 ai_synthesis, timezone, created_at, updated_at, version) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) \
             ON CONFLICT(date) DO UPDATE SET \
                summary=excluded.summary, mood=excluded.mood, energy_level=excluded.energy_level, \
                wins=excluded.wins, blockers=excluded.blockers, learnings=excluded.learnings, \
                ai_synthesis=excluded.ai_synthesis, timezone=excluded.timezone, \
                created_at=excluded.created_at, updated_at=excluded.updated_at, \
                version=excluded.version \
             WHERE excluded.version {op} daily_reviews.version"
        )
    };
    let sql = match version_cmp {
        ">" => SQL_GT.get_or_init(|| render(">")),
        ">=" => SQL_GTE.get_or_init(|| render(">=")),
        other => {
            return Err(rusqlite::Error::InvalidParameterName(format!(
                "sync_upsert_daily_review: version_cmp must be \">\" or \">=\", got {other:?}"
            )));
        }
    };
    let changes = conn.execute(
        sql,
        rusqlite::params![
            date,
            summary,
            mood,
            energy_level,
            wins,
            blockers,
            learnings,
            ai_synthesis,
            timezone,
            created_at,
            updated_at,
            version
        ],
    )?;
    Ok(changes > 0)
}

// ---------------------------------------------------------------------------
// Partial update (amend)
// ---------------------------------------------------------------------------

/// Parameters for amending (partial update) an existing daily review.
/// Only non-None fields are updated. Timezone is backfilled only if
/// currently NULL (preserving immutability for existing values).
#[derive(Debug, Clone, Default)]
pub struct AmendDailyReviewParams<'a> {
    pub date: &'a str,
    pub summary: Option<&'a str>,
    pub mood: Option<i64>,
    pub energy_level: Option<i64>,
    pub wins: Option<&'a str>,
    pub blockers: Option<&'a str>,
    pub learnings: Option<&'a str>,
    pub ai_synthesis: Option<&'a str>,
    pub timezone_backfill: Option<&'a str>, // only applied if existing tz is NULL
    pub version: &'a str,
    pub now: &'a str,
}

/// Amend (partially update) an existing daily review row.
///
/// Only fields that are `Some` in `params` are included in the UPDATE SET
/// clause. `timezone_backfill` is only applied when the existing row's
/// timezone is NULL (backfill, not overwrite).
///
/// Returns `true` if a row was updated, `false` if no row exists for the date.
pub fn amend_daily_review(
    conn: &Connection,
    params: &AmendDailyReviewParams<'_>,
) -> Result<bool, rusqlite::Error> {
    let mut set_clauses = Vec::new();
    let mut values: Vec<&dyn rusqlite::types::ToSql> = Vec::new();

    if let Some(ref summary) = params.summary {
        values.push(summary);
        set_clauses.push(format!("summary = ?{}", values.len()));
    }
    if let Some(ref mood) = params.mood {
        values.push(mood);
        set_clauses.push(format!("mood = ?{}", values.len()));
    }
    if let Some(ref energy) = params.energy_level {
        values.push(energy);
        set_clauses.push(format!("energy_level = ?{}", values.len()));
    }
    if let Some(ref wins) = params.wins {
        values.push(wins);
        set_clauses.push(format!("wins = ?{}", values.len()));
    }
    if let Some(ref blockers) = params.blockers {
        values.push(blockers);
        set_clauses.push(format!("blockers = ?{}", values.len()));
    }
    if let Some(ref learnings) = params.learnings {
        values.push(learnings);
        set_clauses.push(format!("learnings = ?{}", values.len()));
    }
    if let Some(ref ai_synthesis) = params.ai_synthesis {
        values.push(ai_synthesis);
        set_clauses.push(format!("ai_synthesis = ?{}", values.len()));
    }
    if let Some(ref tz) = params.timezone_backfill {
        // Only backfill if existing timezone is NULL
        values.push(tz);
        set_clauses.push(format!(
            "timezone = CASE WHEN timezone IS NULL THEN ?{} ELSE timezone END",
            values.len()
        ));
    }

    // Always update version and updated_at
    values.push(&params.version);
    set_clauses.push(format!("version = ?{}", values.len()));
    values.push(&params.now);
    set_clauses.push(format!("updated_at = ?{}", values.len()));

    // Date + LWW version param.
    //
    // gate on `?version > daily_reviews.version` so a
    // local amend racing an in-flight sync apply that already landed a
    // newer remote version cannot blindly overwrite the cluster's
    // state. Mirrors the guard added to apply_task_update and
    // apply_calendar_event_update.
    values.push(&params.date);
    let date_idx = values.len();
    values.push(&params.version);
    let version_idx = values.len();

    let sql = format!(
        "UPDATE daily_reviews SET {} WHERE date = ?{date_idx} AND ?{version_idx} > version",
        set_clauses.join(", ")
    );

    // The runtime-length placeholder pattern relies on `values`
    // containing at least the version + updated_at + date + version-
    // guard tuple every call. The structure of this function makes
    // that hold (those four pushes are unconditional after the
    // optional set_clauses), but a future refactor that gates one of
    // them behind an `if let Some(...)` would silently produce a SQL
    // statement with zero parameters, executing on an arbitrary row.
    // Assert the invariant so the compiler-friendly debug build flags
    // such a regression at the test boundary.
    debug_assert!(
        !values.is_empty() && !set_clauses.is_empty(),
        "amend_daily_review must always bind at least version + updated_at + date + version-guard"
    );
    let changes = conn.execute(&sql, values.as_slice())?;
    Ok(changes > 0)
}

// ---------------------------------------------------------------------------
// Child materialization: daily_review links
// ---------------------------------------------------------------------------

/// Materialize `daily_review_task_links` for a given date.
///
/// Deletes all existing links for `date`, then inserts each `task_id`.
///
/// `daily_review_task_links.task_id` is declared
/// `NOT NULL` with no `REFERENCES tasks(id)` (intentional — a
/// re-import or out-of-order sync apply may stage the link before
/// the parent task lands). Without an FK, an orphaned reference
/// (e.g. a task that was hard-deleted before its review row
/// rebuilt) silently accumulates in the table forever. Surface the
/// drift to `error_logs` so a recurring orphan is visible to
/// Settings → Diagnostics; the link itself is still inserted
/// because re-import / late-apply is the most common cause and the
/// orphan resolves once the parent row materializes.
pub fn materialize_review_task_links(
    conn: &Connection,
    date: &str,
    task_ids: &[String],
) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("DELETE FROM daily_review_task_links WHERE review_date = ?1")?
        .execute([date])?;
    let missing = collect_missing_ids(conn, "tasks", task_ids)?;
    {
        let mut stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO daily_review_task_links (review_date, task_id, created_at) \
             VALUES (?1, ?2, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
        )?;
        for task_id in task_ids {
            stmt.execute(rusqlite::params![date, task_id])?;
        }
    }
    if !missing.is_empty() {
        crate::error::log::append_error_log_best_effort(
            conn,
            "store.daily_review.materialize_task_links.orphan",
            &format!(
                "daily_review {date}: {n} task_id(s) materialized without a matching \
                 tasks row (possible orphan from re-import / out-of-order apply): {ids}",
                n = missing.len(),
                ids = missing.join(", "),
            ),
            None,
            Some("warn"),
        );
    }
    Ok(())
}

/// Materialize `daily_review_list_links` for a given date.
///
/// Deletes all existing links for `date`, then inserts each `list_id`.
/// Same orphan-detection contract as
/// [`materialize_review_task_links`].
pub fn materialize_review_list_links(
    conn: &Connection,
    date: &str,
    list_ids: &[String],
) -> Result<(), rusqlite::Error> {
    conn.prepare_cached("DELETE FROM daily_review_list_links WHERE review_date = ?1")?
        .execute([date])?;
    let missing = collect_missing_ids(conn, "lists", list_ids)?;
    {
        let mut stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO daily_review_list_links (review_date, list_id, created_at) \
             VALUES (?1, ?2, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))",
        )?;
        for list_id in list_ids {
            stmt.execute(rusqlite::params![date, list_id])?;
        }
    }
    if !missing.is_empty() {
        crate::error::log::append_error_log_best_effort(
            conn,
            "store.daily_review.materialize_list_links.orphan",
            &format!(
                "daily_review {date}: {n} list_id(s) materialized without a matching \
                 lists row (possible orphan from re-import / out-of-order apply): {ids}",
                n = missing.len(),
                ids = missing.join(", "),
            ),
            None,
            Some("warn"),
        );
    }
    Ok(())
}

/// Return the subset of `ids` that have no row in `table` (matched
/// against the row's `id` column). Used by both link materializers
/// to flag orphan link inserts after the fact.
///
/// the previous shape ran one
/// `SELECT 1 FROM <table> WHERE id = ?1` per id (an N+1 query).
/// We now bind every id into a single
/// `SELECT id FROM <table> WHERE id IN (...)` and set-diff the
/// result against the input. `table` is allowlisted to the two
/// callers ("tasks" / "lists") so the format!-built SQL can never
/// receive untrusted input.
fn collect_missing_ids(
    conn: &Connection,
    table: &'static str,
    ids: &[String],
) -> Result<Vec<String>, rusqlite::Error> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    debug_assert!(
        matches!(table, "tasks" | "lists"),
        "collect_missing_ids `table` must be a literal allowlisted by the caller"
    );
    let placeholders = lorvex_domain::sql_csv_placeholders(ids.len());
    let sql = format!("SELECT id FROM {table} WHERE id IN ({placeholders})");
    let mut stmt = conn.prepare(&sql)?;
    let bound: Vec<&dyn rusqlite::ToSql> = ids.iter().map(|s| s as &dyn rusqlite::ToSql).collect();
    let present: std::collections::HashSet<String> = stmt
        .query_map(rusqlite::params_from_iter(bound), |row| row.get(0))?
        .collect::<Result<_, _>>()?;
    Ok(ids
        .iter()
        .filter(|id| !present.contains(id.as_str()))
        .cloned()
        .collect())
}

#[cfg(test)]
mod tests;
