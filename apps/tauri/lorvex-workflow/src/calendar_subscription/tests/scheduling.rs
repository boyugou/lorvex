//! Pure rate-limit cooldown math for the per-subscription backoff
//! schedule. DB-side backoff bookkeeping
//! (`record_subscription_failure`, `clear_subscription_next_retry`,
//! `record_subscription_success`) is exercised end-to-end through the
//! Tauri-surface mutation flow in `app/src-tauri`'s
//! `calendar_subscription_sync::tests::scheduling_db` because the
//! production code path mints an HLC stamp inside
//! `add_calendar_subscription_with_conn`. The pure math below has no
//! such surface dependency.

use crate::calendar_subscription::rate_limit_cooldown_until;

#[test]
fn rate_limit_cooldown_adds_retry_after_seconds_to_now() {
    // Standard case: server says "retry in 3600 seconds"; the
    // returned timestamp must land exactly 3600s past `now`.
    let next = rate_limit_cooldown_until("2026-04-18T09:00:00.000Z", 3_600);
    assert_eq!(next, "2026-04-18T10:00:00.000Z");
}

#[test]
fn rate_limit_cooldown_clamps_hostile_retry_after_values() {
    // a feed that reports `Retry-After: 999999999` must not
    // permanently wedge a subscription — clamp to the 24h ceiling so a
    // persistent issue still gets a fresh probe the next day.
    let next = rate_limit_cooldown_until("2026-04-18T09:00:00.000Z", 999_999_999);
    assert_eq!(next, "2026-04-19T09:00:00.000Z");
}

#[test]
fn rate_limit_cooldown_accepts_zero_seconds() {
    // a zero hint means "retry immediately" — the returned timestamp
    // is exactly `now`, not skewed by a phantom floor.
    let next = rate_limit_cooldown_until("2026-04-18T09:00:00.000Z", 0);
    assert_eq!(next, "2026-04-18T09:00:00.000Z");
}
