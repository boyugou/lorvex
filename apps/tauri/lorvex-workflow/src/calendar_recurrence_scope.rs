use chrono::{Datelike, NaiveDate};
use serde_json::{Map, Value};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TruncateRecurrenceResult {
    Truncated(String),
    Collapse,
    Noop,
}

fn parse_ymd(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()
}

fn format_ymd(value: NaiveDate) -> String {
    value.format("%Y-%m-%d").to_string()
}

pub fn add_ymd_days(value: &str, days: i64) -> Option<String> {
    parse_ymd(value)
        .and_then(|date| date.checked_add_signed(chrono::Duration::days(days)))
        .map(format_ymd)
}

pub fn rebase_date_range_to_occurrence(
    start_date: &str,
    end_date: Option<&str>,
    occurrence_date: &str,
) -> Option<(String, Option<String>)> {
    let previous_start = parse_ymd(start_date)?;
    let occurrence = parse_ymd(occurrence_date)?;
    let next_end = match end_date {
        Some(end) => {
            let previous_end = parse_ymd(end)?;
            let offset = previous_end
                .signed_duration_since(previous_start)
                .num_days();
            Some(format_ymd(
                occurrence.checked_add_signed(chrono::Duration::days(offset))?,
            ))
        }
        None => None,
    };
    Some((occurrence_date.to_string(), next_end))
}

fn weekday_to_index(code: &str) -> Option<u32> {
    match code {
        "SU" => Some(0),
        "MO" => Some(1),
        "TU" => Some(2),
        "WE" => Some(3),
        "TH" => Some(4),
        "FR" => Some(5),
        "SA" => Some(6),
        _ => None,
    }
}

fn advance_by_valid_months(start: NaiveDate, months_to_add: i64) -> Option<NaiveDate> {
    if months_to_add == 0 {
        return Some(start);
    }
    if months_to_add < 0 {
        return None;
    }
    let target_day = start.day();
    let start_year = start.year();
    let start_month0 = start.month0() as i32;
    let mut year = start_year;
    let mut month0 = start_month0;
    let mut steps_applied = 0_i64;
    let ceiling_months = ((months_to_add * 12) + 6) / 7 + 12;
    while steps_applied < months_to_add {
        month0 += 1;
        if month0 > 11 {
            month0 = 0;
            year += 1;
        }
        if NaiveDate::from_ymd_opt(year, (month0 + 1) as u32, target_day).is_some() {
            steps_applied += 1;
        }
        let months_walked = i64::from((year - start_year) * 12 + (month0 - start_month0));
        if months_walked > ceiling_months {
            return None;
        }
    }
    NaiveDate::from_ymd_opt(year, (month0 + 1) as u32, target_day)
}

fn advance_by_valid_years(start: NaiveDate, years_to_add: i64) -> Option<NaiveDate> {
    if years_to_add == 0 {
        return Some(start);
    }
    if years_to_add < 0 {
        return None;
    }
    let target_month = start.month();
    let target_day = start.day();
    let mut year = start.year();
    let mut steps_applied = 0_i64;
    let ceiling = years_to_add * 8 + 8;
    let mut walked = 0_i64;
    while steps_applied < years_to_add {
        year += 1;
        walked += 1;
        if walked > ceiling {
            return None;
        }
        if NaiveDate::from_ymd_opt(year, target_month, target_day).is_some() {
            steps_applied += 1;
        }
    }
    NaiveDate::from_ymd_opt(year, target_month, target_day)
}

