// Re-export from the shared store module.
// Implementation consolidated in lorvex-store.

#[cfg(test)]
pub(crate) use lorvex_store::calendar_timeline::recurrence::count_end_date;

#[cfg(test)]
mod tests {
    use super::count_end_date;

    #[test]
    fn daily_count_3() {
        let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#;
        assert_eq!(
            count_end_date(rule, "2026-01-01").unwrap(),
            Some("2026-01-03".to_string())
        );
    }

    #[test]
    fn weekly_count_2() {
        let rule = r#"{"FREQ":"WEEKLY","INTERVAL":1,"COUNT":2}"#;
        assert_eq!(
            count_end_date(rule, "2026-01-06").unwrap(),
            Some("2026-01-13".to_string())
        );
    }

    #[test]
    fn no_count_returns_none() {
        let rule = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
        assert_eq!(count_end_date(rule, "2026-01-01").unwrap(), None);
    }

    #[test]
    fn count_1_returns_base() {
        let rule = r#"{"FREQ":"MONTHLY","INTERVAL":1,"COUNT":1}"#;
        assert_eq!(
            count_end_date(rule, "2026-03-15").unwrap(),
            Some("2026-03-15".to_string())
        );
    }

    #[test]
    fn yearly_count_3_from_leap_day_clamps_correctly() {
        let rule = r#"{"FREQ":"YEARLY","INTERVAL":1,"COUNT":3}"#;
        assert_eq!(
            count_end_date(rule, "2024-02-29").unwrap(),
            Some("2026-02-28".to_string())
        );
    }
}
