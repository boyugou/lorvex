use super::{
    link_from_row, resolved_link_from_row, ProviderEventLinkDeleteResult,
    ProviderEventLinkWithResolution, TaskProviderEventLink, SELECT_COLS,
};
use crate::error::StoreError;
use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/// Insert or update a task ↔ provider-event link. Returns the upserted row.
pub fn upsert_provider_event_link(
    conn: &Connection,
    task_id: &TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<TaskProviderEventLink, StoreError> {
    // Use millisecond `Z` form via `sync_timestamp_now()` (see
    // `lorvex-domain/src/time/sync_timestamp.rs`) — every other timestamp column
    // in the codebase uses this precision, and mixed formats break
    // lex comparison at the fractional-second boundary (`.123Z` vs
    // `.123456Z` at position 20). Same drift class as R11/R12.
    let now = lorvex_domain::sync_timestamp_now();

    let mut upsert = conn.prepare_cached(
        "INSERT INTO task_provider_event_links \
             (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?5) \
         ON CONFLICT(task_id, provider_kind, provider_scope, provider_event_key) DO UPDATE SET \
           updated_at = excluded.updated_at",
    )?;
    upsert.execute(params![
        task_id,
        provider_kind,
        provider_scope,
        provider_event_key,
        now,
    ])?;
    drop(upsert);

    // `format!`-built SELECT carries only the static
    // `SELECT_COLS` fragment; cache the assembled string in a
    // `LazyLock` so the prepare cache key stays the same byte
    // sequence across calls.
    let mut select = conn.prepare_cached(provider_event_link_select_by_pk_sql())?;
    Ok(select.query_row(
        params![task_id, provider_kind, provider_scope, provider_event_key],
        link_from_row,
    )?)
}

/// Stable `&'static str` for the by-PK SELECT against
/// `task_provider_event_links`. The query body is identical across
/// `upsert_provider_event_link` and `get_provider_event_link`; caching
/// the assembled string on first call lets `prepare_cached` reuse the
/// same plan for both call sites.
fn provider_event_link_select_by_pk_sql() -> &'static str {
    use std::sync::LazyLock;
    static SQL: LazyLock<String> = LazyLock::new(|| {
        format!(
            "SELECT {SELECT_COLS} FROM task_provider_event_links \
             WHERE task_id = ?1 AND provider_kind = ?2 AND provider_scope = ?3 AND provider_event_key = ?4"
        )
    });
    &SQL
}

/// Read a single task ↔ provider-event link by composite key. Returns
/// `None` if no row matches. Audit-trail callers (#3019-H1) use this
/// to capture a `before_json` snapshot before `delete_provider_event_link`
/// destroys the row.
pub fn get_provider_event_link(
    conn: &Connection,
    task_id: &TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<Option<TaskProviderEventLink>, StoreError> {
    let mut stmt = conn.prepare_cached(provider_event_link_select_by_pk_sql())?;
    match stmt.query_row(
        params![task_id, provider_kind, provider_scope, provider_event_key],
        link_from_row,
    ) {
        Ok(link) => Ok(Some(link)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Remove a task ↔ provider-event link. Returns whether a row was deleted,
/// the pre-delete row when one existed, and the remaining links for the task.
/// Callers use the typed result to avoid logging/auditing no-op deletes.
pub fn delete_provider_event_link(
    conn: &Connection,
    task_id: &TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<ProviderEventLinkDeleteResult, StoreError> {
    let before = get_provider_event_link(
        conn,
        task_id,
        provider_kind,
        provider_scope,
        provider_event_key,
    )?;
    let delete_sql =
        "DELETE FROM task_provider_event_links \
         WHERE task_id = ?1 AND provider_kind = ?2 AND provider_scope = ?3 AND provider_event_key = ?4";
    let deleted_rows = conn.prepare_cached(delete_sql)?.execute(params![
        task_id,
        provider_kind,
        provider_scope,
        provider_event_key
    ])?;

    let query = format!(
        "SELECT {SELECT_COLS} FROM task_provider_event_links WHERE task_id = ?1 \
         ORDER BY created_at, provider_kind, provider_scope, provider_event_key"
    );
    let mut stmt = conn.prepare_cached(&query)?;
    let links = stmt
        .query_map(params![task_id], link_from_row)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ProviderEventLinkDeleteResult {
        deleted: deleted_rows > 0,
        before,
        remaining_links: links,
    })
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

/// Return provider links for a task with runtime resolution state.
///
/// Each link is LEFT JOINed against both the provider event cache and
/// `provider_scope_runtime_state`.  The resolution is computed in
/// a single query round-trip:
///
///   - `"resolved"` — provider event exists in local cache
///   - `"pending"` — enabled scope has not completed its first refresh
///   - `"stale"` — enabled scope has refreshed, but the success is older than
///     the provider freshness window
///   - `"unavailable"` — scope is disabled, unconfigured, or currently failing
///   - `"missing"` — scope is enabled and freshly refreshed, but the event is
///     absent upstream
pub fn get_resolved_provider_links_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<ProviderEventLinkWithResolution>, StoreError> {
    let query = "\
        SELECT tpl.task_id, tpl.provider_kind, tpl.provider_scope, tpl.provider_event_key,
               tpl.created_at, tpl.updated_at,
               pce.title, pce.start_date, pce.start_time,
               pce.provider_event_key IS NOT NULL AS has_event,
               psr.availability_state,
               psr.last_refresh_success_at,
               psr.last_refresh_result,
               psr.provider_kind IS NOT NULL AS has_runtime_state,
               s.enabled = 1 AS ical_subscription_enabled,
               psr.last_refresh_success_at IS NOT NULL
                 AND psr.last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')
                 AS scope_stale
        FROM task_provider_event_links tpl
        LEFT JOIN provider_calendar_events pce
          ON tpl.provider_kind = pce.provider_kind
         AND tpl.provider_scope = pce.provider_scope
         AND tpl.provider_event_key = pce.provider_event_key
        LEFT JOIN provider_scope_runtime_state psr
          ON tpl.provider_kind = psr.provider_kind
         AND tpl.provider_scope = psr.provider_scope
        LEFT JOIN calendar_subscriptions s
          ON tpl.provider_kind = 'ical_subscription'
         AND tpl.provider_scope = s.id
        WHERE tpl.task_id = ?1
        ORDER BY tpl.created_at, tpl.provider_kind, tpl.provider_scope, tpl.provider_event_key";

    let mut stmt = conn.prepare_cached(query)?;
    let links = stmt
        .query_map(params![task_id], resolved_link_from_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(links)
}