fn natural_count_end(
    start_ymd: &str,
    freq: &str,
    interval: i64,
    count: i64,
    byday: Option<&[String]>,
) -> Option<String> {
    if count <= 0 || interval <= 0 {
        return None;
    }
    let start = parse_ymd(start_ymd)?;
    let end = match freq {
        "DAILY" => start.checked_add_signed(chrono::Duration::days((count - 1) * interval))?,
        "WEEKLY" => {
            let Some(byday) = byday.filter(|days| !days.is_empty()) else {
                return Some(format_ymd(start.checked_add_signed(
                    chrono::Duration::days((count - 1) * interval * 7),
                )?));
            };
            let mut day_indices = byday
                .iter()
                .filter_map(|code| weekday_to_index(code))
                .collect::<Vec<_>>();
            day_indices.sort_unstable();
            if day_indices.is_empty() {
                return None;
            }
            let start_dow = start.weekday().num_days_from_sunday();
            let mut occurrences_found = 0_i64;
            let mut week_offset = 0_i64;
            loop {
                for dow in &day_indices {
                    let day_delta =
                        i64::from(*dow) - i64::from(start_dow) + week_offset * 7 * interval;
                    if day_delta < 0 {
                        continue;
                    }
                    occurrences_found += 1;
                    if occurrences_found == count {
                        return Some(format_ymd(
                            start.checked_add_signed(chrono::Duration::days(day_delta))?,
                        ));
                    }
                }
                week_offset += 1;
                if week_offset > 10_000 {
                    return None;
                }
            }
        }
        "MONTHLY" => {
            if byday.is_some_and(|days| !days.is_empty()) {
                return None;
            }
            advance_by_valid_months(start, (count - 1) * interval)?
        }
        "YEARLY" => {
            if byday.is_some_and(|days| !days.is_empty()) {
                return None;
            }
            advance_by_valid_years(start, (count - 1) * interval)?
        }
        _ => return None,
    };
    Some(format_ymd(end))
}

