use crate::error::StoreError;
use lorvex_domain::naming::{AVAILABILITY_STATE_ENABLED, AVAILABILITY_STATE_PERMISSION_DENIED};
use rusqlite::{params, Connection, OptionalExtension};

// ---------------------------------------------------------------------------
// Provider operational status
// ---------------------------------------------------------------------------

/// Single source of truth for whether a provider scope is queryable.
///
/// A scope is queryable if and only if `provider_scope_runtime_state`
/// has `availability_state = 'enabled'` for this (kind, scope) pair.
/// All writer paths (EventKit refresh, .ics toggle/refresh, etc.) are
/// responsible for keeping this column up-to-date.
///
/// This function is the ONLY eligibility check that should be used.
/// The timeline query gating (SQL EXISTS filter) and link resolution
/// both defer to the same `availability_state = 'enabled'` contract.
pub fn is_provider_scope_queryable(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
) -> Result<bool, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT availability_state = '{AVAILABILITY_STATE_ENABLED}' FROM provider_scope_runtime_state \
             WHERE provider_kind = ?1 AND provider_scope = ?2"
        )
    });
    Ok(conn
        .query_row(sql, params![provider_kind, provider_scope], |row| {
            row.get::<_, bool>(0)
        })
        .optional()?
        .unwrap_or(false))
}

/// Read the stored `next_attempt_at` cooldown, if any. Callers compare
/// it lexicographically to the current RFC3339 timestamp to decide
/// whether to skip a refresh cycle. Missing row or NULL column → None.
pub fn get_provider_scope_next_attempt_at(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
) -> Result<Option<String>, StoreError> {
    Ok(conn
        .query_row(
            "SELECT next_attempt_at FROM provider_scope_runtime_state \
             WHERE provider_kind = ?1 AND provider_scope = ?2",
            params![provider_kind, provider_scope],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()?
        .flatten())
}

// ---------------------------------------------------------------------------
// Provider scope runtime state — centralized writer
// ---------------------------------------------------------------------------

/// State transition for a provider scope runtime record.
#[derive(Clone, Copy)]
pub enum ProviderScopeTransition<'a> {
    /// Toggle enable/disable (e.g. user flips the calendar subscription toggle).
    Toggle { enabled: bool },
    /// Record a successful refresh.
    RefreshSuccess { now: &'a str },
    /// Record a failed refresh with an error message.
    RefreshError {
        now: &'a str,
        error: &'a str,
        result_label: &'a str,
    },
    /// Record an HTTP 429 response with a server-provided or fallback
    /// Retry-After value. Writes `next_attempt_at = now + retry_after_secs`
    /// so future refresh attempts honor the server's cooldown hint instead
    /// of retrying on the generic polling cadence.
    RateLimited {
        now: &'a str,
        next_attempt_at: &'a str,
        error: &'a str,
    },
    /// Record that access was denied (e.g. EventKit permission denied).
    PermissionDenied,
}

/// Apply a state transition to `provider_scope_runtime_state`.
///
/// This is the ONLY production writer for this table. All callers
/// (EventKit sync, .ics subscription toggle/fetch, Linux calendar)
/// should route through this function instead of hand-writing SQL.
pub fn update_provider_scope_state(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    transition: ProviderScopeTransition<'_>,
) -> Result<(), StoreError> {
    match transition {
        ProviderScopeTransition::Toggle { enabled } => {
            let state = if enabled {
                AVAILABILITY_STATE_ENABLED
            } else {
                "disabled"
            };
            let mut stmt = conn.prepare_cached(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state) \
                 VALUES (?1, ?2, ?3, ?4) \
                 ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
                     enabled = excluded.enabled, \
                     availability_state = excluded.availability_state",
            )?;
            stmt.execute(params![
                provider_kind,
                provider_scope,
                i64::from(enabled),
                state
            ])?;
        }
        ProviderScopeTransition::RefreshSuccess { now } => {
            // `AVAILABILITY_STATE_ENABLED` constant directly into the
            // SQL, which forced a fresh prepare/parse on every refresh
            // tick. Bind it as `?4` instead so the SQL is `&'static str`
            // and `prepare_cached` reuses the planned statement across
            // every provider / EventKit / ICS-feed refresh.
            let mut stmt = conn.prepare_cached(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state, \
                      last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error, \
                      next_attempt_at) \
                 VALUES (?1, ?2, 1, ?4, ?3, ?3, 'success', NULL, NULL) \
                 ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
                     enabled = 1, \
                     availability_state = ?4, \
                     last_refresh_attempt_at = excluded.last_refresh_attempt_at, \
                     last_refresh_success_at = excluded.last_refresh_success_at, \
                     last_refresh_result = 'success', \
                     last_error = NULL, \
                     next_attempt_at = NULL",
            )?;
            stmt.execute(params![
                provider_kind,
                provider_scope,
                now,
                AVAILABILITY_STATE_ENABLED,
            ])?;
        }
        ProviderScopeTransition::RefreshError {
            now,
            error,
            result_label,
        } => {
            let mut stmt = conn.prepare_cached(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state, \
                      last_refresh_attempt_at, last_refresh_result, last_error) \
                 VALUES (?1, ?2, 1, ?3, ?4, ?3, ?5) \
                 ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
                     availability_state = excluded.availability_state, \
                     last_refresh_attempt_at = excluded.last_refresh_attempt_at, \
                     last_refresh_result = excluded.last_refresh_result, \
                     last_error = excluded.last_error",
            )?;
            stmt.execute(params![
                provider_kind,
                provider_scope,
                result_label,
                now,
                error,
            ])?;
        }
        ProviderScopeTransition::RateLimited {
            now,
            next_attempt_at,
            error,
        } => {
            // Keep `availability_state = 'enabled'` so the UI still lists
            // the feed and the eligibility gate still exposes cached
            // events — we're waiting, not disabled. `last_refresh_result`
            // gets the generic `fetch_error` label (the CHECK constraint
            // doesn't carry a rate-limit value) but `next_attempt_at`
            // does the actual gating downstream.
            //
            // `availability_state` is bound as `?6` here too (was
            // `prepare_cached` reuses the plan across rate-limited
            // retries.
            let mut stmt = conn.prepare_cached(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state, \
                      last_refresh_attempt_at, last_refresh_result, last_error, next_attempt_at) \
                 VALUES (?1, ?2, 1, ?6, ?3, 'fetch_error', ?4, ?5) \
                 ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
                     availability_state = ?6, \
                     last_refresh_attempt_at = excluded.last_refresh_attempt_at, \
                     last_refresh_result = 'fetch_error', \
                     last_error = excluded.last_error, \
                     next_attempt_at = excluded.next_attempt_at",
            )?;
            stmt.execute(params![
                provider_kind,
                provider_scope,
                now,
                error,
                next_attempt_at,
                AVAILABILITY_STATE_ENABLED,
            ])?;
        }
        ProviderScopeTransition::PermissionDenied => {
            let mut stmt = conn.prepare_cached(
                "INSERT INTO provider_scope_runtime_state \
                     (provider_kind, provider_scope, enabled, availability_state, last_refresh_result) \
                 VALUES (?1, ?2, 1, ?3, ?3) \
                 ON CONFLICT(provider_kind, provider_scope) DO UPDATE SET \
                     availability_state = ?3, \
                     last_refresh_result = ?3",
            )?;
            stmt.execute(params![
                provider_kind,
                provider_scope,
                AVAILABILITY_STATE_PERMISSION_DENIED,
            ])?;
        }
    }
    Ok(())
}
