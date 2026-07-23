use super::month_year::{first_monthly_candidate_on_or_after, first_yearly_candidate_on_or_after};
use super::parse::{
    parse_bounded_count_for_expansion, parse_freq, parse_interval, parse_required_ymd,
    parse_rule_object, parse_until, MAX_RECURRENCE_COUNT,
};
use super::weekly::first_weekly_candidate_on_or_after;
use crate::error::StoreError;
use chrono::{Duration, NaiveDate};

/// Check whether the event span `[start, end]` overlaps the query window
/// `[from, to]` (both inclusive).
pub fn overlaps_calendar_range(
    start: NaiveDate,
    end: NaiveDate,
    from: NaiveDate,
    to: NaiveDate,
) -> bool {
    start <= to && end >= from
}

// ---------------------------------------------------------------------------
// First-occurrence-on-or-after
// ---------------------------------------------------------------------------

/// Compute the first occurrence of a recurrence on or after `target`,
/// anchored at `base`. Respects UNTIL bounds.
///
/// For WEEKLY rules with BYDAY, delegates to
/// [`first_weekly_byday_occurrence_on_or_after`].
pub fn first_occurrence_on_or_after(
    recurrence_json: &str,
    base: NaiveDate,
    target: NaiveDate,
) -> Result<Option<NaiveDate>, StoreError> {
    let rule = parse_rule_object(recurrence_json)?;
    let freq = parse_freq(&rule)?;
    let interval = parse_interval(&rule)?;
    let until = parse_until(&rule)?;
    if until.is_some_and(|bound| target > bound) {
        return Ok(None);
    }

    let candidate = match freq {
        "DAILY" => {
            if target <= base {
                base
            } else {
                let delta = (target - base).num_days();
                let steps = (delta + interval - 1) / interval;
                base + Duration::days(steps * interval)
            }
        }
        "WEEKLY" => match first_weekly_candidate_on_or_after(&rule, base, target, interval)? {
            Some(date) => date,
            None => return Ok(None),
        },
        "MONTHLY" => match first_monthly_candidate_on_or_after(&rule, base, target, interval)? {
            Some(date) => date,
            None => return Ok(None),
        },
        "YEARLY" => match first_yearly_candidate_on_or_after(&rule, base, target, interval)? {
            Some(date) => date,
            None => return Ok(None),
        },
        _ => {
            return Err(StoreError::Validation(format!(
                "invalid recurrence rule: unsupported FREQ {freq}"
            )))
        }
    };

    if until.is_some_and(|bound| candidate > bound) {
        return Ok(None);
    }

    Ok(Some(candidate))
}

// ---------------------------------------------------------------------------
// recurs_on_date
// ---------------------------------------------------------------------------

/// Check if a recurring event (with recurrence JSON and base date) has an
/// occurrence on exactly `target_date_ymd`.
pub fn recurs_on_date(
    recurrence_json: &str,
    base_date_ymd: &str,
    target_date_ymd: &str,
) -> Result<bool, StoreError> {
    let base = parse_required_ymd(base_date_ymd, "base_date")?;
    let target = parse_required_ymd(target_date_ymd, "target_date")?;
    if target < base {
        return Ok(false);
    }
    if target == base {
        return Ok(true);
    }

    let rule = parse_rule_object(recurrence_json)?;

    // Check UNTIL bound.
    if let Some(until) = parse_until(&rule)? {
        if target > until {
            return Ok(false);
        }
    }

    // Check COUNT bound — enumerate occurrences up to count.
    if let Some(count) = parse_bounded_count_for_expansion(&rule)? {
        let mut current = base_date_ymd.to_string();
        for _ in 1..count {
            match calculate_next_occurrence_date(recurrence_json, &current)? {
                Some(next) if next > current => {
                    if next.as_str() == target_date_ymd {
                        return Ok(true);
                    }
                    if next.as_str() > target_date_ymd {
                        return Ok(false);
                    }
                    current = next;
                }
                _ => return Ok(false),
            }
        }
        return Ok(false);
    }

    // Unbounded recurrence — find first occurrence on or after target.
    let first = first_occurrence_on_or_after(recurrence_json, base, target)?;
    Ok(first.is_some_and(|d| d == target))
}

// ---------------------------------------------------------------------------
// calculate_next_occurrence_date
// ---------------------------------------------------------------------------

/// Compute the next occurrence date after `base_date_ymd`, respecting UNTIL.
///
/// This is the canonical name (matching the MCP crate). The Tauri crate's
/// `calculate_next_occurrence` is equivalent.
pub fn calculate_next_occurrence_date(
    recurrence_json: &str,
    base_date_ymd: &str,
) -> Result<Option<String>, StoreError> {
    let rule = parse_rule_object(recurrence_json)?;
    let base = parse_required_ymd(base_date_ymd, "base_date")?;
    let target = base + Duration::days(1);
    let Some(next) = first_occurrence_on_or_after(recurrence_json, base, target)? else {
        return Ok(None);
    };

    // Enforce UNTIL bound.
    if let Some(until) = parse_until(&rule)? {
        if next > until {
            return Ok(None);
        }
    }

    Ok(Some(next.format("%Y-%m-%d").to_string()))
}

// ---------------------------------------------------------------------------
// next_occurrence_strictly_after
// ---------------------------------------------------------------------------

/// Compute the next recurrence date strictly after both `today_ymd` and
/// `base_date_ymd`, using `base_date_ymd` for cadence alignment.
///
/// This prevents deferred due dates from shifting the recurrence cadence:
/// instead of computing `deferred_date + interval`, we find the first
/// occurrence in the cadence that falls after today (and after the current
/// due date).
pub fn next_occurrence_strictly_after(
    recurrence_json: &str,
    base_date_ymd: &str,
    today_ymd: &str,
) -> Result<Option<String>, StoreError> {
    let base = parse_required_ymd(base_date_ymd, "base_date")?;
    let today = parse_required_ymd(today_ymd, "today")?;
    let floor = if base > today { base } else { today };
    let target = floor + Duration::days(1);
    let next = first_occurrence_on_or_after(recurrence_json, base, target)?;
    Ok(next.map(|date| date.format("%Y-%m-%d").to_string()))
}

// ---------------------------------------------------------------------------
// count_end_date
// ---------------------------------------------------------------------------

/// Given a recurrence JSON and a base date, compute the date of the Nth
/// occurrence (1-indexed: count=1 means just the base date itself).
///
/// Returns `Ok(None)` if COUNT is absent or if the series terminates early.
pub fn count_end_date(
    recurrence_json: &str,
    base_date: &str,
) -> Result<Option<String>, StoreError> {
    let rule = parse_rule_object(recurrence_json)?;
    let Some(count) = parse_bounded_count_for_expansion(&rule)? else {
        return Ok(None);
    };
    if count == 1 {
        parse_required_ymd(base_date, "base_date")?;
        return Ok(Some(base_date.to_string()));
    }

    parse_required_ymd(base_date, "base_date")?;
    // Defensive cap in case a pre-existing DB row bypassed `parse_count`
    // (e.g. a legacy rule stored before MAX_RECURRENCE_COUNT was enforced).
    let bounded_count = count.min(MAX_RECURRENCE_COUNT);
    let mut current = base_date.to_string();
    for _ in 1..bounded_count {
        let Some(next) = calculate_next_occurrence_date(recurrence_json, &current)? else {
            return Ok(None);
        };
        if next <= current {
            return Err(StoreError::Invariant(format!(
                "non-advancing recurrence when computing COUNT end date from {current}"
            )));
        }
        current = next;
    }
    Ok(Some(current))
}
