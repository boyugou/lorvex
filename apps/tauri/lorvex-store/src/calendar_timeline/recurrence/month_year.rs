use super::parse::{
    days_in_month, parse_byday_tokens, parse_bymonth, parse_bymonthday, parse_bysetpos,
    ByMonthDayAnchor,
};
use crate::error::StoreError;
use chrono::{Datelike, NaiveDate};
use serde_json::Value;

fn add_months_clamped_required(
    base: NaiveDate,
    months_to_add: i64,
    anchor: ByMonthDayAnchor,
) -> Result<NaiveDate, StoreError> {
    add_months_with_anchor(base, months_to_add, anchor).ok_or_else(|| {
        StoreError::Invariant(format!(
            "failed to advance recurrence month from {base} by {months_to_add} months with anchor {anchor:?}"
        ))
    })
}
fn nth_weekday_in_month(year: i32, month: u32, dow: u32, ordinal: i32) -> Option<NaiveDate> {
    if ordinal == 0 {
        return None;
    }
    let max_day = days_in_month(year, month)?;
    if ordinal > 0 {
        let first = NaiveDate::from_ymd_opt(year, month, 1)?;
        let first_dow = first.weekday().num_days_from_sunday();
        let offset = (dow + 7 - first_dow) % 7;
        // Checked arithmetic so a peer or RRULE with `BYDAY=53MO`
        // (parser allows ±53) can't push `day` past `u32::MAX`. Any
        // overflow returns `None`, which the caller treats as "no
        // such occurrence" — same as `day > max_day`.
        let day = (ordinal as u32)
            .checked_sub(1)?
            .checked_mul(7)?
            .checked_add(1 + offset)?;
        if day <= max_day {
            NaiveDate::from_ymd_opt(year, month, day)
        } else {
            None
        }
    } else {
        let last = NaiveDate::from_ymd_opt(year, month, max_day)?;
        let last_dow = last.weekday().num_days_from_sunday();
        let offset = (last_dow + 7 - dow) % 7;
        // Checked arithmetic: `BYDAY=-5MO` in February
        // (`max_day=28, offset>0, multiplier=28`) underflows the bare
        // `max_day - offset - (|ord|-1)*7` form, panicking debug
        // builds and silently wrapping in release. Any underflow now
        // returns `None`, same as the caller's "no such occurrence"
        // branch.
        let subtract = ordinal
            .unsigned_abs()
            .checked_sub(1)?
            .checked_mul(7)?
            .checked_add(offset)?;
        let day = max_day.checked_sub(subtract)?;
        NaiveDate::from_ymd_opt(year, month, day)
    }
}

fn nth_weekday_in_year(year: i32, dow: u32, ordinal: i32) -> Option<NaiveDate> {
    if ordinal == 0 {
        return None;
    }
    if ordinal > 0 {
        let first = NaiveDate::from_ymd_opt(year, 1, 1)?;
        let first_dow = first.weekday().num_days_from_sunday();
        let offset = (dow + 7 - first_dow) % 7;
        // Checked arithmetic: same overflow class as
        // `nth_weekday_in_month` — a `BYDAY=53MO` ordinal (parser
        // ceiling) wrap silently.
        let day_of_year = (ordinal as u32)
            .checked_sub(1)?
            .checked_mul(7)?
            .checked_add(1 + offset)?;
        NaiveDate::from_yo_opt(year, day_of_year)
    } else {
        let last = NaiveDate::from_ymd_opt(year, 12, 31)?;
        let last_dow = last.weekday().num_days_from_sunday();
        let offset = (last_dow + 7 - dow) % 7;
        // Checked arithmetic: any negative ordinal `|o|>=53` plus a
        // sufficiently small `last.ordinal() - offset` underflowed
        // the bare subtraction. Returns `None` on underflow, same
        // as `day_of_year` outside `1..=last.ordinal()`.
        let subtract = ordinal
            .unsigned_abs()
            .checked_sub(1)?
            .checked_mul(7)?
            .checked_add(offset)?;
        let day_of_year = last.ordinal().checked_sub(subtract)?;
        NaiveDate::from_yo_opt(year, day_of_year)
    }
}

fn apply_bysetpos(mut candidates: Vec<NaiveDate>, positions: &[i64]) -> Vec<NaiveDate> {
    candidates.sort_unstable();
    candidates.dedup();
    let len = candidates.len() as i64;
    let mut selected = Vec::new();
    for position in positions {
        let index = if *position > 0 {
            *position - 1
        } else {
            len + *position
        };
        if (0..len).contains(&index) {
            selected.push(candidates[index as usize]);
        }
    }
    selected.sort_unstable();
    selected.dedup();
    selected
}

