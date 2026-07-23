use super::parse::{byday_code_to_num, parse_bymonth, parse_wkst};
use crate::error::StoreError;
use chrono::{Datelike, Duration, NaiveDate};
use serde_json::Value;

/// Extract sorted, deduplicated day-of-week numbers from a recurrence rule's
/// `BYDAY` array. Returns `Ok(None)` if the array is absent or empty.
pub fn weekly_target_dows(rule: &Value) -> Result<Option<Vec<u32>>, StoreError> {
    let Some(byday) = rule.get("BYDAY").and_then(Value::as_array) else {
        return Ok(None);
    };
    if byday.is_empty() {
        return Ok(None);
    }

    let mut target_dows: Vec<u32> = Vec::with_capacity(byday.len());
    for raw in byday {
        let code = raw.as_str().ok_or_else(|| {
            StoreError::Validation(
                "invalid recurrence rule: BYDAY entries must be weekday codes".to_string(),
            )
        })?;
        let dow = byday_code_to_num(code).ok_or_else(|| {
            StoreError::Validation(format!(
                "invalid recurrence rule: unsupported BYDAY code {code}"
            ))
        })?;
        target_dows.push(dow);
    }
    target_dows.sort_unstable();
    target_dows.dedup();
    Ok(Some(target_dows))
}

/// For a WEEKLY rule with BYDAY, find the first occurrence on or after
/// `target` that is aligned to the recurrence cadence anchored at `base`.
pub fn first_weekly_byday_occurrence_on_or_after(
    rule: &Value,
    base: NaiveDate,
    target: NaiveDate,
    interval: i64,
) -> Result<Option<NaiveDate>, StoreError> {
    let Some(mut target_dows) = weekly_target_dows(rule)? else {
        return Ok(None);
    };
    let wkst = parse_wkst(rule)?;
    let week_start = |date: NaiveDate| {
        let dow = date.weekday().num_days_from_sunday();
        date - Duration::days(i64::from((dow + 7 - wkst) % 7))
    };
    let day_offset = |dow: u32| i64::from((dow + 7 - wkst) % 7);
    target_dows.sort_by_key(|dow| day_offset(*dow));
    let base_week_start = week_start(base);
    let target_week_start = week_start(target.max(base));
    let weeks_between = ((target_week_start - base_week_start).num_days() / 7).max(0);
    let aligned_weeks = (weeks_between / interval) * interval;
    let mut current_week_start = base_week_start + Duration::weeks(aligned_weeks);

    for _ in 0..3 {
        let minimum_date = if current_week_start == base_week_start {
            base.max(target)
        } else {
            target.max(current_week_start)
        };
        for dow in &target_dows {
            let candidate = current_week_start + Duration::days(day_offset(*dow));
            if candidate < base {
                continue;
            }
            if candidate >= minimum_date {
                return Ok(Some(candidate));
            }
        }
        current_week_start += Duration::weeks(interval);
    }

    Ok(None)
}

pub(super) fn first_weekly_candidate_on_or_after(
    rule: &Value,
    base: NaiveDate,
    target: NaiveDate,
    interval: i64,
) -> Result<Option<NaiveDate>, StoreError> {
    let bymonth = parse_bymonth(rule)?;
    let allowed_month = |date: NaiveDate| {
        bymonth
            .as_ref()
            .is_none_or(|months| months.contains(&date.month()))
    };

    if rule["BYDAY"]
        .as_array()
        .is_some_and(|days| !days.is_empty())
    {
        let mut cursor = target.max(base);
        for _ in 0..2400 {
            let Some(candidate) =
                first_weekly_byday_occurrence_on_or_after(rule, base, cursor, interval)?
            else {
                return Ok(None);
            };
            if allowed_month(candidate) {
                return Ok(Some(candidate));
            }
            cursor = candidate + Duration::days(1);
        }
        return Err(StoreError::Invariant(format!(
            "failed to find weekly BYMONTH recurrence candidate from {base} on or after {target}"
        )));
    }

    let target = target.max(base);
    let interval_days = interval * 7;
    let delta = (target - base).num_days().max(0);
    let initial_steps = (delta + interval_days - 1) / interval_days;
    for steps in initial_steps..initial_steps + 2400 {
        let candidate = base + Duration::days(steps * interval_days);
        if candidate >= target && allowed_month(candidate) {
            return Ok(Some(candidate));
        }
    }
    Err(StoreError::Invariant(format!(
        "failed to find weekly recurrence candidate from {base} on or after {target}"
    )))
}
