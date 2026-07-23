//! Non-fatal recurrence-rule diagnostics.
//!
//! [`emit_warnings`] inspects an already-validated rule and surfaces
//! cases where the rule is technically legal but the user almost
//! certainly didn't realize the implication — e.g. `BYMONTHDAY=31`
//! silently skipping every month shorter than 31 days, or
//! `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29` only firing once every four
//! years (and not at all in centurial non-leap years).

use crate::validation::recurrence::RecurrenceWarning;

/// Emit non-fatal warnings for a normalized recurrence rule.
///
/// Walks the post-validation values, detects skip-prone idioms, and
/// returns the warning list (possibly empty). Each positive
/// `BYMONTHDAY` in 29..=31 raises one `BymonthdaySkipsMonths` warning
/// (in canonical order), since a multi-day rule can skip different
/// months for different days. The single-day leap-year birthday
/// pattern (`FREQ=YEARLY;BYMONTH=[2];BYMONTHDAY=[29]`) suppresses the
/// generic "BYMONTHDAY skips months" warning so the diagnostic surface
/// speaks plainly about the actual once-every-four-years behavior; a
/// multi-day rule keeps the per-day skip warnings.
pub(super) fn emit_warnings(
    freq: &str,
    bymonthday: Option<&[i64]>,
    bymonth: Option<&[i64]>,
) -> Vec<RecurrenceWarning> {
    let mut warnings: Vec<RecurrenceWarning> = Vec::new();
    if !matches!(freq, "MONTHLY" | "YEARLY") {
        return warnings;
    }
    let Some(days) = bymonthday else {
        return warnings;
    };

    // Negative values count from the end of the month and therefore
    // never skip a month — only positive 29/30/31 do. One warning per
    // such day, in the (already sorted+deduped) canonical order.
    for &day in days {
        if (29..=31).contains(&day) {
            warnings.push(RecurrenceWarning::BymonthdaySkipsMonths { day });
        }
    }

    // Leap-year birthday: `FREQ=YEARLY;BYMONTH=[2];BYMONTHDAY=[29]`
    // legitimately exists, but the user should know the rule only
    // fires every four years (and skips 2100 / 2200 / 2300 because of
    // the Gregorian century rule). Replace the generic
    // "BYMONTHDAY skips months" with the more specific leap-year
    // variant so the diagnostic surface can spell that out. Only the
    // single-day [29] shape collapses; a multi-day rule keeps its
    // per-day skip warnings.
    if freq == "YEARLY" && days == [29] {
        if let Some(months) = bymonth {
            if months.len() == 1 && months[0] == 2 {
                warnings.retain(|w| !matches!(w, RecurrenceWarning::BymonthdaySkipsMonths { .. }));
                warnings.push(RecurrenceWarning::LeapYearBirthday);
            }
        }
    }

    warnings
}
