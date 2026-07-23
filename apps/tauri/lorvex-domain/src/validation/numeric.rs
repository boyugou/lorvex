//! Numeric-range validators (priority, estimated_minutes, mood,
//! reminder window).

use super::error::ValidationError;
use super::limits::{
    MAX_ESTIMATED_MINUTES, MAX_REMINDER_WINDOW_SECONDS, MOOD_MAX, MOOD_MIN, PRIORITY_MAX,
    PRIORITY_MIN,
};

/// collapse the near-identical i64+inclusive-range
/// validators (priority, estimated_minutes, mood,
/// reminder_window) onto one helper. Each call site rebuilt
/// the same `if !(min..=max).contains(&v) { Err(OutOfRange { … }) }`
/// skeleton; lifting the predicate keeps a single shape so a future
/// numeric range gets one line at the call site instead of a 10-line
/// copy-paste that drifts on field-name typos.
fn check_range(
    field: &'static str,
    min: i64,
    max: i64,
    actual: i64,
) -> Result<(), ValidationError> {
    if !(min..=max).contains(&actual) {
        return Err(ValidationError::OutOfRange {
            field,
            min,
            max,
            actual,
        });
    }
    Ok(())
}

/// Validate a task priority value: must be in [`PRIORITY_MIN`]..=[`PRIORITY_MAX`].
pub fn validate_priority(p: i64) -> Result<(), ValidationError> {
    check_range("priority", PRIORITY_MIN, PRIORITY_MAX, p)
}

/// Validate estimated_minutes: must be in 1..=[`MAX_ESTIMATED_MINUTES`].
///
/// zero is semantically meaningless for an *estimate* — it
/// implies "no work" rather than "unknown" (callers express "unknown" by
/// passing `None`/`NULL`, not 0). The DB column is `INTEGER NULL` and the
/// scheduler treats `Some(0)` as "scheduled but takes no time", which has
/// no real-world meaning. Reject 0 at the validation boundary.
pub fn validate_estimated_minutes(m: i64) -> Result<(), ValidationError> {
    check_range("estimated_minutes", 1, MAX_ESTIMATED_MINUTES, m)
}

/// Validate a mood or energy_level rating: must be in [`MOOD_MIN`]..=[`MOOD_MAX`].
pub fn validate_mood(value: i64) -> Result<(), ValidationError> {
    check_range("mood", MOOD_MIN, MOOD_MAX, value)
}

/// Validate a reminder window in seconds: must be in 0..=[`MAX_REMINDER_WINDOW_SECONDS`].
pub fn validate_reminder_window(seconds: i64) -> Result<(), ValidationError> {
    check_range("reminder_window", 0, MAX_REMINDER_WINDOW_SECONDS, seconds)
}
