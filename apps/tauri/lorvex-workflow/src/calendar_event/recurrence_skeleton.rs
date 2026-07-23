//! EXDATE skeleton-preserve comparator.
//!
//! [`recurrence_skeleton_matches`] is the policy
//! [`super::update::UpdateCalendarEventMutation`] consults to decide
//! whether a recurrence patch keeps the stored exception list. Two
//! canonical recurrence-rule JSON blobs share the same skeleton (and
//! therefore name the same instance grid) iff they agree on every
//! scalar bound (`FREQ`, `INTERVAL`, `WKST`) and every BY-array
//! (`BYDAY`, `BYMONTHDAY`, `BYMONTH`, `BYSETPOS`, `BYHOUR`,
//! `BYMINUTE`, `BYSECOND`) treated as a set.

use serde_json::Value;

/// Recurrence-skeleton comparator used by the EXDATE preserve
/// policy. Returns `true` iff two canonical recurrence-rule JSON
/// blobs share the same instance grid — i.e. they differ at most in
/// their `UNTIL` and/or `COUNT` bounds.
///
/// EXDATE timestamps point at specific recurrence instances. If the
/// instance grid (`FREQ`, `INTERVAL`, `BYDAY`, `BYMONTHDAY`,
/// `BYMONTH`, `BYSETPOS`, `BYHOUR`, `BYMINUTE`, `BYSECOND`, `WKST`)
/// is unchanged, every surviving EXDATE still names a valid
/// instance and the user's intent to skip / reschedule those
/// occurrences carries across the patch. When the skeleton shifts,
/// EXDATE must drop because the stored timestamps may no longer
/// correspond to any instance at all.
///
/// Both inputs are expected to be canonical JSON produced by
/// [`lorvex_domain::validation::normalize_calendar_recurrence`].
/// A parse failure on either side conservatively returns `false`
/// (drop EXDATE).
///
/// # Invariant: canonical recurrence never carries `RDATE`
///
/// RDATE would name explicit extra instance timestamps on top of
/// the RRULE grid; two otherwise-identical rules differing only in
/// RDATE would compare equal here even though the explicit-date
/// instances moved, surfacing stale EXDATE entries on the new
/// grid. The skeleton comparator is safe to ignore RDATE because
/// the canonical normalizer
/// ([`lorvex_domain::validation::normalize_calendar_recurrence`]
/// → `normalize_task_recurrence`) rejects every key outside
/// `FREQ / INTERVAL / BYDAY / BYMONTH / BYMONTHDAY / BYSETPOS /
/// WKST / UNTIL / COUNT`, so an RDATE field can never reach this
/// function. If that allowlist is ever widened to admit RDATE,
/// the field must be added to the skeleton equivalence set below
pub fn recurrence_skeleton_matches(old_json: &str, new_json: &str) -> bool {
    let Ok(old) = serde_json::from_str::<Value>(old_json) else {
        return false;
    };
    let Ok(new) = serde_json::from_str::<Value>(new_json) else {
        return false;
    };
    // Scalar fields: compare values directly.
    const SCALAR_FIELDS: &[&str] = &["FREQ", "INTERVAL", "WKST"];
    for field in SCALAR_FIELDS {
        if old.get(field) != new.get(field) {
            return false;
        }
    }
    // BY*-array fields: semantically these are sets (BYDAY=[MO,TU]
    // names the same instance grid as BYDAY=[TU,MO]). Compare as
    // sorted+deduped sets so a normalizer reorder doesn't masquerade
    // as a skeleton change and wipe EXDATE. See.
    //
    // BYHOUR/BYMINUTE/BYSECOND shift the time-of-day of every
    // instance. Even when FREQ/INTERVAL/BYDAY are unchanged, a
    // BYHOUR delta moves every occurrence and any stored EXDATE
    // (which names an exact recurrence timestamp) no longer matches
    // a real instance. Include these in the skeleton so the
    // preserve-EXDATE policy drops the list on time-of-day edits.
    const ARRAY_FIELDS: &[&str] = &[
        "BYDAY",
        "BYMONTHDAY",
        "BYMONTH",
        "BYSETPOS",
        "BYHOUR",
        "BYMINUTE",
        "BYSECOND",
    ];
    for field in ARRAY_FIELDS {
        if !json_array_set_eq(old.get(field), new.get(field)) {
            return false;
        }
    }
    true
}

