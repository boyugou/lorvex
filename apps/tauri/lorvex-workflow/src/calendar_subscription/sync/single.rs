//! Per-subscription orchestrator: load metadata, honor the 429
//! cooldown, fetch the `.ics` body through the surface-supplied
//! [`FetchBackend`], classify [`FetchedIcsError`] into the
//! rate-limited / truncated / other branches, and hand the parsed
//! body off to [`sync_subscription_content`] for the diff-apply.
//!
//! Sibling of [`super::content`] and [`super::truncation_reject`] so
//! the orchestrator's branch points are readable top-to-bottom
//! without the per-row apply or the truncation-rejection bookkeeping
//! interleaved inline.

use rusqlite::params;

use lorvex_domain::sync_timestamp_now;
use lorvex_domain::time::SyncTimestamp;
use lorvex_store::repositories::provider_repo::{self, ProviderScopeTransition};
use lorvex_store::with_immediate_transaction;

use super::super::error::CalendarSubscriptionError;
use super::super::scheduling::{
    rate_limit_cooldown_until, record_subscription_failure, DEFAULT_RATE_LIMIT_COOLDOWN_SECS,
};
use super::super::tzid::UnknownTzidSink;
use super::content::sync_subscription_content;
use super::truncation_reject::record_ics_truncation_rejection;
use super::types::{FetchBackend, FetchedIcsError, SubscriptionSyncResult};

/// user-facing "Retry now" — clear the backoff gate for a
/// single subscription and run a fresh sync immediately. Distinct
/// from [`sync_calendar_subscription`] (which ignores the scheduler
/// gate but still walks the provider_scope_runtime_state 429
/// cooldown): "Retry now" is explicit user intent — they want the
/// feed probed right now regardless of the backoff schedule, and
/// any failure resets the exponential clock from 1 minute rather
/// than continuing from where it was.
pub fn retry_calendar_subscription_now(
    conn: &rusqlite::Connection,
    backend: &dyn FetchBackend,
    unknown_tzid_sink: UnknownTzidSink<'_>,
    id: &str,
) -> Result<SubscriptionSyncResult, CalendarSubscriptionError> {
    super::super::scheduling::clear_subscription_next_retry(conn, id)?;
    sync_calendar_subscription(conn, backend, unknown_tzid_sink, id)
}

