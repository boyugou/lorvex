//! Truncation-rejection short-circuit: persist the
//! `sync.ics.truncated` diagnostic and build the
//! `SubscriptionSyncResult` for the caller without touching cached
//! provider events.
//!
//! Lives in its own sibling so the preservation contract (leave the
//! cached events untouched on a mid-stream cut-off) is straightforward
//! to exercise in tests without a real HTTP server — the rejection
//! path is enforced by *not* invoking any of the upsert / diff-delete
//! helpers from this function.

use lorvex_store::repositories::provider_repo::{self, ProviderScopeTransition};

use super::super::error::CalendarSubscriptionError;
use super::super::truncation::{IcsTruncationReason, ICS_TRUNCATION_MESSAGE};
use super::types::{SubscriptionSyncResult, ICS_TRUNCATION_LOG_SOURCE};

/// persist the "feed truncated" diagnostic and build the
/// short-circuit `SubscriptionSyncResult` for the caller. Factored
/// out of [`sync_calendar_subscription`] so the truncation-rejection
/// path is straightforward to exercise in tests without a real HTTP
/// server — the preservation contract (leave the cached provider
/// events untouched) is enforced by *not* invoking any of the
/// upsert / diff-delete helpers from this function.
pub fn record_ics_truncation_rejection(
    conn: &rusqlite::Connection,
    id: &str,
    name: &str,
    now: &str,
    reason: IcsTruncationReason,
    safe_url: &str,
) -> Result<SubscriptionSyncResult, CalendarSubscriptionError> {
    let diagnostic = format!("{ICS_TRUNCATION_MESSAGE} ({reason}): {safe_url}");

    // The provider-scope runtime state has a closed CHECK-enum on
    // `last_refresh_result` — `fetch_error` is the nearest category
    // for a transient mid-stream cut-off. The dedicated truncation
    // signal lives in the `error_logs` row below, whose `source`
    // column is free-form.
    provider_repo::update_provider_scope_state(
        conn,
        "ical_subscription",
        id,
        ProviderScopeTransition::RefreshError {
            now,
            error: &diagnostic,
            result_label: "fetch_error",
        },
    )?;

    // emit a secondary structured log so Settings → Diagnostics can
    // filter on the dedicated source. Failures to append to
    // `error_logs` must not mask the truncation itself — the caller
    // has already persisted the feed's `last_error`. `details`
    // carries the subscription id + the URL so a user who triages
    // the diagnostic can connect it to the right feed.
    let details = format!("subscription_id={id} url={safe_url} reason={reason}");
    let _ = lorvex_store::error_log::append_error_log(
        conn,
        ICS_TRUNCATION_LOG_SOURCE,
        &diagnostic,
        Some(&details),
        Some("warn"),
    );

    Ok(SubscriptionSyncResult {
        subscription_id: id.to_string(),
        subscription_name: name.to_string(),
        events_imported: 0,
        events_updated: 0,
        events_removed: 0,
        error: Some(diagnostic),
    })
}
