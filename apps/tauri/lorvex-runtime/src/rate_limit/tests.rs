use super::*;
use std::time::Duration;

#[test]
fn allows_writes_under_cap() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // 50 writes at t=0 are well under both caps.
    for i in 0..50 {
        match state.check_at(start) {
            WriteRateDecision::Allowed { .. } => {}
            WriteRateDecision::Denied { .. } => panic!("write {i} should be allowed"),
        }
    }
}

#[test]
fn rejects_write_after_hard_cap() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // 500 writes at t=0 drain the hard bucket exactly.
    for i in 0..500 {
        match state.check_at(start) {
            WriteRateDecision::Allowed { .. } => {}
            WriteRateDecision::Denied { .. } => panic!("write {i} should be allowed"),
        }
    }
    // The 501st in the same instant must be Denied.
    match state.check_at(start) {
        WriteRateDecision::Denied { hard_capacity } => {
            assert_eq!(hard_capacity, HARD_CAPACITY as u64);
        }
        other => panic!("expected Denied, got {other:?}"),
    }
}

#[test]
fn soft_cap_emits_warn_signal_but_continues() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the soft bucket (60 tokens) at t=0.
    for i in 0..60 {
        match state.check_at(start) {
            WriteRateDecision::Allowed {
                warn: WarnSignal::Ok,
            } => {}
            other => panic!("write {i} should not warn, got {other:?}"),
        }
    }
    // The 61st write at t=0 crosses the soft cap. It MUST be
    // Allowed (we're still well under the hard cap) and MUST flag
    // a warning.
    match state.check_at(start) {
        WriteRateDecision::Allowed {
            warn: WarnSignal::FirstSoftCapCrossing,
        } => {}
        other => panic!("first over-soft write must flag a warning, got {other:?}"),
    }
    // The 62nd write still over-soft: warning latch prevents spam,
    // and the write still succeeds.
    match state.check_at(start) {
        WriteRateDecision::Allowed {
            warn: WarnSignal::Ok,
        } => {}
        other => panic!("subsequent over-soft writes must not re-warn, got {other:?}"),
    }
}

#[test]
fn tokens_refill_over_time() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the hard bucket completely.
    for _ in 0..500 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed { .. }
        ));
    }
    // At t=0 the next write is Denied.
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Denied { .. }
    ));

    // Advance 60 seconds of synthetic time: that's 60 * 0.1389 ≈
    // 8.33 refilled hard tokens, and 60 * 1.0 = 60 refilled soft
    // tokens (capped at 60). So a write 60s later must succeed.
    let later = start + Duration::from_secs(60);
    assert!(matches!(
        state.check_at(later),
        WriteRateDecision::Allowed { .. }
    ));

    // Drain the remaining refilled hard tokens to re-starve the
    // bucket.
    let mut consumed = 1;
    while matches!(state.check_at(later), WriteRateDecision::Allowed { .. }) {
        consumed += 1;
        assert!(
            consumed <= 20,
            "hard bucket should not refill past ~9 tokens after 60s"
        );
    }
    assert!(
        (7..=10).contains(&consumed),
        "expected ~8 writes allowed after 60s of refill, got {consumed}"
    );

    // Another hour of synthetic time fully refills the hard
    // bucket.
    let much_later = start + Duration::from_secs(60 + 3600);
    for i in 0..500 {
        match state.check_at(much_later) {
            WriteRateDecision::Allowed { .. } => {}
            WriteRateDecision::Denied { .. } => {
                panic!("post-refill write {i} should succeed")
            }
        }
    }
    assert!(
        matches!(state.check_at(much_later), WriteRateDecision::Denied { .. }),
        "hard bucket should re-exhaust after 500 writes"
    );
}

#[test]
fn soft_warning_rearms_after_bucket_recovers() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the soft bucket and cross the threshold once.
    for _ in 0..60 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed { .. }
        ));
    }
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Allowed {
            warn: WarnSignal::FirstSoftCapCrossing
        }
    ));
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Allowed {
            warn: WarnSignal::Ok
        }
    ));

    // 90 seconds later the soft bucket is fully recovered.
    let later = start + Duration::from_secs(90);
    // First write consumes a token from the refilled bucket: no
    // warn. This also clears the warning latch since the consume
    // succeeded.
    assert!(matches!(
        state.check_at(later),
        WriteRateDecision::Allowed {
            warn: WarnSignal::Ok
        }
    ));

    // Drain again and confirm a second spike produces a fresh
    // warning.
    for _ in 0..59 {
        assert!(matches!(
            state.check_at(later),
            WriteRateDecision::Allowed { .. }
        ));
    }
    assert!(matches!(
        state.check_at(later),
        WriteRateDecision::Allowed {
            warn: WarnSignal::FirstSoftCapCrossing
        }
    ));
}

/// Regression for NA8: pre-fix the latch reset was guarded by
/// `self.soft.tokens >= 1.0` AFTER the consume, equivalent to
/// "bucket held 2+ tokens before the consume". A trickle refill —
/// exactly 1 token, consumed immediately — left the latch armed,
/// and a subsequent burst over the cap produced no further warning
/// even though it was a fresh stress episode. Rearm on every
/// successful consume so each over-cap burst gets its own
/// warning.
#[test]
fn soft_warning_rearms_when_only_one_token_refilled() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the soft bucket and warn once.
    for _ in 0..60 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed { .. }
        ));
    }
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Allowed {
            warn: WarnSignal::FirstSoftCapCrossing
        }
    ));

    // Refill exactly 1 token. Pre-fix this single token would be
    // consumed immediately, leaving post-consume tokens at 0 —
    // NOT >= 1, so the latch stayed stuck at `true`.
    let one_token_later = start + Duration::from_secs(1);
    assert!(
        matches!(
            state.check_at(one_token_later),
            WriteRateDecision::Allowed {
                warn: WarnSignal::Ok
            }
        ),
        "single-token refill should consume cleanly"
    );

    // Hammer the bucket again immediately. The first failure of
    // this burst MUST warn — pre-fix it returned `Ok` because the
    // latch was still armed from the previous burst.
    assert!(
        matches!(
            state.check_at(one_token_later),
            WriteRateDecision::Allowed {
                warn: WarnSignal::FirstSoftCapCrossing
            }
        ),
        "second over-cap burst must produce its own warning",
    );
}

/// Hard-cap rejection MUST NOT advance the soft-cap latch — once
/// the hard bucket is empty, retries of the same rejected write
/// would otherwise re-trigger the soft warn every time.
#[test]
fn hard_cap_rejection_does_not_disturb_soft_state() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the hard bucket. Soft bucket goes to 0 too (hard
    // capacity > soft capacity, so the soft bucket bottoms out
    // first), and the soft latch will fire once at write 61.
    for _ in 0..60 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed {
                warn: WarnSignal::Ok
            }
        ));
    }
    // Write 61 crosses the soft cap and warns.
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Allowed {
            warn: WarnSignal::FirstSoftCapCrossing
        }
    ));
    // Drain the rest of the hard bucket (writes 62..500). All
    // should be over-soft but already-warned.
    for _ in 62..=500 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed {
                warn: WarnSignal::Ok
            }
        ));
    }
    // Now the hard bucket is empty.
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Denied { .. }
    ));
    // A second hard-cap rejection should still be Denied — and
    // the soft latch is unchanged: when the hard bucket is empty
    // we never even check the soft bucket, so we cannot
    // accidentally rearm or refire the soft warn.
    assert!(matches!(
        state.check_at(start),
        WriteRateDecision::Denied { .. }
    ));
}
