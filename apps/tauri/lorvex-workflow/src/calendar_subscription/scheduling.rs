//! Calendar subscription cooldown helpers.
//!
//! `rate_limit_cooldown_until` is the retained primitive: clamp
//! `retry_after_secs` at [`MAX_RATE_LIMIT_COOLDOWN_SECS`] and add it
//! to `now`, returning a canonical RFC3339 millisecond `Z` string lex-comparable against
//! every other timestamp column.

use super::error::CalendarSubscriptionError;

/// Default cooldown applied when a 429 response omits (or mis-formats)
/// the `Retry-After` header. Chosen to match
/// `SUBSCRIPTION_SYNC_MIN_GAP_MS` on the frontend — if the server won't
/// tell us when to come back, wait one full poll cycle before trying.
pub const DEFAULT_RATE_LIMIT_COOLDOWN_SECS: u64 = 60 * 60;

/// Upper bound on honored Retry-After values. A hostile or misconfigured
/// feed that responds with `Retry-After: 999999999` should not permanently
/// wedge a subscription. 24h is longer than any reasonable rate-limit
/// window but short enough that a genuinely persistent issue gets a fresh
/// probe the next day instead of being invisibly frozen forever.
pub const MAX_RATE_LIMIT_COOLDOWN_SECS: u64 = 24 * 60 * 60;

/// Compute `next_attempt_at` = `now + clamp(retry_after_secs)`. Returns
/// a canonical RFC3339 millisecond-Z string matching the precision used by
/// the local timestamp columns — lex-comparable against `now()`.
pub fn rate_limit_cooldown_until(now: &str, retry_after_secs: u64) -> String {
    let clamped = retry_after_secs.min(MAX_RATE_LIMIT_COOLDOWN_SECS);
    let parsed = chrono::DateTime::parse_from_rfc3339(now)
        .map_or_else(|_| chrono::Utc::now(), |dt| dt.with_timezone(&chrono::Utc));
    lorvex_domain::format_sync_timestamp(parsed + chrono::Duration::seconds(clamped as i64))
}

/// Compatibility no-op for the old per-subscription backoff columns.
pub fn record_subscription_failure(
    _conn: &rusqlite::Connection,
    _id: &str,
    _now: &str,
    _retry_after_secs: Option<u64>,
) -> Result<(), CalendarSubscriptionError> {
    Ok(())
}

/// Compatibility no-op for the old per-subscription backoff columns.
pub fn record_subscription_success(
    _conn: &rusqlite::Connection,
    _id: &str,
) -> Result<(), CalendarSubscriptionError> {
    Ok(())
}

/// Compatibility no-op for the old per-subscription backoff columns.
pub fn clear_subscription_next_retry(
    _conn: &rusqlite::Connection,
    _id: &str,
) -> Result<(), CalendarSubscriptionError> {
    Ok(())
}
