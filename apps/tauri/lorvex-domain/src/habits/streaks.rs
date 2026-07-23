use chrono::{Datelike, NaiveDate};
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HabitStreakFrequency {
    Daily,
    Weekly,
    Monthly,
}

impl HabitStreakFrequency {
    pub fn from_wire_str(value: &str) -> Self {
        match value {
            "daily" => Self::Daily,
            "monthly" => Self::Monthly,
            // "weekly" and "times_per_week" both use weekly bucket logic.
            _ => Self::Weekly,
        }
    }
}

pub fn compute_habit_current_streak(
    dates: &[NaiveDate],
    today: NaiveDate,
    frequency: HabitStreakFrequency,
    target_count: i64,
) -> i64 {
    match frequency {
        HabitStreakFrequency::Daily => {
            let mut sorted = dates.to_vec();
            sorted.sort_unstable_by(|left, right| right.cmp(left));
            daily_current_streak(&sorted, today)
        }
        HabitStreakFrequency::Weekly => weekly_current_streak(dates, today, target_count),
        HabitStreakFrequency::Monthly => monthly_current_streak(dates, today, target_count),
    }
}

pub fn compute_habit_longest_streak(
    dates: &[NaiveDate],
    frequency: HabitStreakFrequency,
    target_count: i64,
) -> i64 {
    let mut sorted = dates.to_vec();
    sorted.sort_unstable();
    match frequency {
        HabitStreakFrequency::Daily => daily_longest_streak(&sorted),
        HabitStreakFrequency::Weekly => weekly_longest_streak(&sorted, target_count),
        HabitStreakFrequency::Monthly => monthly_longest_streak(&sorted, target_count),
    }
}

fn daily_current_streak(dates_desc: &[NaiveDate], today: NaiveDate) -> i64 {
    if dates_desc.is_empty() {
        return 0;
    }
    let days_since = (today - dates_desc[0]).num_days();
    if days_since > 1 {
        return 0;
    }
    let mut streak = 1_i64;
    for i in 1..dates_desc.len() {
        if (dates_desc[i - 1] - dates_desc[i]).num_days() == 1 {
            streak += 1;
        } else {
            break;
        }
    }
    streak
}

fn daily_longest_streak(dates_asc: &[NaiveDate]) -> i64 {
    if dates_asc.is_empty() {
        return 0;
    }
    let mut longest = 1_i64;
    let mut current = 1_i64;
    for i in 1..dates_asc.len() {
        if (dates_asc[i] - dates_asc[i - 1]).num_days() == 1 {
            current += 1;
            longest = longest.max(current);
        } else {
            current = 1;
        }
    }
    longest
}

fn weekly_current_streak(dates: &[NaiveDate], today: NaiveDate, target_count: i64) -> i64 {
    if dates.is_empty() {
        return 0;
    }

    let mut week_counts: HashMap<(i32, u32), i64> = HashMap::new();
    for &date in dates {
        let week = date.iso_week();
        *week_counts.entry((week.year(), week.week())).or_insert(0) += 1;
    }

    let target = target_count.max(1);
    let today_week = today.iso_week();
    let current_week_count = week_counts
        .get(&(today_week.year(), today_week.week()))
        .copied()
        .unwrap_or(0);
    let mut streak = i64::from(current_week_count >= target);

    let mut cursor =
        iso_week_start(today_week.year(), today_week.week()) - chrono::Duration::days(1);
    loop {
        let week = cursor.iso_week();
        let count = week_counts
            .get(&(week.year(), week.week()))
            .copied()
            .unwrap_or(0);
        if count < target {
            break;
        }
        streak += 1;
        cursor = iso_week_start(week.year(), week.week()) - chrono::Duration::days(1);
        if streak > 10_000 {
            break;
        }
    }
    streak
}

fn weekly_longest_streak(dates_asc: &[NaiveDate], target_count: i64) -> i64 {
    if dates_asc.is_empty() {
        return 0;
    }

    let mut week_counts: BTreeMap<(i32, u32), i64> = BTreeMap::new();
    for &date in dates_asc {
        let week = date.iso_week();
        *week_counts.entry((week.year(), week.week())).or_insert(0) += 1;
    }

    let target = target_count.max(1);
    let mut longest = 0_i64;
    let mut current = 0_i64;
    let mut prev_key: Option<(i32, u32)> = None;

    for (&(year, week), &count) in &week_counts {
        let is_consecutive = prev_key.is_some_and(|(prev_year, prev_week)| {
            let prev_start = iso_week_start(prev_year, prev_week);
            let this_start = iso_week_start(year, week);
            (this_start - prev_start).num_days() == 7
        });

        if count >= target {
            current = if is_consecutive { current + 1 } else { 1 };
            longest = longest.max(current);
        } else {
            current = 0;
        }
        prev_key = Some((year, week));
    }
    longest
}

