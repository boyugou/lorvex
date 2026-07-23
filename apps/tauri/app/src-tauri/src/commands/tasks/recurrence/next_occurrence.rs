#[cfg(test)]
mod tests {
    fn calculate_next_occurrence(recurrence_json: &str, base_date_str: &str) -> Option<String> {
        lorvex_store::calendar_timeline::recurrence::calculate_next_occurrence_date(
            recurrence_json,
            base_date_str,
        )
        .expect("recurrence rule should parse")
    }

    #[test]
    fn yearly_recurrence_clamps_leap_day_to_feb_28() {
        let result = calculate_next_occurrence(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2024-02-29");
        assert_eq!(result.as_deref(), Some("2025-02-28"));
    }

    #[test]
    fn yearly_recurrence_preserves_leap_day_in_leap_year() {
        let result = calculate_next_occurrence(r#"{"FREQ":"YEARLY","INTERVAL":4}"#, "2024-02-29");
        assert_eq!(result.as_deref(), Some("2028-02-29"));
    }

    #[test]
    fn yearly_recurrence_normal_date() {
        let result = calculate_next_occurrence(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2026-03-15");
        assert_eq!(result.as_deref(), Some("2027-03-15"));
    }

    #[test]
    fn monthly_recurrence_bymonthday_31_skips_feb() {
        // RFC 5545 §3.3.10: explicit BYMONTHDAY=31 skips February
        // (no 31st) rather than clamping — next after Jan 31 is Mar 31.
        let result = calculate_next_occurrence(
            r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#,
            "2026-01-31",
        );
        assert_eq!(result.as_deref(), Some("2026-03-31"));
    }

    #[test]
    fn daily_recurrence_basic() {
        let result = calculate_next_occurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-15");
        assert_eq!(result.as_deref(), Some("2026-03-16"));
    }

    #[test]
    fn weekly_recurrence_basic() {
        let result = calculate_next_occurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#, "2026-03-15");
        assert_eq!(result.as_deref(), Some("2026-03-22"));
    }

    #[test]
    fn until_date_prevents_next_occurrence() {
        let result = calculate_next_occurrence(
            r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-15"}"#,
            "2026-03-15",
        );
        assert_eq!(result, None);
    }

    #[test]
    fn monthly_bymonthday_31_lands_on_next_month_with_31_days() {
        // From Feb 28 the next BYMONTHDAY=31 occurrence is Mar 31.
        let result = calculate_next_occurrence(
            r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#,
            "2026-02-28",
        );
        assert_eq!(result.as_deref(), Some("2026-03-31"));
    }

    #[test]
    fn yearly_bymonthday_29_skips_to_next_leap_year() {
        // Explicit BYMONTHDAY=29 (no BYMONTH) skips non-leap Februaries —
        // from Feb 28 2025 the next Feb-29 is leap year 2028.
        let result = calculate_next_occurrence(
            r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTHDAY":29}"#,
            "2025-02-28",
        );
        assert_eq!(result.as_deref(), Some("2028-02-29"));
    }
}
