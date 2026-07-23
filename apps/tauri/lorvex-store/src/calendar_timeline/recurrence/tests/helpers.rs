use super::*;

pub(super) fn weekly_target_dows(rule: &Value) -> Option<Vec<u32>> {
    super::weekly_target_dows(rule).expect("recurrence rule should parse")
}

pub(super) fn first_weekly_byday_occurrence_on_or_after(
    rule: &Value,
    base: NaiveDate,
    target: NaiveDate,
    interval: i64,
) -> Option<NaiveDate> {
    super::first_weekly_byday_occurrence_on_or_after(rule, base, target, interval)
        .expect("recurrence rule should parse")
}

pub(super) fn recurs_on_date(
    recurrence_json: &str,
    base_date_ymd: &str,
    target_date_ymd: &str,
) -> bool {
    super::recurs_on_date(recurrence_json, base_date_ymd, target_date_ymd)
        .expect("recurrence rule should parse")
}

pub(super) fn first_occurrence_on_or_after(
    recurrence_json: &str,
    base: NaiveDate,
    target: NaiveDate,
) -> Option<NaiveDate> {
    super::first_occurrence_on_or_after(recurrence_json, base, target)
        .expect("recurrence rule should parse")
}

pub(super) fn calculate_next_occurrence_date(
    recurrence_json: &str,
    base_date_ymd: &str,
) -> Option<String> {
    super::calculate_next_occurrence_date(recurrence_json, base_date_ymd)
        .expect("recurrence rule should parse")
}

pub(super) fn next_occurrence_strictly_after(
    recurrence_json: &str,
    base_date_ymd: &str,
    today_ymd: &str,
) -> Option<String> {
    super::next_occurrence_strictly_after(recurrence_json, base_date_ymd, today_ymd)
        .expect("recurrence rule should parse")
}

pub(super) fn count_end_date(recurrence_json: &str, base_date: &str) -> Option<String> {
    super::count_end_date(recurrence_json, base_date).expect("recurrence rule should parse")
}

// -----------------------------------------------------------------------
// parse_ymd
