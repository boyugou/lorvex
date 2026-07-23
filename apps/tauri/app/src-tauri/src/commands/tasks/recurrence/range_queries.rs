// Thin wrappers preserving Tauri-side function names.
// Implementation delegated to lorvex-store's consolidated recurrence module.

#[cfg(test)]
pub(crate) use lorvex_store::calendar_timeline::recurrence::overlaps_calendar_range;

#[cfg(test)]
mod tests {
    use super::*;

    fn first_recurrence_on_or_after(
        recurrence_json: &str,
        base: chrono::NaiveDate,
        target: chrono::NaiveDate,
    ) -> Option<chrono::NaiveDate> {
        lorvex_store::calendar_timeline::recurrence::first_occurrence_on_or_after(
            recurrence_json,
            base,
            target,
        )
        .expect("recurrence rule should parse")
    }

    #[test]
    fn yearly_first_occurrence_clamps_leap_day() {
        let base = chrono::NaiveDate::from_ymd_opt(2024, 2, 29).unwrap();
        let target = chrono::NaiveDate::from_ymd_opt(2025, 1, 1).unwrap();
        let result =
            first_recurrence_on_or_after(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, base, target);
        assert_eq!(
            result,
            Some(chrono::NaiveDate::from_ymd_opt(2025, 2, 28).unwrap()),
            "Yearly recurrence from Feb 29 must clamp to Feb 28 in 2025"
        );
    }

    #[test]
    fn yearly_first_occurrence_preserves_leap_day() {
        let base = chrono::NaiveDate::from_ymd_opt(2024, 2, 29).unwrap();
        let target = chrono::NaiveDate::from_ymd_opt(2028, 1, 1).unwrap();
        let result =
            first_recurrence_on_or_after(r#"{"FREQ":"YEARLY","INTERVAL":4}"#, base, target);
        assert_eq!(
            result,
            Some(chrono::NaiveDate::from_ymd_opt(2028, 2, 29).unwrap()),
            "Yearly recurrence with interval 4 should land on Feb 29 in leap year"
        );
    }

    #[test]
    fn overlaps_range_basic() {
        let from = chrono::NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
        let to = chrono::NaiveDate::from_ymd_opt(2026, 3, 31).unwrap();
        assert!(overlaps_calendar_range(from, to, from, to));
        assert!(!overlaps_calendar_range(
            chrono::NaiveDate::from_ymd_opt(2026, 4, 1).unwrap(),
            chrono::NaiveDate::from_ymd_opt(2026, 4, 30).unwrap(),
            from,
            to,
        ));
    }
}
