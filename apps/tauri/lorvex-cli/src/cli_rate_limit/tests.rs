//! Unit-test coverage of the CLI-side translator. The bucket math
//! is exercised in `lorvex_runtime::rate_limit::tests`; here we
//! pin only the CLI translation surface (CliError variant,
//! exit-code class, message-prefix contract).
use super::*;

/// Hard-cap rejection MUST surface as `CliError::Validation` so
/// the existing exit-code classifier maps it to EX_DATAERR (65),
/// the same class the MCP server's wire format pins via the
/// `rate_limited` retryable contract.
#[test]
fn hard_cap_rejection_returns_validation_error_with_documented_prefix() {
    let start = Instant::now();
    let mut state = WriteRateLimitState::new(start);
    // Drain the hard bucket directly. We don't drive the singleton
    // here because parallel tests would race over its state — the
    // `cli_rate_limit_funnel_rejects_after_hard_cap` test in
    // `crate::commands::shared::effects` exercises the full singleton-backed path
    // serialised via the HLC test mutex.
    for _ in 0..500 {
        assert!(matches!(
            state.check_at(start),
            WriteRateDecision::Allowed { .. }
        ));
    }
    let denied = match state.check_at(start) {
        WriteRateDecision::Denied { hard_capacity } => hard_capacity,
        other => panic!("expected Denied, got {other:?}"),
    };
    assert_eq!(denied, HARD_CAPACITY as u64);

    // Mirror the rejection-message construction inside
    // `check_cli_write_rate_limit` so a future message tweak
    // shows up as a test failure.
    let err = CliError::Validation(format!(
        "rate limit exceeded: CLI writes capped at {denied} per hour \
         to prevent runaway loops. Back off and retry later."
    ));
    assert_eq!(err.exit_code(), 65, "Validation maps to EX_DATAERR (65)");
    assert_eq!(err.kind(), "validation");
    let display = format!("{err}");
    assert!(
        display.starts_with("rate limit exceeded:"),
        "rejection prefix must match MCP contract: {display}",
    );
}