pub fn truncate_recurrence_before(
    raw_recurrence: Option<&str>,
    split_date_ymd: &str,
    series_start_ymd: Option<&str>,
) -> TruncateRecurrenceResult {
    let Some(raw_recurrence) = raw_recurrence else {
        return TruncateRecurrenceResult::Collapse;
    };
    if series_start_ymd.is_some_and(|start| split_date_ymd <= start) {
        return TruncateRecurrenceResult::Collapse;
    }
    let Ok(Value::Object(parsed)) = serde_json::from_str::<Value>(raw_recurrence) else {
        return TruncateRecurrenceResult::Collapse;
    };
    let Some(split_minus_one) = add_ymd_days(split_date_ymd, -1) else {
        return TruncateRecurrenceResult::Collapse;
    };
    let mut next: Map<String, Value> = parsed;
    let existing_until = next
        .get("UNTIL")
        .and_then(Value::as_str)
        .map(str::to_string);
    let existing_count = next.get("COUNT").and_then(Value::as_i64);
    next.remove("COUNT");

    if let Some(existing_until) = existing_until {
        next.insert(
            "UNTIL".to_string(),
            Value::String(if existing_until < split_minus_one {
                existing_until
            } else {
                split_minus_one
            }),
        );
        return TruncateRecurrenceResult::Truncated(Value::Object(next).to_string());
    }

    if let Some(existing_count) = existing_count {
        let freq = next.get("FREQ").and_then(Value::as_str).unwrap_or("");
        let interval = next.get("INTERVAL").and_then(Value::as_i64).unwrap_or(1);
        let byday = next.get("BYDAY").and_then(Value::as_array).map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        });
        let natural_end = series_start_ymd.and_then(|start| {
            natural_count_end(start, freq, interval, existing_count, byday.as_deref())
        });
        if natural_end.is_some_and(|end| end < split_minus_one) {
            return TruncateRecurrenceResult::Noop;
        }
        next.insert("UNTIL".to_string(), Value::String(split_minus_one));
        return TruncateRecurrenceResult::Truncated(Value::Object(next).to_string());
    }

    next.insert("UNTIL".to_string(), Value::String(split_minus_one));
    TruncateRecurrenceResult::Truncated(Value::Object(next).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn truncated(raw: &str, split: &str, start: &str) -> serde_json::Value {
        match truncate_recurrence_before(Some(raw), split, Some(start)) {
            TruncateRecurrenceResult::Truncated(next) => serde_json::from_str(&next).unwrap(),
            other => panic!("expected truncation, got {other:?}"),
        }
    }

    #[test]
    fn truncates_unbounded_daily_recurrence_to_split_minus_one() {
        let next = truncated(
            r#"{"FREQ":"DAILY","INTERVAL":1}"#,
            "2026-05-10",
            "2026-05-01",
        );
        assert_eq!(next["UNTIL"], "2026-05-09");
        assert_eq!(next["FREQ"], "DAILY");
    }

    #[test]
    fn malformed_or_non_object_recurrence_collapses_original() {
        assert_eq!(
            truncate_recurrence_before(None, "2026-05-10", Some("2026-05-01")),
            TruncateRecurrenceResult::Collapse
        );
        assert_eq!(
            truncate_recurrence_before(Some("not-json"), "2026-05-10", Some("2026-05-01")),
            TruncateRecurrenceResult::Collapse
        );
        assert_eq!(
            truncate_recurrence_before(Some("[1,2,3]"), "2026-05-10", Some("2026-05-01")),
            TruncateRecurrenceResult::Collapse
        );
    }

    #[test]
    fn preserves_earlier_until_instead_of_extending_series() {
        let next = truncated(
            r#"{"FREQ":"DAILY","UNTIL":"2026-05-03"}"#,
            "2026-05-10",
            "2026-05-01",
        );
        assert_eq!(next["UNTIL"], "2026-05-03");
    }

    #[test]
    fn weekly_count_byday_inside_range_clamps_and_preserves_grid() {
        let next = truncated(
            r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"COUNT":10}"#,
            "2026-02-15",
            "2026-01-05",
        );
        assert_eq!(next["UNTIL"], "2026-02-14");
        assert_eq!(next["BYDAY"], serde_json::json!(["MO"]));
        assert!(next.get("COUNT").is_none());
    }

    #[test]
    fn weekly_count_byday_finished_series_is_noop() {
        let result = truncate_recurrence_before(
            Some(r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"COUNT":10}"#),
            "2026-03-15",
            Some("2026-01-05"),
        );
        assert_eq!(result, TruncateRecurrenceResult::Noop);
    }

    #[test]
    fn count_bounded_month_end_uses_valid_rfc_instances() {
        let next = truncated(
            r#"{"FREQ":"MONTHLY","COUNT":3}"#,
            "2026-04-15",
            "2026-01-31",
        );
        assert_eq!(next["UNTIL"], "2026-04-14");
        assert!(next.get("COUNT").is_none());
    }

    #[test]
    fn yearly_leap_day_count_uses_valid_rfc_instances() {
        let next = truncated(
            r#"{"FREQ":"YEARLY","INTERVAL":1,"COUNT":2}"#,
            "2028-03-01",
            "2024-02-29",
        );
        assert_eq!(next["UNTIL"], "2028-02-29");
        assert!(next.get("COUNT").is_none());
    }

    #[test]
    fn unmodeled_monthly_byday_count_preserves_intent_with_until() {
        let next = truncated(
            r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["2MO"],"COUNT":5}"#,
            "2030-01-01",
            "2026-01-12",
        );
        assert_eq!(next["UNTIL"], "2029-12-31");
        assert_eq!(next["BYDAY"], serde_json::json!(["2MO"]));
        assert!(next.get("COUNT").is_none());
    }

    #[test]
    fn count_bounded_finished_series_is_noop() {
        let result = truncate_recurrence_before(
            Some(r#"{"FREQ":"DAILY","COUNT":2}"#),
            "2026-05-10",
            Some("2026-05-01"),
        );
        assert_eq!(result, TruncateRecurrenceResult::Noop);
    }

    #[test]
    fn split_at_series_start_collapses_original() {
        let result = truncate_recurrence_before(
            Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
            "2026-05-01",
            Some("2026-05-01"),
        );
        assert_eq!(result, TruncateRecurrenceResult::Collapse);
    }

    #[test]
    fn rebases_multi_day_payload_dates_to_occurrence() {
        assert_eq!(
            rebase_date_range_to_occurrence("2026-05-01", Some("2026-05-03"), "2026-05-10"),
            Some(("2026-05-10".to_string(), Some("2026-05-12".to_string()))),
        );
    }
}
