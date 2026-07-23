//! Per-session write rate-limiting for the MCP server (#2364).
//!
//! Context: the MCP write path is the assistant's primary interface, and a
//! runaway model — stuck in a delete/create loop, iterating over batches
//! without making progress, or simply misconfigured — can issue thousands
//! of writes per second. Those writes hit `log_change`,
//! each one stamping an HLC, pushing to the outbox, and writing a
//! changelog row. There is no natural backpressure on the stdio transport
//! beyond the single writer Mutex: a runaway assistant burns CPU, fills
//! the outbox faster than sync can drain it, and pollutes the user's
//! changelog with noise.
//!
//! This module adds a two-tier token-bucket limiter on writes:
//!
//! - **Soft cap — 60 writes/minute.** Over the soft rate we log a single
//!   warning per crossing and let the write through. The soft cap exists
//!   to surface "the assistant is busier than expected" in logs without
//!   disrupting legitimate batch operations.
//! - **Hard cap — 500 writes/hour.** Over the hard rate we reject the
//!   write with [`McpError::RateLimited`] ("rate limit exceeded: …"). The
//!   error flows through the structured-error contract (#2182) as
//!   `{kind: "rate_limited", retryable: true}` — the assistant should
//!   back off, not blindly retry.
//!
//! Both caps are implemented as classic token buckets that refill at a
//! constant rate: the soft bucket refills one token per second, the hard
//! bucket refills one token every 7.2 seconds. A write consumes one
//! token from each bucket.
//!
//! **In-memory only.** Counters live in a per-process `Mutex` and reset
//! on MCP server restart. That matches the scope of the fix: a session
//! is "one stdio connection", and buckets reset naturally when the
//! client reconnects. A persisted limiter would need a schema and a
//! user-preference override (out of scope for #2364).
//!
//! **Architectural parallel.** `server_cancellation` exposes a single
//! helper called from write handlers at logical step boundaries. The
//! rate limiter uses the same shape: [`check_write_rate_limit`] is
//! called once from the `log_change` preamble, so every
//! logged write is counted regardless of which tool emitted it.
//!
//! ## Cross-surface alignment (round-3 audit finding #2)
//!
//! The bucket math + state struct was lifted into
//! `lorvex_runtime::rate_limit` so the agent-first CLI funnel
//! (`log_cli_changelog_inner` in `lorvex-cli/src/commands/shared/effects/mod.rs`)
//! can enforce the same shape (60/min soft, 500/hr hard) without
//! drift. The MCP server and the CLI keep INDEPENDENT
//! `OnceLock<Mutex<…>>` singletons — they're separate processes with
//! separate token budgets. This file is now a thin translator between
//! the typed [`WriteRateDecision`] and the MCP wire-error contract.

use crate::error::McpError;
use lorvex_runtime::{WarnSignal, WriteRateDecision, WriteRateLimitState, SOFT_CAPACITY};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

#[cfg(test)]
use lorvex_runtime::HARD_CAPACITY;

/// Process-wide limiter. One stdio MCP server = one session, so a single
/// global bucket pair covers the whole session. Lazily initialized so
/// the first write's `Instant::now()` becomes `t=0` for the bucket.
static RATE_LIMIT: OnceLock<Mutex<WriteRateLimitState>> = OnceLock::new();

fn limiter() -> &'static Mutex<WriteRateLimitState> {
    RATE_LIMIT.get_or_init(|| Mutex::new(WriteRateLimitState::new(Instant::now())))
}

/// Check whether the calling write is allowed under the session's
/// rate caps. Call this from the top of every logged-write path —
/// `log_change` is the canonical chokepoint, so a
/// single call there covers task, list, habit, memory, and preference
/// mutations.
pub(crate) fn check_write_rate_limit() -> Result<(), McpError> {
    let mut guard = limiter()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    match guard.check_at(Instant::now()) {
        WriteRateDecision::Allowed { warn } => {
            if matches!(warn, WarnSignal::FirstSoftCapCrossing) {
                tracing::warn!(
                    soft_capacity = SOFT_CAPACITY as u64,
                    window_secs = 60_u64,
                    "MCP write rate-limit soft cap crossed; continuing"
                );
            }
            Ok(())
        }
        WriteRateDecision::Denied { hard_capacity } => Err(McpError::RateLimited(format!(
            "rate limit exceeded: MCP writes capped at {hard_capacity} per hour \
             to prevent runaway loops. Back off and retry later."
        ))),
    }
}

#[cfg(test)]
mod tests;
