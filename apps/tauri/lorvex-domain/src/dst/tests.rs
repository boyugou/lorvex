use super::*;
use chrono::NaiveDate;

fn ny() -> Tz {
    "America/New_York"
        .parse()
        .expect("chrono-tz has America/New_York")
}

fn naive(date: (i32, u32, u32), time: (u32, u32, u32)) -> NaiveDateTime {
    NaiveDate::from_ymd_opt(date.0, date.1, date.2)
        .expect("valid date")
        .and_hms_opt(time.0, time.1, time.2)
        .expect("valid time")
}

#[test]
fn resolve_local_datetime_returns_valid_for_normal_time() {
    // 2026-04-18 09:00 New_York is an ordinary weekday morning.
    let input = naive((2026, 4, 18), (9, 0, 0));
    let result = resolve_local_datetime(ny(), input);
    match result {
        DstResolution::Valid(dt) => {
            assert_eq!(dt.naive_local(), input);
            // EDT offset in April = UTC-4 → 09:00 local = 13:00 UTC.
            assert_eq!(
                dt.with_timezone(&chrono::Utc)
                    .format("%Y-%m-%dT%H:%M:%SZ")
                    .to_string(),
                "2026-04-18T13:00:00Z",
            );
        }
        other => panic!("expected Valid, got {other:?}"),
    }
}

#[test]
fn resolve_local_datetime_returns_ambiguous_for_fall_back() {
    // 2026-11-01 01:30 New_York is the fall-back ambiguity:
    // 01:30 EDT (UTC-4) happens first, then the clock rewinds to
    // 01:00 EST (UTC-5) and 01:30 EST happens again.
    let input = naive((2026, 11, 1), (1, 30, 0));
    let result = resolve_local_datetime(ny(), input);
    match result {
        DstResolution::Ambiguous { earlier, later } => {
            let earlier_utc = earlier
                .with_timezone(&chrono::Utc)
                .format("%Y-%m-%dT%H:%M:%SZ")
                .to_string();
            let later_utc = later
                .with_timezone(&chrono::Utc)
                .format("%Y-%m-%dT%H:%M:%SZ")
                .to_string();
            assert_eq!(earlier_utc, "2026-11-01T05:30:00Z");
            assert_eq!(later_utc, "2026-11-01T06:30:00Z");
        }
        other => panic!("expected Ambiguous, got {other:?}"),
    }
}

#[test]
fn resolve_local_datetime_returns_skipped_for_spring_forward_gap() {
    // 2026-03-08 02:30 New_York falls in the spring-forward gap
    // (clocks jump 02:00 EST → 03:00 EDT). That wall clock does
    // not exist on that date.
    let input = naive((2026, 3, 8), (2, 30, 0));
    let result = resolve_local_datetime(ny(), input);
    match result {
        DstResolution::Skipped {
            requested,
            snapped_to,
        } => {
            assert_eq!(requested, input);
            // Snapping 15m at a time from 02:30 lands at 03:00 EDT
            // after four steps, which is 07:00 UTC.
            let snapped_utc = snapped_to
                .with_timezone(&chrono::Utc)
                .format("%Y-%m-%dT%H:%M:%SZ")
                .to_string();
            assert_eq!(snapped_utc, "2026-03-08T07:00:00Z");
        }
        other => panic!("expected Skipped, got {other:?}"),
    }
}
