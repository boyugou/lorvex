//! Provider mirror repository — shared CRUD and resolution logic for
//! `provider_calendar_events` and `task_provider_event_links` tables.
//!
//! These tables are device-local (never synced). Both the Tauri app and the MCP
//! server delegate to these functions instead of embedding their own SQL.

use lorvex_domain::naming::{
    AVAILABILITY_STATE_AUTHORIZATION_ERROR, AVAILABILITY_STATE_ENABLED,
    AVAILABILITY_STATE_FETCH_ERROR, AVAILABILITY_STATE_PARSE_ERROR,
    AVAILABILITY_STATE_PERMISSION_DENIED,
};
use lorvex_domain::time::{Date, SyncTimestamp, TimeOfDay};
use serde::{Deserialize, Serialize};

mod events;
mod links;
mod scope_state;

pub use events::{
    clear_provider_events_by_kind, clear_provider_events_by_scope, delete_provider_event,
    get_provider_event_keys, upsert_provider_event, ProviderEventData, ProviderEventUpsertOutcome,
};
pub use links::{
    delete_provider_event_link, get_provider_event_link, get_resolved_provider_links_for_task,
    upsert_provider_event_link,
};
pub use scope_state::{
    get_provider_scope_next_attempt_at, is_provider_scope_queryable, update_provider_scope_state,
    ProviderScopeTransition,
};

pub(super) fn is_provider_error_label(label: Option<&str>) -> bool {
    matches!(
        label,
        Some(value)
            if value == AVAILABILITY_STATE_PERMISSION_DENIED
                || value == AVAILABILITY_STATE_AUTHORIZATION_ERROR
                || value == AVAILABILITY_STATE_FETCH_ERROR
                || value == AVAILABILITY_STATE_PARSE_ERROR
    )
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A row from `task_provider_event_links`.
///
/// `created_at` / `updated_at` are typed
/// `SyncTimestamp` instead of bare `String`. Wire format is unchanged
/// — `SyncTimestamp` serializes as the same canonical RFC 3339
/// millisecond-precision `Z` string the column was always written as,
/// so JSON / sync envelopes / SQLite columns stay byte-identical.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskProviderEventLink {
    pub task_id: String,
    pub provider_kind: String,
    pub provider_scope: String,
    pub provider_event_key: String,
    pub created_at: SyncTimestamp,
    pub updated_at: SyncTimestamp,
}

#[derive(Debug, Clone)]
pub struct ProviderEventLinkDeleteResult {
    pub deleted: bool,
    pub before: Option<TaskProviderEventLink>,
    pub remaining_links: Vec<TaskProviderEventLink>,
}

/// A provider link joined against the `provider_calendar_events` cache, with a
/// runtime-computed `resolution_state`:
///   - `"resolved"` — provider event exists in local cache
///   - `"pending"` — provider is enabled but has never completed a refresh
///   - `"stale"` — provider has refreshed before, but the cache is too old to
///     trust an absent event as a deletion
///   - `"unavailable"` — provider is disabled, unconfigured, or currently failing
///   - `"missing"` — provider is active and freshly refreshed, but the event is absent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderEventLinkWithResolution {
    pub task_id: String,
    pub provider_kind: String,
    pub provider_scope: String,
    pub provider_event_key: String,
    pub created_at: SyncTimestamp,
    pub updated_at: SyncTimestamp,
    pub event_title: Option<String>,
    pub event_start_date: Option<Date>,
    pub event_start_time: Option<TimeOfDay>,
    pub resolution_state: String,
}

// ---------------------------------------------------------------------------
// Row mappers
// ---------------------------------------------------------------------------

pub(super) fn link_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskProviderEventLink> {
    Ok(TaskProviderEventLink {
        task_id: row.get(0)?,
        provider_kind: row.get(1)?,
        provider_scope: row.get(2)?,
        provider_event_key: row.get(3)?,
        created_at: row.get(4)?,
        updated_at: row.get(5)?,
    })
}

/// Map a row from the 3-way JOIN query (links + events + runtime state) into
/// a `ProviderEventLinkWithResolution` with computed `resolution_state`.
///
/// Column layout: 0-5 = link cols, 6-8 = event cols, 9 = has_event bool,
/// 10 = availability_state, 11 = last_refresh_success_at,
/// 12 = last_refresh_result, 13 = has_runtime_state,
/// 14 = ical_subscription_enabled, 15 = scope_stale.
pub(super) fn resolved_link_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<ProviderEventLinkWithResolution> {
    let provider_kind: String = row.get(1)?;
    let has_event: bool = row.get(9)?;
    let availability_state: Option<String> = row.get(10)?;
    let last_refresh_success_at: Option<String> = row.get(11)?;
    let last_refresh_result: Option<String> = row.get(12)?;
    let has_runtime_state: bool = row.get(13)?;
    let ical_subscription_enabled: Option<bool> = row.get(14)?;
    let scope_stale: bool = row.get(15)?;

    let scope_configured_enabled = if provider_kind == "ical_subscription" {
        ical_subscription_enabled.unwrap_or(false)
    } else {
        has_runtime_state
    };
    let scope_available = availability_state.as_deref() == Some(AVAILABILITY_STATE_ENABLED);
    let scope_failing = is_provider_error_label(availability_state.as_deref())
        || is_provider_error_label(last_refresh_result.as_deref());

    let resolution_state = if has_event {
        "resolved"
    } else if !scope_configured_enabled {
        "unavailable"
    } else if !has_runtime_state {
        "pending"
    } else if !scope_available || scope_failing {
        "unavailable"
    } else if last_refresh_success_at.is_none() {
        "pending"
    } else if scope_stale {
        "stale"
    } else {
        "missing"
    };

    Ok(ProviderEventLinkWithResolution {
        task_id: row.get(0)?,
        provider_kind,
        provider_scope: row.get(2)?,
        provider_event_key: row.get(3)?,
        created_at: row.get(4)?,
        updated_at: row.get(5)?,
        event_title: row.get(6)?,
        event_start_date: row.get(7)?,
        event_start_time: row.get(8)?,
        resolution_state: resolution_state.to_string(),
    })
}

pub(super) const SELECT_COLS: &str =
    "task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at";

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
