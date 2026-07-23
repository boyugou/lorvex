use super::*;
use chrono::NaiveDate;

#[test]
fn pagination_default_values() {
    let p = Pagination::default();
    assert_eq!(p.limit, 100);
    assert_eq!(p.offset, 0);
}

#[test]
fn today_predicate_holds_date() {
    let pred = TodayPredicate {
        date: NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
    };
    assert_eq!(pred.date.to_string(), "2026-03-23");
}

#[test]
fn upcoming_predicate_holds_range() {
    let pred = UpcomingPredicate {
        from_date: NaiveDate::from_ymd_opt(2026, 3, 23).unwrap(),
        days: 7,
    };
    assert_eq!(pred.days, 7);
}

#[test]
fn derive_open_task_lateness_distinguishes_past_planned_from_overdue_states() {
    let today = NaiveDate::from_ymd_opt(2026, 4, 4).unwrap();

    assert_eq!(
        derive_open_task_lateness(
            Some(NaiveDate::from_ymd_opt(2026, 4, 3).unwrap()),
            Some(NaiveDate::from_ymd_opt(2026, 4, 7).unwrap()),
            today,
        ),
        Some(TaskLateness::PastPlanned)
    );
    assert_eq!(
        derive_open_task_lateness(
            None,
            Some(NaiveDate::from_ymd_opt(2026, 4, 3).unwrap()),
            today
        ),
        Some(TaskLateness::OverdueUnhandled)
    );
    assert_eq!(
        derive_open_task_lateness(
            Some(NaiveDate::from_ymd_opt(2026, 4, 4).unwrap()),
            Some(NaiveDate::from_ymd_opt(2026, 4, 3).unwrap()),
            today,
        ),
        Some(TaskLateness::OverdueAcknowledged)
    );
    assert_eq!(
        derive_open_task_lateness(
            Some(NaiveDate::from_ymd_opt(2026, 4, 5).unwrap()),
            Some(NaiveDate::from_ymd_opt(2026, 4, 3).unwrap()),
            today,
        ),
        Some(TaskLateness::OverdueAcknowledged)
    );
}

#[test]
fn search_predicate_optional_filters() {
    let pred = SearchPredicate {
        query: "buy groceries".into(),
        status_filter: None,
        list_filter: None,
        tag_filter: None,
    };
    assert!(pred.status_filter.is_none());
}

#[test]
fn by_tag_predicate_by_id() {
    let pred = ByTagPredicate {
        tag_id: Some("abc-123".into()),
        tag_lookup_key: None,
    };
    assert!(pred.tag_id.is_some());
    assert!(pred.tag_lookup_key.is_none());
}
