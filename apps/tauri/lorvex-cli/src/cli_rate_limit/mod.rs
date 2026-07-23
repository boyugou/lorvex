//! Per-process write rate-limiting for the `lorvex` CLI (round-3 audit
//! finding #2 — the agent-first companion to #2364).
//!
//! Context: the CLI exposes the SAME write surface as the MCP server
//! (`batch_create_tasks`, `batch_update_tasks`, every
//! `lorvex tasks ...` mutation, lifecycle ops, etc.), targeted at the
//! same agent-first audience. A runaway agent shelling out to
//! `lorvex tasks update …` in a tight loop would burn CPU, fill the
//! outbox faster than sync drains it, and pollute `ai_changelog` with
//! noise — exactly the failure mode the MCP-side limiter exists to
//! prevent. The CLI funnel `log_cli_changelog_inner` (in
//! `crate::commands::shared::effects`) routes every CLI write
//! through this module's preamble for the equivalent backpressure.
//!
//! ## Shape — same as MCP, by design
//!
//! - **Soft cap — 60 writes/minute.** Over the soft rate we emit a
//!   single `cli_log!(Warn, …)` per crossing and let the write
//!   through. The soft cap surfaces "the agent is busier than
//!   expected" without disrupting legitimate batch operations
//!   (`lorvex tasks batch-create` from a script writing 50 tasks at
//!   once).
//! - **Hard cap — 500 writes/hour.** Over the hard rate we reject the
//!   write with [`CliError::Validation`] and the same "rate limit
//!   exceeded: …" prefix the MCP error carries. The CLI's exit-code
//!   classifier maps `Validation` to EX_DATAERR (65); the rejection
//!   message is what tells the agent "back off, don't blindly retry."
//!
//! ## Independent state from the MCP server
//!
//! Both surfaces wrap [`lorvex_runtime::WriteRateLimitState`] in their
//! own `OnceLock<Mutex<…>>` static — the CLI runs in a separate process
//! from the MCP server, so a shared bucket would either need IPC (which
//! there is no infrastructure for) or a persistent SQLite-backed
//! limiter (out of scope for the audit finding). Per-process buckets
//! reset on each `lorvex …` invocation; the typical agent footprint
//! (one short-lived CLI invocation per shell-out) means the CLI
//! limiter mostly catches a runaway loop within one `lorvex` process,
//! which is exactly when the limiter matters most.
//!
//! ## Soft warning channel
//!
//! The MCP server emits the soft-cap warning via `tracing::warn!`
//! because the Tauri parent captures the structured stderr stream
//! (#3035-M9). The CLI does not have a `tracing-subscriber`
//! initialized — verbosity routing goes through the
//! `cli_log!(Warn, …)` macro in `crate::verbosity`, which writes to
//! stderr at the `Warn` level (the default). Both surfaces reach the
//! same operational outcome: a single warning line per over-soft
//! crossing, suppressed across subsequent over-soft writes until the
//! bucket recovers.
//!
//! ## `LORVEX_AGENT_NAME` does NOT gate the limiter
//!
//! Note that `LORVEX_AGENT_NAME` is consulted by `resolve_cli_actor_name`
//! (in `crate::commands::shared::effects`) for `ai_changelog.initiated_by` attribution
//! — it does NOT scope the limiter. Every CLI write goes through the
//! same bucket regardless of who ran the command, because the runaway
//! risk is the same: a misconfigured `lorvex` invocation in any
//! shell-out loop produces the same outbox pressure as a tight MCP
//! tool-call loop. Suppressing the limiter for "interactive humans"
//! would require a heuristic (TTY check? subcommand allowlist?) that
//! could be defeated by the very shell-out pattern we're trying to
//! catch. The shared cap is generous enough (60/min, 500/hr) that
//! interactive humans never see a warning — see the
//! `tokens_refill_over_time` test in
//! `lorvex_runtime::rate_limit::tests` for the recovery curve. If
//! a future iteration ever wants per-actor scoping, it lifts cleanly
//! into a `HashMap<String, WriteRateLimitState>` keyed on the resolved
//! actor name; the math itself stays unchanged.

use crate::error::CliError;
use crate::verbosity::cli_log;
use lorvex_runtime::{WarnSignal, WriteRateDecision, WriteRateLimitState, SOFT_CAPACITY};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

#[cfg(test)]
use lorvex_runtime::HARD_CAPACITY;

/// Process-wide limiter for the `lorvex` CLI binary. One CLI
/// invocation = one process = one shared bucket pair across whatever
/// subcommand sequence the agent issues. Lazily initialized so the
/// first write's `Instant::now()` becomes `t=0` for the bucket.
static CLI_RATE_LIMIT: OnceLock<Mutex<WriteRateLimitState>> = OnceLock::new();

fn limiter() -> &'static Mutex<WriteRateLimitState> {
    CLI_RATE_LIMIT.get_or_init(|| Mutex::new(WriteRateLimitState::new(Instant::now())))
}

/// Check whether the calling write is allowed under the CLI process'
/// rate caps. Call this from the top of every CLI logged-write path —
/// `log_cli_changelog_inner` (in `crate::commands::shared::effects`) is the canonical
/// chokepoint, so a single call there covers task, list, habit,
/// memory, focus, calendar, and preference mutations.
///
/// Rejected writes return [`CliError::Validation`] so the existing
/// exit-code classifier maps them to EX_DATAERR (65).
/// MCP-side rejection used a typed `RateLimited` kind that the CLI's
/// JSON-error renderer also surfaces; the CLI shell mirrors that
/// shape on the rejection-message prefix while keeping the local
/// variant simple — the CLI does not yet have a dedicated
/// `RateLimited` variant because the message contract is already
/// stable across both surfaces and the exit-code mapping is the
/// reader-visible behavior.
pub(crate) fn check_cli_write_rate_limit() -> Result<(), CliError> {
    let mut guard = limiter()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    match guard.check_at(Instant::now()) {
        WriteRateDecision::Allowed { warn } => {
            if matches!(warn, WarnSignal::FirstSoftCapCrossing) {
                cli_log!(
                    Warn,
                    "CLI write rate-limit soft cap crossed (soft_capacity={}, window_secs=60); continuing",
                    SOFT_CAPACITY as u64,
                );
            }
            Ok(())
        }
        WriteRateDecision::Denied { hard_capacity } => Err(CliError::Validation(format!(
            "rate limit exceeded: CLI writes capped at {hard_capacity} per hour \
             to prevent runaway loops. Back off and retry later."
        ))),
    }
}

/// Test-only hook to reset the process-wide CLI rate-limit state so a
/// hammer-test that drains the bucket cannot poison every subsequent
/// CLI test in the same `cargo test` process. The production code
/// path NEVER calls this — buckets reset on process exit, which is
/// the only correct refresh trigger for a real `lorvex` invocation.
///
/// Tests that exhaust the limiter (e.g.
/// `cli_rate_limit_funnel_rejects_after_hard_cap`) MUST call this in
/// a test fixture (typically alongside the HLC test mutex acquire) so
/// the global singleton stays reusable across the test suite.
#[cfg(test)]
pub(crate) fn reset_for_tests() {
    let mut guard = limiter()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *guard = WriteRateLimitState::new(Instant::now());
}

#[cfg(test)]
mod tests;