fn monthly_current_streak(dates: &[NaiveDate], today: NaiveDate, target_count: i64) -> i64 {
    if dates.is_empty() {
        return 0;
    }

    let mut month_counts: HashMap<(i32, u32), i64> = HashMap::new();
    for &date in dates {
        *month_counts.entry((date.year(), date.month())).or_insert(0) += 1;
    }

    let target = target_count.max(1);
    let current_month_count = month_counts
        .get(&(today.year(), today.month()))
        .copied()
        .unwrap_or(0);
    let mut streak = i64::from(current_month_count >= target);

    let mut cursor = prev_month(today.year(), today.month());
    loop {
        let count = month_counts.get(&cursor).copied().unwrap_or(0);
        if count < target {
            break;
        }
        streak += 1;
        cursor = prev_month(cursor.0, cursor.1);
        if streak > 10_000 {
            break;
        }
    }
    streak
}

fn monthly_longest_streak(dates_asc: &[NaiveDate], target_count: i64) -> i64 {
    if dates_asc.is_empty() {
        return 0;
    }

    let mut month_counts: BTreeMap<(i32, u32), i64> = BTreeMap::new();
    for &date in dates_asc {
        *month_counts.entry((date.year(), date.month())).or_insert(0) += 1;
    }

    let target = target_count.max(1);
    let mut longest = 0_i64;
    let mut current = 0_i64;
    let mut prev_key: Option<(i32, u32)> = None;

    for (&(year, month), &count) in &month_counts {
        let is_consecutive = prev_key.is_some_and(|(prev_year, prev_month)| {
            next_month(prev_year, prev_month) == (year, month)
        });

        if count >= target {
            current = if is_consecutive { current + 1 } else { 1 };
            longest = longest.max(current);
        } else {
            current = 0;
        }
        prev_key = Some((year, month));
    }
    longest
}

const fn prev_month(year: i32, month: u32) -> (i32, u32) {
    if month == 1 {
        (year - 1, 12)
    } else {
        (year, month - 1)
    }
}

const fn next_month(year: i32, month: u32) -> (i32, u32) {
    if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    }
}

fn iso_week_start(year: i32, week: u32) -> NaiveDate {
    NaiveDate::from_isoywd_opt(year, week, chrono::Weekday::Mon)
        .unwrap_or_else(|| NaiveDate::from_ymd_opt(year, 1, 1).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use chrono::NaiveDate;

    use super::{compute_habit_current_streak, compute_habit_longest_streak, HabitStreakFrequency};

    fn d(value: &str) -> NaiveDate {
        NaiveDate::parse_from_str(value, "%Y-%m-%d").expect("valid test date")
    }

    #[test]
    fn daily_current_allows_today_or_yesterday_but_not_older() {
        assert_eq!(
            compute_habit_current_streak(
                &[d("2026-05-13"), d("2026-05-12"), d("2026-05-11")],
                d("2026-05-13"),
                HabitStreakFrequency::Daily,
                1,
            ),
            3,
        );
        assert_eq!(
            compute_habit_current_streak(
                &[d("2026-05-12"), d("2026-05-11")],
                d("2026-05-13"),
                HabitStreakFrequency::Daily,
                1,
            ),
            2,
        );
        assert_eq!(
            compute_habit_current_streak(
                &[d("2026-05-10"), d("2026-05-09")],
                d("2026-05-13"),
                HabitStreakFrequency::Daily,
                1,
            ),
            0,
        );
    }

    #[test]
    fn daily_longest_resets_on_skipped_days() {
        assert_eq!(
            compute_habit_longest_streak(
                &[
                    d("2026-05-01"),
                    d("2026-05-02"),
                    d("2026-05-04"),
                    d("2026-05-05"),
                    d("2026-05-06")
                ],
                HabitStreakFrequency::Daily,
                1,
            ),
            3,
        );
    }

    #[test]
    fn weekly_current_and_longest_use_iso_week_boundaries_and_target_count() {
        let dates = [
            d("2025-12-29"),
            d("2026-01-01"),
            d("2026-01-05"),
            d("2026-01-07"),
            d("2026-01-12"),
        ];

        assert_eq!(
            compute_habit_current_streak(&dates, d("2026-01-14"), HabitStreakFrequency::Weekly, 2),
            2,
        );
        assert_eq!(
            compute_habit_longest_streak(&dates, HabitStreakFrequency::Weekly, 2),
            2,
        );
    }

    #[test]
    fn monthly_current_and_longest_use_calendar_months_and_target_count() {
        let dates = [
            d("2025-12-01"),
            d("2025-12-15"),
            d("2026-01-03"),
            d("2026-01-20"),
            d("2026-03-01"),
            d("2026-03-02"),
        ];

        assert_eq!(
            compute_habit_current_streak(&dates, d("2026-03-13"), HabitStreakFrequency::Monthly, 2,),
            1,
        );
        assert_eq!(
            compute_habit_longest_streak(&dates, HabitStreakFrequency::Monthly, 2),
            2,
        );
    }
}