/// Compare two optional JSON values as sorted+deduped sets. `None`
/// and `Some(Null)` are treated as the empty set; mismatched shapes
/// (one array, one scalar) compare unequal. Scalars compare by
/// equality. The canonicalization step (sort by serialized form +
/// dedup) makes set-equivalent arrays compare equal regardless of
/// the order produced by upstream normalizers.
fn json_array_set_eq(a: Option<&Value>, b: Option<&Value>) -> bool {
    fn canonical(v: Option<&Value>) -> Vec<String> {
        match v {
            None | Some(Value::Null) => Vec::new(),
            Some(Value::Array(items)) => {
                let mut serialized: Vec<String> = items.iter().map(|x| x.to_string()).collect();
                serialized.sort();
                serialized.dedup();
                serialized
            }
            Some(other) => vec![other.to_string()],
        }
    }
    canonical(a) == canonical(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skeleton_matches_when_only_until_differs() {
        let a = r#"{"FREQ":"WEEKLY","INTERVAL":1,"UNTIL":"2026-06-01"}"#;
        let b = r#"{"FREQ":"WEEKLY","INTERVAL":1,"UNTIL":"2027-01-01"}"#;
        assert!(recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_differs_when_byday_changes() {
        let a = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"]}"#;
        let b = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["TU"]}"#;
        assert!(!recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_invalid_json_drops_exdate() {
        assert!(!recurrence_skeleton_matches("not json", "not json"));
    }

    /// : a BYHOUR shift moves every instance of the recurrence
    /// to a new time-of-day; any preserved EXDATE would dangle. The
    /// skeleton comparator must report the rules as differing so the
    /// caller drops EXDATE.
    #[test]
    fn skeleton_differs_when_byhour_changes() {
        let a = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYHOUR":[9]}"#;
        let b = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYHOUR":[10]}"#;
        assert!(!recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_differs_when_byminute_changes() {
        let a = r#"{"FREQ":"DAILY","INTERVAL":1,"BYMINUTE":[0]}"#;
        let b = r#"{"FREQ":"DAILY","INTERVAL":1,"BYMINUTE":[30]}"#;
        assert!(!recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_differs_when_bysecond_changes() {
        let a = r#"{"FREQ":"DAILY","INTERVAL":1,"BYSECOND":[0]}"#;
        let b = r#"{"FREQ":"DAILY","INTERVAL":1,"BYSECOND":[15]}"#;
        assert!(!recurrence_skeleton_matches(a, b));
    }

    /// : BY-array order is not semantically significant — two
    /// rules whose BY-fields differ only in element order name the
    /// same instance grid, so EXDATE must survive.
    #[test]
    fn skeleton_matches_when_byday_reordered() {
        let a = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","TU","WE"]}"#;
        let b = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["WE","MO","TU"]}"#;
        assert!(recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_matches_when_bymonth_reordered_and_deduped() {
        let a = r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[1,3,6,6]}"#;
        let b = r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[6,3,1]}"#;
        assert!(recurrence_skeleton_matches(a, b));
    }

    #[test]
    fn skeleton_matches_when_byhour_reordered() {
        let a = r#"{"FREQ":"DAILY","INTERVAL":1,"BYHOUR":[9,17]}"#;
        let b = r#"{"FREQ":"DAILY","INTERVAL":1,"BYHOUR":[17,9]}"#;
        assert!(recurrence_skeleton_matches(a, b));
    }

    ///  F11: the skeleton comparator's RDATE-blindness is
    /// safe only because the canonical normalizer rejects RDATE
    /// (and every other key outside the published allowlist). Lock
    /// that invariant in here so widening the normalizer key set
    /// without revisiting this comparator fails loudly.
    #[test]
    fn canonical_normalizer_rejects_rdate_so_skeleton_can_ignore_it() {
        let err = lorvex_domain::validation::normalize_calendar_recurrence(Some(
            r#"{"FREQ":"WEEKLY","INTERVAL":1,"RDATE":["2026-05-04"]}"#,
        ))
        .expect_err("RDATE must be rejected by the canonical normalizer");
        let message = err.to_string();
        assert!(
            message.contains("RDATE") || message.to_lowercase().contains("unknown"),
            "error should mention RDATE / unknown key: {message}",
        );
    }

    #[test]
    fn skeleton_still_differs_when_byday_actually_changes() {
        let a = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","TU"]}"#;
        let b = r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#;
        assert!(!recurrence_skeleton_matches(a, b));
    }
}
