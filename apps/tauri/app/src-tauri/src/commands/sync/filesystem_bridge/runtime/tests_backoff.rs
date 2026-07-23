use super::tests_support::*;
use super::*;

#[test]
fn should_skip_outbox_for_backoff_skips_exhausted_rows() {
    let now = chrono::Utc::now();
    let entry = outbox_entry_fixture(outbox::MAX_RETRIES, None);
    assert!(
        should_skip_outbox_for_backoff(&entry, &now),
        "rows at MAX_OUTBOX_RETRIES must be permanently skipped"
    );
}

#[test]
fn should_skip_outbox_for_backoff_skips_rows_still_inside_wait_window() {
    let now = chrono::Utc::now();
    let retry_at = lorvex_domain::format_sync_timestamp(now);
    let entry = outbox_entry_fixture(1, Some(&retry_at));
    assert!(
        should_skip_outbox_for_backoff(&entry, &now),
        "freshly retried rows must honor backoff before another push attempt"
    );
}

#[test]
fn should_skip_outbox_for_backoff_allows_retry_after_wait_window_or_bad_timestamp() {
    let now = chrono::Utc::now();
    let old_retry = lorvex_domain::format_sync_timestamp(now - chrono::Duration::hours(2));
    let old_entry = outbox_entry_fixture(1, Some(&old_retry));
    assert!(
        !should_skip_outbox_for_backoff(&old_entry, &now),
        "rows whose backoff window elapsed should be retried"
    );

    let malformed_entry = outbox_entry_fixture(1, Some("not-a-timestamp"));
    assert!(
        !should_skip_outbox_for_backoff(&malformed_entry, &now),
        "malformed retry timestamps should not wedge the row behind backoff forever"
    );
}

#[test]
fn outbox_backoff_jitter_is_symmetric_around_deterministic() {
    use std::collections::HashSet;

    // retry_count = 4 → deterministic = min(30 * 2^3, 3600) = 240,
    // jitter_range = 24, so valid outputs ∈ [216, 264].
    let retry_count = 4_i64;
    let deterministic = 240_i64;
    let jitter_range = 24_i64;
    let lo = deterministic - jitter_range;
    let hi = deterministic + jitter_range;

    let mut observed = HashSet::new();
    let mut saw_below = false;
    let mut saw_above = false;
    // 5_000 samples is plenty: jitter_range*2+1 = 49, so by birthday
    // bound we'd see all 49 outputs in O(50 * log(50)) ≈ 200 draws.
    // 5k gives the test fully deterministic asymmetry coverage.
    for _ in 0..5_000 {
        let v = super::outbox_backoff_seconds(retry_count);
        assert!(v >= lo && v <= hi, "{v} outside [{lo}, {hi}]");
        observed.insert(v);
        if v < deterministic {
            saw_below = true;
        }
        if v > deterministic {
            saw_above = true;
        }
    }
    assert!(saw_below, "jitter never went below the deterministic value");
    assert!(saw_above, "jitter never went above the deterministic value");
    // Sanity: we hit at least half the discrete output points.
    assert!(
        observed.len() >= ((jitter_range * 2 + 1) / 2) as usize,
        "jitter hit only {} of ~{} possible values — distribution still skewed",
        observed.len(),
        jitter_range * 2 + 1,
    );
}
