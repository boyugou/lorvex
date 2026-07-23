//! Shared write rate-limiter math for agent-targeted Lorvex surfaces
//! (#2364 round-3 audit finding #2).
//!
//! ## Why this module exists
//!
//! Both the MCP server and the agent-first CLI expose the same write
//! surface (`batch_create_tasks`, `batch_update_tasks`, every
//! `lorvex tasks ...` mutation, lifecycle ops, etc.) to the same
//! audience the limiter exists to protect against — assistants stuck
//! in loops, batched without progress checks, or simply misconfigured.
//! The MCP server gates every write through
//! `log_change_and_enqueue_sync` with [`check_write_rate_limit`]
//! (`mcp-server/src/runtime/rate_limit/mod.rs`); the CLI funnel
//! `log_cli_changelog_inner` (lorvex-cli/src/db_ops/shared.rs) had no
//! equivalent backpressure. A runaway agent shelling out to
//! `lorvex tasks update ...` in a tight loop would burn CPU, fill the
//! outbox faster than sync drains it, and pollute `ai_changelog` with
//! noise.
//!
//! The fix is NOT to share the limiter state across processes — the
//! MCP server and the CLI are independent processes with independent
//! token budgets. The fix is to share the BUCKET MATH so both surfaces
//! enforce the same shape (60/min soft warn, 500/hr hard cap), keep
//! identical refill semantics, and stay in lockstep when one of the
//! caps changes. Each binary owns its own `OnceLock<Mutex<…>>` static
//! and translates the typed [`WriteRateDecision`] into its surface's
//! native error / log channel.
//!
//! ## What lives here
//!
//! - [`WriteRateLimitState`] — the per-process token-bucket state
//!   (one soft bucket, one hard bucket, plus a soft-warn latch).
//! - [`WriteRateDecision`] — the typed outcome returned by
//!   [`WriteRateLimitState::check_at`]. Allowed writes carry a
//!   [`WarnSignal`] telling the caller whether to emit the soft-cap
//!   warning; denied writes carry the documented hard-cap rate so the
//!   surface can render the message without re-typing the constant.
//! - [`WarnSignal`] — `Ok` (no warning) vs.
//!   `FirstSoftCapCrossing` (caller should emit one warning log line).
//! - The two capacity constants ([`SOFT_CAPACITY`], [`HARD_CAPACITY`])
//!   so the surface shells can format their hard-cap rejection messages
//!   without drift. The matching `*_REFILL_PER_SEC` rates stay private
//!   to this module — they're an implementation detail of the bucket
//!   refill math, not part of the user-facing wording.
//!
//! ## What does NOT live here
//!
//! - The `OnceLock<Mutex<…>>` singleton — each binary keeps its own.
//! - `tracing::warn!` / `eprintln!` — the surface decides how to log.
//! - The crate-specific error type — the surface translates the
//!   typed decision into `McpError::RateLimited` / `CliError::Validation`.
//!
//! ## Correctness invariants
//!
//! 1. The hard cap is checked first. If the hard bucket is empty the
//!    soft bucket is NOT decremented — a rejected write does not count
//!    against the soft warning, otherwise a long over-cap window would
//!    log a soft warning every time a rejected write retried.
//! 2. The soft-warn latch (`soft_warned`) is reset on every successful
//!    soft-bucket consume, NOT only when post-consume tokens are >= 1.
//!    A trickle refill — exactly 1 token, consumed immediately —
//!    leaves post-consume tokens at 0; the legacy guard
//!    `tokens >= 1.0` after the consume kept the latch armed and a
//!    subsequent over-cap burst produced no further warning. Reset on
//!    success-implies-recovery so each distinct over-soft burst gets
//!    its own warning. Regression coverage:
//!    `soft_warning_rearms_when_only_one_token_refilled`.
//! 3. The math is panic-free, IO-free, and error-free. Callers drive
//!    `check_at` with a synthetic [`Instant`] in tests so refill
//!    behavior is deterministic without sleeping wall-clock time.

use std::time::Instant;

/// Soft cap — warn-only. 60 writes per minute = 1 token/second refill,
/// burst capacity of 60.
pub const SOFT_CAPACITY: f64 = 60.0;
const SOFT_REFILL_PER_SEC: f64 = 1.0; // 60 tokens / 60 seconds

/// Hard cap — rejecting. 500 writes per hour = 1 token per 7.2s refill,
/// burst capacity of 500.
pub const HARD_CAPACITY: f64 = 500.0;
const HARD_REFILL_PER_SEC: f64 = 500.0 / 3600.0; // ≈0.1389

/// State for a single token bucket. Internal — exposed only via
/// [`WriteRateLimitState`].
#[derive(Debug, Clone, Copy)]
struct Bucket {
    /// Remaining token count (fractional to smooth the refill math).
    tokens: f64,
    /// Last time we refilled the bucket.
    last_refill: Instant,
    /// Maximum tokens the bucket can hold.
    capacity: f64,
    /// Tokens added per elapsed second.
    refill_per_sec: f64,
}