fn resolve_bymonthday_for_month(
    anchor: ByMonthDayAnchor,
    year: i32,
    month: u32,
    clamp: bool,
) -> Option<NaiveDate> {
    let max_day = days_in_month(year, month)?;
    let day = match anchor {
        ByMonthDayAnchor::FromStart(day) if day <= max_day => day,
        ByMonthDayAnchor::FromStart(day) if clamp => day.min(max_day),
        ByMonthDayAnchor::FromStart(_) => return None,
        ByMonthDayAnchor::FromEnd(offset) => {
            let clamped = offset.min(max_day);
            max_day - clamped + 1
        }
    };
    NaiveDate::from_ymd_opt(year, month, day)
}

pub(super) fn month_candidates(
    rule: &Value,
    year: i32,
    month: u32,
    fallback_day: u32,
    apply_setpos: bool,
) -> Result<Vec<NaiveDate>, StoreError> {
    let max_day = days_in_month(year, month).ok_or_else(|| {
        StoreError::Invariant(format!("invalid recurrence month {year}-{month:02}"))
    })?;
    let byday = parse_byday_tokens(rule)?;
    let bysetpos = parse_bysetpos(rule)?;
    let has_bymonthday = !rule.get("BYMONTHDAY").is_none_or(Value::is_null);
    let anchors = parse_bymonthday(rule, fallback_day)?;

    let mut candidates: Vec<NaiveDate> = if has_bymonthday {
        // Explicit BYMONTHDAY follows RFC 5545 §3.3.10: a positive day the
        // month lacks (31 in February) yields no occurrence — the month is
        // skipped, never clamped, matching the `BymonthdaySkipsMonths`
        // warning and a verbatim `BYMONTHDAY=31` RRULE. Negative anchors
        // resolve against month length. Multiple month-days (`[1, 15]`)
        // each resolve independently; the sort + dedup below merges them
        // into one ascending list for the month.
        anchors
            .iter()
            .filter_map(|anchor| resolve_bymonthday_for_month(*anchor, year, month, false))
            .collect()
    } else if byday.is_some() || bysetpos.is_some() {
        (1..=max_day)
            .filter_map(|day| NaiveDate::from_ymd_opt(year, month, day))
            .collect()
    } else {
        // Implicit day-of-month, no positional keys: clamp to the month end
        // so an un-injected raw rule still advances. Authoring paths inject
        // an explicit BYMONTHDAY first (negative for month-end anchors), so
        // the friendly Jan31->Feb28->Mar31 series flows through the branch
        // above, RFC-faithfully. `anchors` here is `[FromStart(fallback_day)]`.
        anchors
            .iter()
            .filter_map(|anchor| resolve_bymonthday_for_month(*anchor, year, month, true))
            .collect()
    };

    if let Some(tokens) = byday {
        candidates.retain(|date| {
            tokens.iter().any(|token| {
                if date.weekday().num_days_from_sunday() != token.dow {
                    return false;
                }
                token.ordinal.is_none_or(|ordinal| {
                    nth_weekday_in_month(year, month, token.dow, ordinal) == Some(*date)
                })
            })
        });
    }

    candidates.sort_unstable();
    candidates.dedup();
    if apply_setpos {
        if let Some(positions) = bysetpos {
            candidates = apply_bysetpos(candidates, &positions);
        }
    }
    Ok(candidates)
}

pub(super) fn first_monthly_candidate_on_or_after(
    rule: &Value,
    base: NaiveDate,
    target: NaiveDate,
    interval: i64,
) -> Result<Option<NaiveDate>, StoreError> {
    let bymonth = parse_bymonth(rule)?;
    let target = target.max(base);
    let months_between = (i64::from(target.year() - base.year()) * 12) + i64::from(target.month0())
        - i64::from(base.month0());
    let initial_steps = if months_between <= 0 {
        0
    } else {
        (months_between / interval).max(0)
    };

    // The cap is a runtime safety net, not a UNTIL boundary check.
    // Real rules are bounded explicitly via UNTIL/COUNT (handled higher
    // up in `first_occurrence_on_or_after`); this loop only walks
    // forward enough months to find the next candidate. 2400 iterations
    // is at least 200 years for monthly cadences (interval=1) and
    // 2400 × interval years otherwise — far past the calendar horizon
    // of any real planner. Treat exhaustion as "no occurrence in the
    // observable future" and return Ok(None) so callers truncate
    // gracefully rather than surface an Invariant that the user can't
    // act on.
    for steps in initial_steps..initial_steps + 2400 {
        let month_start = add_months_clamped_required(
            NaiveDate::from_ymd_opt(base.year(), base.month(), 1).ok_or_else(|| {
                StoreError::Invariant(format!("invalid monthly recurrence base date {base}"))
            })?,
            steps * interval,
            ByMonthDayAnchor::FromStart(1),
        )?;
        if bymonth
            .as_ref()
            .is_none_or(|months| months.contains(&month_start.month()))
        {
            for candidate in month_candidates(
                rule,
                month_start.year(),
                month_start.month(),
                base.day(),
                true,
            )? {
                if candidate >= target {
                    return Ok(Some(candidate));
                }
            }
        }
    }
    Ok(None)
}

