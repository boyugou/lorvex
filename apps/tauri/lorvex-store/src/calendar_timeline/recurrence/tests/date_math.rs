use super::*;

#[test]
fn add_months_clamped_basic() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 15).unwrap();
    assert_eq!(
        add_months_clamped(base, 1, 15),
        Some(NaiveDate::from_ymd_opt(2026, 2, 15).unwrap())
    );
}

#[test]
fn add_months_clamped_feb_clamp() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 31).unwrap();
    assert_eq!(
        add_months_clamped(base, 1, 31),
        Some(NaiveDate::from_ymd_opt(2026, 2, 28).unwrap())
    );
}

#[test]
fn add_months_clamped_target_day_anchor() {
    // Even when base is Feb 28 (clamped from 31), target_day=31 restores.
    let base = NaiveDate::from_ymd_opt(2026, 2, 28).unwrap();
    assert_eq!(
        add_months_clamped(base, 1, 31),
        Some(NaiveDate::from_ymd_opt(2026, 3, 31).unwrap())
    );
}

// -----------------------------------------------------------------------
// weekly_target_dows

#[test]
fn overlaps_range_identical() {
    let from = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let to = NaiveDate::from_ymd_opt(2026, 3, 31).unwrap();
    assert!(overlaps_calendar_range(from, to, from, to));
}

#[test]
fn overlaps_range_no_overlap() {
    let from = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let to = NaiveDate::from_ymd_opt(2026, 3, 31).unwrap();
    assert!(!overlaps_calendar_range(
        NaiveDate::from_ymd_opt(2026, 4, 1).unwrap(),
        NaiveDate::from_ymd_opt(2026, 4, 30).unwrap(),
        from,
        to,
    ));
}

#[test]
fn overlaps_range_single_day_boundary() {
    let from = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let to = NaiveDate::from_ymd_opt(2026, 3, 31).unwrap();
    // Event ends on from day — should still overlap.
    assert!(overlaps_calendar_range(
        NaiveDate::from_ymd_opt(2026, 2, 28).unwrap(),
        from,
        from,
        to,
    ));
    // Event starts on to day — should still overlap.
    assert!(overlaps_calendar_range(to, to, from, to));
}

#[test]
fn overlaps_range_entirely_before() {
    let from = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let to = NaiveDate::from_ymd_opt(2026, 3, 31).unwrap();
    assert!(!overlaps_calendar_range(
        NaiveDate::from_ymd_opt(2026, 2, 1).unwrap(),
        NaiveDate::from_ymd_opt(2026, 2, 28).unwrap(),
        from,
        to,
    ));
}

// -----------------------------------------------------------------------