impl Bucket {
    const fn new(now: Instant, capacity: f64, refill_per_sec: f64) -> Self {
        Self {
            tokens: capacity,
            last_refill: now,
            capacity,
            refill_per_sec,
        }
    }

    /// Refill tokens based on elapsed wall-clock, capped at `capacity`.
    fn refill(&mut self, now: Instant) {
        let elapsed = now
            .saturating_duration_since(self.last_refill)
            .as_secs_f64();
        if elapsed > 0.0 {
            self.tokens = (self.tokens + elapsed * self.refill_per_sec).min(self.capacity);
            self.last_refill = now;
        }
    }

    /// Try to consume one token. Returns `true` when a token was spent.
    fn try_consume(&mut self, now: Instant) -> bool {
        self.refill(now);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

/// Per-session limiter state. Holds one soft and one hard bucket plus a
/// latch so the soft-cap warning is not spammed every write.
///
/// One binary instance = one session — both the MCP server (one stdio
/// connection per invocation) and the CLI (one process per `lorvex …`
/// invocation) wrap this in a `OnceLock<Mutex<…>>` so the buckets reset
/// naturally when the process exits and a fresh invocation starts with
/// full capacity.
#[derive(Debug)]
pub struct WriteRateLimitState {
    soft: Bucket,
    hard: Bucket,
    /// True iff we have already logged a soft-cap warning for the
    /// current over-soft window. Cleared when the soft bucket recovers
    /// to >= 1 token (i.e. on the next successful soft consume) so a
    /// later spike warns again.
    soft_warned: bool,
}

impl WriteRateLimitState {
    /// Construct a fresh limiter anchored at `now`. Both buckets start
    /// at full capacity and the warn latch starts cleared.
    pub const fn new(now: Instant) -> Self {
        Self {
            soft: Bucket::new(now, SOFT_CAPACITY, SOFT_REFILL_PER_SEC),
            hard: Bucket::new(now, HARD_CAPACITY, HARD_REFILL_PER_SEC),
            soft_warned: false,
        }
    }

    /// Core decision function. Tests drive this directly with
    /// synthetic `Instant` values so refill behavior is deterministic
    /// without sleeping real wall-clock time. Callers in production
    /// pass `Instant::now()`.
    ///
    /// Returns [`WriteRateDecision::Allowed`] when the write is
    /// allowed (with a [`WarnSignal`] telling the caller whether to
    /// emit a one-shot soft-cap warning) or
    /// [`WriteRateDecision::Denied`] when the hard cap is exceeded.
    pub fn check_at(&mut self, now: Instant) -> WriteRateDecision {
        // Hard cap first: if we're out of hard tokens, fail loudly
        // without counting this call against the soft bucket (the
        // request never made it through).
        if !self.hard.try_consume(now) {
            return WriteRateDecision::Denied {
                hard_capacity: HARD_CAPACITY as u64,
            };
        }

        // Soft cap: consume a token if available. If not, emit a single
        // warning per over-soft crossing (cleared when the bucket
        // recovers).
        //
        // The latch reset condition reads the bucket's state AFTER
        // try_consume has already decremented one token. A
        // successful consume implies the pre-consume bucket held at
        // least 1.0 — i.e. the bucket has recovered to >= 1 token,
        // which is the recovery condition the comment on
        // `soft_warned` documents. Pre-fix the latch was reset only
        // when post-consume tokens >= 1.0 — equivalent to requiring
        // the pre-consume bucket to hold >= 2.0 — so a steady
        // refill+consume rhythm at exactly the soft cap kept the
        // latch stuck and a later runaway spike logged nothing.
        // Rebase on the success-implies-recovery invariant so each
        // distinct over-soft burst gets its own warning.
        let warn = if self.soft.try_consume(now) {
            self.soft_warned = false;
            WarnSignal::Ok
        } else if self.soft_warned {
            WarnSignal::Ok
        } else {
            self.soft_warned = true;
            WarnSignal::FirstSoftCapCrossing
        };

        WriteRateDecision::Allowed { warn }
    }
}

/// Outcome of the soft-cap check, decoupled from logging so tests can
/// assert without scraping stderr / a tracing subscriber.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WarnSignal {
    /// No warning needed — either under the soft cap or we already
    /// warned for this over-soft window.
    Ok,
    /// First crossing of the soft cap; caller should emit a single
    /// warning log line.
    FirstSoftCapCrossing,
}

/// Typed outcome of a single rate-limit check. Each surface (MCP /
/// CLI) translates this into its native error type at the boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WriteRateDecision {
    /// The write is allowed under both caps. `warn` tells the caller
    /// whether to emit the one-shot soft-cap warning at this call.
    Allowed { warn: WarnSignal },
    /// The hard cap is exhausted; the write must be rejected. The
    /// caller should format a user-visible error citing
    /// `hard_capacity` writes per hour.
    Denied {
        /// The documented hard-cap rate (writes per hour). Surfaces
        /// substitute this into their localized rejection message.
        hard_capacity: u64,
    },
}

#[cfg(test)]
mod tests;