/// Refresh one subscription end-to-end: load metadata, honor the
/// 429 cooldown, fetch the body through `backend`, then call
/// [`sync_subscription_content`] to apply the diff inside a single
/// transaction.
pub fn sync_calendar_subscription(
    conn: &rusqlite::Connection,
    backend: &dyn FetchBackend,
    unknown_tzid_sink: UnknownTzidSink<'_>,
    id: &str,
) -> Result<SubscriptionSyncResult, CalendarSubscriptionError> {
    let (name, url, sub_color): (String, String, Option<String>) = conn
        .query_row(
            "SELECT name, url, color FROM calendar_subscriptions WHERE id = ?1 AND enabled = 1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|e| {
            CalendarSubscriptionError::Validation(format!(
                "Subscription not found or disabled: {e}"
            ))
        })?;

    // honor server-provided Retry-After cooldown across the
    // `online` event + 60-min poll. If a prior fetch hit HTTP 429 and
    // wrote `next_attempt_at`, skip this cycle silently. The
    // comparison runs through `SyncTimestamp` so mixed-precision peers
    // (3 vs 6 fractional digits) cannot misorder under a raw lex
    // compare.
    let now = sync_timestamp_now();
    let cooldown =
        provider_repo::get_provider_scope_next_attempt_at(conn, "ical_subscription", id)?;
    if let Some(next_attempt_at) = cooldown {
        let now_typed = SyncTimestamp::parse(&now).ok_or_else(|| {
            CalendarSubscriptionError::Internal(format!(
                "sync_timestamp_now produced a non-canonical value: {now:?}"
            ))
        })?;
        let next_attempt_at_typed = SyncTimestamp::parse(&next_attempt_at).ok_or_else(|| {
            CalendarSubscriptionError::Internal(format!(
                "calendar subscription cooldown 'next_attempt_at' is not a canonical sync timestamp: {next_attempt_at:?}"
            ))
        })?;
        if now_typed < next_attempt_at_typed {
            return Ok(SubscriptionSyncResult {
                subscription_id: id.to_string(),
                subscription_name: name,
                events_imported: 0,
                events_updated: 0,
                events_removed: 0,
                error: Some(format!(
                    "Calendar feed is rate-limited; next attempt at {next_attempt_at}"
                )),
            });
        }
    }

    // Fetch with NO writer-lock context — backends own their own
    // transport setup and timeouts.
    let fetched = match backend.fetch_ics(&url, None) {
        Ok(fetched) => fetched,
        Err(FetchedIcsError::RateLimited {
            retry_after_secs,
            safe_url,
        }) => {
            let secs = retry_after_secs.unwrap_or(DEFAULT_RATE_LIMIT_COOLDOWN_SECS);
            let message = match retry_after_secs {
                Some(s) => format!(
                    "Calendar feed is rate-limited (HTTP 429). Retry after {s}s: {safe_url}"
                ),
                None => {
                    format!("Calendar feed is rate-limited (HTTP 429). Retry later: {safe_url}")
                }
            };
            let next_attempt_at = rate_limit_cooldown_until(&now, secs);
            // Wrap the provider-scope state update + the
            // per-subscription backoff bump in a single immediate
            // transaction. Without the boundary the two writes ran on
            // autocommit; a power failure or kill between them left
            // the feed flagged RateLimited with stale backoff state,
            // which the scheduler interpreted as "permanently
            // rate-limited".
            return with_immediate_transaction::<_, CalendarSubscriptionError>(conn, |conn| {
                provider_repo::update_provider_scope_state(
                    conn,
                    "ical_subscription",
                    id,
                    ProviderScopeTransition::RateLimited {
                        now: &now,
                        next_attempt_at: &next_attempt_at,
                        error: &message,
                    },
                )?;
                // advance per-subscription backoff and persist the
                // server's Retry-After hint as a hard floor so the
                // scheduler's next eligibility check respects the longer
                // of (schedule step, server hint).
                record_subscription_failure(conn, id, &now, retry_after_secs)?;
                Ok(SubscriptionSyncResult {
                    subscription_id: id.to_string(),
                    subscription_name: name.clone(),
                    events_imported: 0,
                    events_updated: 0,
                    events_removed: 0,
                    error: Some(message.clone()),
                })
            });
        }
        Err(FetchedIcsError::Truncated { reason, safe_url }) => {
            // a truncated response looks like an iCalendar prefix
            // but is missing its terminator (or has an unbalanced
            // VEVENT). We intentionally do NOT call
            // `parse_ics_events` or the diff-delete pass — the
            // cached events from the last successful poll stay
            // intact, and the scheduler retries on the next cycle.
            // The dedicated `sync.ics.truncated` label on the
            // `error_logs` row lets diagnostics distinguish this
            // transient condition from a generic fetch failure, and
            // keeps the feed's `last_error` informative.
            //
            // Wrap the backoff bump + the diagnostic persistence in a
            // single immediate transaction so a crash between writes
            // cannot leave the feed half-flagged.
            return with_immediate_transaction::<_, CalendarSubscriptionError>(conn, |conn| {
                record_subscription_failure(conn, id, &now, None)?;
                record_ics_truncation_rejection(conn, id, &name, &now, reason, &safe_url)
            });
        }
        Err(FetchedIcsError::Other(message)) => {
            // Atomic provider-scope state update + backoff bump so a
            // crash between the two writes never leaves the feed
            // flagged with stale backoff.
            return with_immediate_transaction::<_, CalendarSubscriptionError>(conn, |conn| {
                provider_repo::update_provider_scope_state(
                    conn,
                    "ical_subscription",
                    id,
                    ProviderScopeTransition::RefreshError {
                        now: &now,
                        error: &message,
                        result_label: "fetch_error",
                    },
                )?;
                record_subscription_failure(conn, id, &now, None)?;
                Ok(SubscriptionSyncResult {
                    subscription_id: id.to_string(),
                    subscription_name: name.clone(),
                    events_imported: 0,
                    events_updated: 0,
                    events_removed: 0,
                    error: Some(message.clone()),
                })
            });
        }
    };

    sync_subscription_content(
        conn,
        id,
        &name,
        &fetched.body,
        sub_color.as_deref(),
        unknown_tzid_sink,
    )
}
