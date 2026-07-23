use super::*;

/// Verify sync_timestamp_now() produces timestamps compatible with string-based
/// LWW comparison. The format must be:
/// - Fixed millisecond precision (3 decimal places)
/// - UTC "Z" suffix (not "+00:00")
/// - Lexicographic ordering matches temporal ordering
///
/// This prevents the timestamp format mismatch bug fixed in 06928259 from regressing.
#[test]
fn sync_timestamp_now_format_is_millisecond_z_suffix() {
    let ts = sync_timestamp_now();

    // Must end with Z (not +00:00)
    assert!(
        ts.ends_with('Z'),
        "sync_timestamp_now must use Z suffix, got: {ts}"
    );

    // Must have exactly 3 decimal places (millisecond precision)
    let dot_pos = ts.rfind('.').expect("timestamp must have decimal point");
    let z_pos = ts.rfind('Z').expect("timestamp must have Z suffix");
    let decimal_digits = z_pos - dot_pos - 1;
    assert_eq!(
        decimal_digits, 3,
        "sync_timestamp_now must have 3 decimal places (millisecond), got {decimal_digits} in: {ts}"
    );
}

/// Verify that two timestamps produced by sync_timestamp_now() in sequence
/// are lexicographically ordered (newer > older).
#[test]
fn sync_timestamps_are_lexicographically_ordered() {
    // Poll until the clock advances past t1. `sync_timestamp_now` has no
    // monotonicity counter (it just reads Utc::now()), so on a coarse
    // scheduler (Windows 15.6ms tick) a fixed thread::sleep(1ms) can
    // return with Utc::now() unchanged. Loop with a generous wall-clock
    // budget instead.
    let t1 = sync_timestamp_now();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
    let t2 = loop {
        let t = sync_timestamp_now();
        if t > t1 {
            break t;
        }
        if std::time::Instant::now() >= deadline {
            panic!("sync_timestamp_now did not advance within 2s: t1={t1}, last={t}");
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    };

    assert!(
        t2 > t1,
        "Later timestamp must sort after earlier: t1={t1}, t2={t2}"
    );
}