pub(super) fn yearly_candidates(
    rule: &Value,
    base: NaiveDate,
    year: i32,
) -> Result<Vec<NaiveDate>, StoreError> {
    let bymonth = parse_bymonth(rule)?;
    let byday = parse_byday_tokens(rule)?;
    let bysetpos = parse_bysetpos(rule)?;
    let has_bymonth = !rule.get("BYMONTH").is_none_or(Value::is_null);
    let has_bymonthday = !rule.get("BYMONTHDAY").is_none_or(Value::is_null);
    let months: Vec<u32> = match bymonth {
        Some(months) => months,
        None if byday.is_some() && !has_bymonthday => (1..=12).collect(),
        None => vec![base.month()],
    };

    let mut candidates = Vec::new();
    for month in months {
        let mut month_dates = month_candidates(rule, year, month, base.day(), false)?;
        if let Some(tokens) = byday.as_ref() {
            if !has_bymonth {
                month_dates.retain(|date| {
                    tokens.iter().any(|token| {
                        if date.weekday().num_days_from_sunday() != token.dow {
                            return false;
                        }
                        token.ordinal.is_none_or(|ordinal| {
                            nth_weekday_in_year(year, token.dow, ordinal) == Some(*date)
                        })
                    })
                });
            }
        }
        candidates.extend(month_dates);
    }

    if !has_bymonth && !has_bymonthday && byday.is_none() && bysetpos.is_none() {
        // Implicit fallback (no positional keys): clamp the base day-of-month
        // to the target month end so a bare YEARLY rule still advances.
        candidates = parse_bymonthday(rule, base.day())?
            .iter()
            .filter_map(|anchor| resolve_bymonthday_for_month(*anchor, year, base.month(), true))
            .collect();
    }

    candidates.sort_unstable();
    candidates.dedup();
    if let Some(positions) = bysetpos {
        candidates = apply_bysetpos(candidates, &positions);
    }
    Ok(candidates)
}

pub(super) fn first_yearly_candidate_on_or_after(
    rule: &Value,
    base: NaiveDate,
    target: NaiveDate,
    interval: i64,
) -> Result<Option<NaiveDate>, StoreError> {
    let target = target.max(base);
    let years_between = i64::from(target.year() - base.year());
    let initial_steps = if years_between <= 0 {
        0
    } else {
        (years_between / interval).max(0)
    };

    // Same rationale as `first_monthly_candidate_on_or_after`: 400
    // iterations × interval years covers the practical horizon, and
    // exhaustion is a "no observable occurrence" signal, not an
    // invariant break.
    for steps in initial_steps..initial_steps + 400 {
        let year = base.year()
            + i32::try_from(steps * interval).map_err(|_| {
                StoreError::Invariant(format!(
                    "yearly recurrence step overflow from {base} with interval {interval}"
                ))
            })?;
        for candidate in yearly_candidates(rule, base, year)? {
            if candidate >= target {
                return Ok(Some(candidate));
            }
        }
    }
    Ok(None)
}

// ---------------------------------------------------------------------------
// Core date arithmetic
// ---------------------------------------------------------------------------

/// Advance `base` by `months_to_add` months, clamping the day to `target_day`
/// (or the month maximum, whichever is smaller).
///
/// The explicit `target_day` parameter preserves BYMONTHDAY anchors through
/// months with fewer days (e.g. Jan 31 -> Feb 28 -> Mar 31).
pub fn add_months_clamped(
    base: NaiveDate,
    months_to_add: i64,
    target_day: u32,
) -> Option<NaiveDate> {
    add_months_with_anchor(base, months_to_add, ByMonthDayAnchor::FromStart(target_day))
}

/// Like [`add_months_clamped`] but accepts a signed [`ByMonthDayAnchor`]
/// so that `FromEnd(n)` (RFC 5545 BYMONTHDAY=-n) resolves correctly
/// against the target month's actual length.
pub(crate) fn add_months_with_anchor(
    base: NaiveDate,
    months_to_add: i64,
    anchor: ByMonthDayAnchor,
) -> Option<NaiveDate> {
    let total_month_index = i64::from(base.year()) * 12 + i64::from(base.month0()) + months_to_add;
    let new_year = i32::try_from(total_month_index.div_euclid(12)).ok()?;
    let new_month0 = u32::try_from(total_month_index.rem_euclid(12)).ok()?;
    let new_month = new_month0 + 1;
    let day = anchor.resolve(new_year, new_month)?;
    NaiveDate::from_ymd_opt(new_year, new_month, day)
}
