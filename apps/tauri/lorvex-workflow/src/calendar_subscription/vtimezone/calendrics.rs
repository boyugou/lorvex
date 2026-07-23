//! Calendar arithmetic for VTIMEZONE rule resolution: walking back
//! from a query instant to the nearest yearly DST transition
//! (`latest_transition_at_or_before`) and computing the n-th weekday
//! of a month (`nth_weekday_of_month`) for `BYDAY=2SU` / `BYDAY=-1SU`
//! patterns. No IO, pure date math.

use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, Weekday};

use super::types::Observance;

/// Find the latest transition for a single observance that is at
/// or before `naive_local`. Returns `None` only if the observance
/// has not yet started by `naive_local`.
pub(super) fn latest_transition_at_or_before(
    obs: &Observance,
    naive_local: NaiveDateTime,
) -> Option<NaiveDateTime> {
    if obs.dtstart > naive_local {
        return None;
    }

    let Some(rule) = &obs.rrule else {
        return Some(obs.dtstart);
    };

    // Find the latest yearly occurrence of the rule that is at or
    // before naive_local. The rule recurs yearly starting at
    // `obs.dtstart.year()`. Walk backwards from naive_local.year()
    // and check each candidate.
    let query_year = naive_local.year();
    let start_year = obs.dtstart.year();

    // RRULE bound: don't materialize occurrences past `until`.
    let max_year = match rule.until {
        Some(until) if until.year() < query_year => until.year(),
        _ => query_year,
    };

    // Search a small window: the candidate may be in `query_year`
    // (most common — DST already happened this year) or
    // `query_year - 1` (we're in January, last year's STANDARD
    // observance is still active). Going further back is dominated
    // by another observance's later transition.
    let mut candidate: Option<NaiveDateTime> = None;
    for year in (start_year..=max_year).rev().take(2) {
        if let Some(occ) = nth_weekday_of_month(year, rule.by_month, rule.by_day) {
            let dt = occ.and_time(obs.dtstart.time());
            if dt <= naive_local {
                if let Some(until) = rule.until {
                    if dt > until {
                        continue;
                    }
                }
                candidate = Some(dt);
                break;
            }
        }
    }

    // Fallback: if no recurring occurrence is in range, the
    // observance is still active from its bare DTSTART.
    candidate.or(Some(obs.dtstart))
}

/// Compute the date of the `n`-th `weekday` of `(year, month)`.
/// Positive `n` counts from the start of the month (1 = first);
/// negative `n` counts from the end (-1 = last).
pub(crate) fn nth_weekday_of_month(
    year: i32,
    month: u32,
    by_day: (Weekday, i32),
) -> Option<NaiveDate> {
    let (target_weekday, n) = by_day;
    if n == 0 {
        return None;
    }
    if n > 0 {
        let first = NaiveDate::from_ymd_opt(year, month, 1)?;
        let first_weekday = first.weekday();
        let offset = (7 + target_weekday.num_days_from_sunday() as i32
            - first_weekday.num_days_from_sunday() as i32)
            % 7;
        let day = 1 + offset + (n - 1) * 7;
        NaiveDate::from_ymd_opt(year, month, day as u32)
    } else {
        // Last day of month
        let next_month_first = if month == 12 {
            NaiveDate::from_ymd_opt(year + 1, 1, 1)?
        } else {
            NaiveDate::from_ymd_opt(year, month + 1, 1)?
        };
        let last = next_month_first - Duration::days(1);
        let last_weekday = last.weekday();
        let offset = (7 + last_weekday.num_days_from_sunday() as i32
            - target_weekday.num_days_from_sunday() as i32)
            % 7;
        let day = last.day() as i32 - offset - (-(n) - 1) * 7;
        if day < 1 {
            return None;
        }
        NaiveDate::from_ymd_opt(year, month, day as u32)
    }
}
