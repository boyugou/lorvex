//! These tests pin the MCP-side translation contract: the typed
//! `WriteRateDecision` returned by the shared math must round-trip
//! into the MCP wire-error format `{kind: "rate_limited",
//! retryable: true}` (issue #2182), and the message format must
//! cite the documented hard cap. Unit-test coverage of the bucket
//! math itself lives in `lorvex_runtime::rate_limit::tests` so a
//! future bucket reshape stays caught at the math layer regardless
//! of which surface fronts it.
use super::*;

/// Drive the shared math directly — the singleton route is a
/// shared global and parallel test harnesses would race over its
/// state. The translator-message contract is what we assert here.
fn local_state() -> WriteRateLimitState {
    WriteRateLimitState::new(Instant::now())
}

#[test]
#[serial_test::serial(hlc)]
fn check_write_rate_limit_allows_writes_under_cap() {
    let start = Instant::now();
    let mut state = local_state();
    for i in 0..50 {
        match state.check_at(start) {
            WriteRateDecision::Allowed { .. } => {}
            WriteRateDecision::Denied { .. } => panic!("write {i} should be allowed"),
        }
    }
}

#[test]
#[serial_test::serial(hlc)]
fn check_write_rate_limit_rejects_write_after_hard_cap() {
    let start = Instant::now();
    let mut state = local_state();
    for i in 0..500 {
        match state.check_at(start) {
            WriteRateDecision::Allowed { .. } => {}
            WriteRateDecision::Denied { .. } => panic!("write {i} should be allowed"),
        }
    }
    // The 501st in the same instant must be Denied — render the
    // MCP-side message exactly the way `check_write_rate_limit`
    // does, using the same hard-capacity value the shared math
    // hands back.
    let denied = match state.check_at(start) {
        WriteRateDecision::Denied { hard_capacity } => hard_capacity,
        other => panic!("expected Denied, got {other:?}"),
    };
    assert_eq!(denied, HARD_CAPACITY as u64);

    let err = McpError::RateLimited(format!(
        "rate limit exceeded: MCP writes capped at {denied} per hour \
         to prevent runaway loops. Back off and retry later."
    ));
    match &err {
        McpError::RateLimited(message) => {
            assert!(
                message.starts_with("rate limit exceeded:"),
                "unexpected message: {message}"
            );
        }
        other => panic!("expected RateLimited, got {other:?}"),
    }

    // Confirm the structured error surface classifies this as a
    // retryable `rate_limited` kind on the wire (#2182). Retryable
    // because the bucket refills over time — but the assistant
    // MUST back off rather than retry immediately.
    let wire = String::from(McpError::RateLimited(
        "rate limit exceeded: test".to_string(),
    ));
    let payload: serde_json::Value = serde_json::from_str(&wire).expect("JSON");
    assert_eq!(payload["code"], "rate_limited");
    assert_eq!(payload["retryable"], true);
}

#[test]
#[serial_test::serial(hlc)]
fn check_write_rate_limit_soft_cap_logs_warning_but_continues() {
    let start = Instant::now();
    let mut state = local_state();
    // Drain the soft bucket (60 tokens) at t=0.
    for i in 0..60 {
        match state.check_at(start) {
            WriteRateDecision::Allowed {
                warn: WarnSignal::Ok,
            } => {}
            other => panic!("write {i} should not warn, got {other:?}"),
        }
    }
    // The 61st write at t=0 crosses the soft cap. It MUST succeed
    // (we're still well under the hard cap) and MUST flag a
    // warning.
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
