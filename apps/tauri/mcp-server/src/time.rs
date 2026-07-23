// Re-export time utilities from lorvex-domain.
// The canonical implementations now live in the shared crate.
//
// the bare `local_today_ymd` /
// `local_date_plus_days_ymd` helpers in `lorvex-domain` are gone.
// They silently used `chrono::Local` (the host-machine zone)
// regardless of the user's stored timezone preference, so a user
// with `PREF_TIMEZONE = "America/Los_Angeles"` running on a UTC-set
// CI/server box saw "today" against the host clock. Every
// production caller now routes through
// `today_ymd_for_timezone_name(Utc::now(), …)` /
// `date_plus_days_ymd_for_timezone_name(Utc::now(), …)` with the
// preference passed in explicitly.
pub use lorvex_domain::time::{date_plus_days_ymd_for_timezone_name, today_ymd_for_timezone_name};

/// Test-only convenience: `today_ymd_for_timezone_name(Utc::now(),
/// None)` against the host clock. Exists so test fixtures can keep
/// reading "today" without having to plumb a timezone string into
/// every assertion. The production code path no
/// longer has a system-local fallback that ignores the user's
/// preference, but tests legitimately want "whatever today is on
/// the box that ran cargo test" — naming the helper `..._for_test`
/// keeps the rule "no production caller may forget the timezone"
/// enforceable while leaving fixtures ergonomic.
#[cfg(test)]
pub(crate) fn today_ymd_local_for_test() -> String {
    today_ymd_for_timezone_name(chrono::Utc::now(), None)
}

/// Test-only companion to [`today_ymd_local_for_test`].
#[cfg(test)]
pub(crate) fn date_plus_days_ymd_local_for_test(offset_days: i64) -> String {
    date_plus_days_ymd_for_timezone_name(chrono::Utc::now(), None, offset_days)
}
