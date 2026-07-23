use super::super::*;

#[test]
fn priority_valid_range() {
    for p in PRIORITY_MIN..=PRIORITY_MAX {
        assert!(validate_priority(p).is_ok(), "priority {p} should be valid");
    }
}

#[test]
fn priority_too_low() {
    assert_eq!(
        validate_priority(0),
        Err(ValidationError::OutOfRange {
            field: "priority",
            min: PRIORITY_MIN,
            max: PRIORITY_MAX,
            actual: 0,
        })
    );
}

#[test]
fn priority_too_high() {
    assert_eq!(
        validate_priority(5),
        Err(ValidationError::OutOfRange {
            field: "priority",
            min: PRIORITY_MIN,
            max: PRIORITY_MAX,
            actual: 5,
        })
    );
}

#[test]
fn priority_negative() {
    assert!(validate_priority(-1).is_err());
}

// -- validate_estimated_minutes ------------------------------------

#[test]
fn estimated_minutes_valid() {
    assert!(validate_estimated_minutes(60).is_ok());
}

/// zero is now rejected — "no work" is not a meaningful
/// estimate. Callers express "unknown" by passing `None`/`NULL`, never 0.
#[test]
fn estimated_minutes_zero_is_rejected() {
    assert!(validate_estimated_minutes(0).is_err());
}

#[test]
fn estimated_minutes_one_is_minimum() {
    assert!(validate_estimated_minutes(1).is_ok());
}

#[test]
fn estimated_minutes_max() {
    assert!(validate_estimated_minutes(MAX_ESTIMATED_MINUTES).is_ok());
}

#[test]
fn estimated_minutes_negative() {
    assert!(validate_estimated_minutes(-1).is_err());
}

#[test]
fn estimated_minutes_over_max() {
    assert!(validate_estimated_minutes(MAX_ESTIMATED_MINUTES + 1).is_err());
}

// -- validate_mood -------------------------------------------------

#[test]
fn mood_valid_range() {
    for v in MOOD_MIN..=MOOD_MAX {
        assert!(validate_mood(v).is_ok(), "mood {v} should be valid");
    }
}

#[test]
fn mood_too_low() {
    assert!(validate_mood(0).is_err());
}

#[test]
fn mood_too_high() {
    assert!(validate_mood(6).is_err());
}

// -- validate_reminder_window --------------------------------------

#[test]
fn reminder_window_valid() {
    assert!(validate_reminder_window(3600).is_ok());
}

#[test]
fn reminder_window_zero() {
    assert!(validate_reminder_window(0).is_ok());
}

#[test]
fn reminder_window_max() {
    assert!(validate_reminder_window(MAX_REMINDER_WINDOW_SECONDS).is_ok());
}

#[test]
fn reminder_window_negative() {
    assert!(validate_reminder_window(-1).is_err());
}

#[test]
fn reminder_window_over_max() {
    assert!(validate_reminder_window(MAX_REMINDER_WINDOW_SECONDS + 1).is_err());
}
