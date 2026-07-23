use super::*;

#[test]
fn allowlist_contains_every_canonical_value() {
    for value in ["accepted", "declined", "tentative", "needs-action"] {
        assert!(
            AttendeeStatus::parse_strict(value).is_some(),
            "{value} must be parseable as a canonical AttendeeStatus"
        );
    }
}

#[test]
fn allowlist_rejects_underscore_form() {
    // Closing #2953: the underscore form is NOT canonical. It must
    // be rejected everywhere so write, sync apply, and import
    // boundaries share the same RFC 5545 contract.
    assert!(AttendeeStatus::parse_strict("needs_action").is_none());
}

#[test]
fn parse_strict_rejects_underscore_form() {
    // Legacy underscore form is no longer repaired by inbound paths.
    assert_eq!(AttendeeStatus::parse_strict("needs_action"), None);
    assert_eq!(
        AttendeeStatus::parse_strict("needs-action"),
        Some(AttendeeStatus::NeedsAction)
    );
}

#[test]
fn parse_strict_rejects_unknown_values() {
    for bad in ["", "Accepted", "MAYBE", "delegated", "completed"] {
        assert_eq!(
            AttendeeStatus::parse_strict(bad),
            None,
            "{bad:?} must not normalize"
        );
    }
}

#[test]
fn from_str_returns_typed_error_for_unknown() {
    let err = AttendeeStatus::from_str("definitely-not-a-partstat").unwrap_err();
    assert!(err.to_string().contains("definitely-not-a-partstat"));
}

#[test]
fn display_lists_canonical_values_in_stable_order() {
    assert_eq!(
        attendee_status_allowlist_display(),
        "accepted, declined, tentative, needs-action"
    );
}
