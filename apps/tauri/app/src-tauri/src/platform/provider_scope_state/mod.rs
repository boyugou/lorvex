use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use lorvex_store::repositories::provider_repo::{self, ProviderScopeTransition};
use rusqlite::Connection;

fn apply_provider_scope_transition(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    transition: ProviderScopeTransition<'_>,
) -> AppResult<()> {
    provider_repo::update_provider_scope_state(conn, provider_kind, provider_scope, transition)
        .map_err(AppError::from)
}

pub(crate) fn record_refresh_success(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    now: &str,
) -> AppResult<()> {
    apply_provider_scope_transition(
        conn,
        provider_kind,
        provider_scope,
        ProviderScopeTransition::RefreshSuccess { now },
    )
}

pub(crate) fn record_refresh_error(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
    now: &str,
    error: &str,
    result_label: &str,
) -> AppResult<()> {
    apply_provider_scope_transition(
        conn,
        provider_kind,
        provider_scope,
        ProviderScopeTransition::RefreshError {
            now,
            error,
            result_label,
        },
    )
}

#[cfg(target_os = "windows")]
fn record_permission_denied_with_conn(
    conn: &Connection,
    provider_kind: &str,
    provider_scope: &str,
) -> AppResult<()> {
    apply_provider_scope_transition(
        conn,
        provider_kind,
        provider_scope,
        ProviderScopeTransition::PermissionDenied,
    )
}

#[cfg(target_os = "windows")]
pub(crate) fn record_permission_denied(provider_kind: &str, provider_scope: &str) -> AppResult<()> {
    let conn = get_conn()?;
    record_permission_denied_with_conn(&conn, provider_kind, provider_scope)
}

#[cfg(test)]
mod tests;
