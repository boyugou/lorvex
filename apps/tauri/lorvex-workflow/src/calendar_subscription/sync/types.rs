//! IPC / wire types and the surface-supplied transport trait for the
//! subscription sync pipeline.
//!
//! Owns the data shapes every sibling in this subtree consumes:
//! [`FetchedIcs`] / [`FetchedIcsError`] for backend results, the
//! [`FetchBackend`] trait that injects the HTTP transport, and the
//! per-feed [`SubscriptionSyncResult`] row both surfaces emit. The
//! [`ICS_TRUNCATION_LOG_SOURCE`] constant lives here too because the
//! orchestrator and the truncation-rejection helper both reference it.

use serde::Serialize;

use super::super::truncation::{IcsTruncationReason, ICS_TRUNCATION_MESSAGE};

/// `error_logs.source` value written when a subscription refresh is
/// aborted because the fetched body is truncated. Settings →
/// Diagnostics filters on `source`, so a dedicated value here lets
/// users distinguish a mid-stream cut-off from a generic fetch / parse
/// failure. The provider-scope runtime state's `last_refresh_result`
/// enum is closed (CHECK constraint), so the refresh still classifies
/// as `fetch_error` there and the truncation signal travels through
/// this secondary log entry where `source` is free-form.
pub const ICS_TRUNCATION_LOG_SOURCE: &str = "sync.ics.truncated";

/// Successful body read from a `FetchBackend`. `status` is the raw
/// HTTP status — backends are responsible for translating 429 into
/// [`FetchedIcsError::RateLimited`] before returning, so `status` here
/// is informational (currently unused by the orchestrator but reserved
/// for diagnostic surfacing of e.g. 200 vs 204).
#[derive(Debug, Clone)]
pub struct FetchedIcs {
    pub body: String,
    pub etag: Option<String>,
    pub status: u16,
}

/// Typed error from a `FetchBackend` fetch attempt.
///
/// The variants mirror the orchestrator's branch points: rate-limit
/// cooldown bookkeeping is gated on `RateLimited`, the cache-preserve
/// path on `Truncated`, and the generic `last_error` write on `Other`.
#[derive(Debug)]
pub enum FetchedIcsError {
    /// Server returned HTTP 429. `retry_after_secs` carries the
    /// parsed `Retry-After` header when present (per RFC 9110 only
    /// the integer-seconds form is decoded). `safe_url` is the
    /// caller-sanitized URL the orchestrator surfaces in
    /// `last_error`.
    RateLimited {
        retry_after_secs: Option<u64>,
        safe_url: String,
    },
    /// Body looked like a VCALENDAR prefix but did not balance —
    /// missing `END:VCALENDAR` terminator, or unmatched
    /// `BEGIN:VEVENT` / `END:VEVENT` counts. Backends run truncation
    /// detection inline so the orchestrator preserves the cached
    /// events and writes the dedicated `sync.ics.truncated`
    /// diagnostic.
    Truncated {
        reason: IcsTruncationReason,
        safe_url: String,
    },
    /// Any other failure: transport, DNS, redirect cap, captive
    /// portal heuristic, malformed Location header, etc. The message
    /// is surfaced verbatim to `last_error`.
    Other(String),
}

impl std::fmt::Display for FetchedIcsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FetchedIcsError::RateLimited {
                retry_after_secs,
                safe_url,
            } => match retry_after_secs {
                Some(secs) => write!(
                    f,
                    "Calendar feed is rate-limited (HTTP 429). Retry after {secs}s: {safe_url}"
                ),
                None => write!(
                    f,
                    "Calendar feed is rate-limited (HTTP 429). Retry later: {safe_url}"
                ),
            },
            FetchedIcsError::Truncated { reason, safe_url } => {
                write!(f, "{ICS_TRUNCATION_MESSAGE} ({reason}): {safe_url}")
            }
            FetchedIcsError::Other(msg) => f.write_str(msg),
        }
    }
}

/// Surface-supplied transport for ICS body fetches.
///
/// Implementors own everything that ties the fetch to a concrete
/// runtime: HTTP client construction, SSRF / DNS-rebinding defenses,
/// per-read idle-timeout enforcement, captive-portal heuristics, and
/// the `Retry-After` parser that classifies a 429 response. The
/// workflow orchestrator stays agnostic of all of these by accepting
/// a `&dyn FetchBackend` reference and routing through the trait.
pub trait FetchBackend {
    /// Fetch the body of the `.ics` feed at `url`. `etag` is the
    /// last-seen ETag (presently unused by the orchestrator — every
    /// refresh re-reads the full body — and reserved for a future
    /// conditional-fetch surface).
    fn fetch_ics(&self, url: &str, etag: Option<&str>) -> Result<FetchedIcs, FetchedIcsError>;
}

/// IPC-shaped result of one subscription refresh attempt.
///
/// Both the Tauri command surface and the CLI emit this struct
/// directly. Each row carries the per-feed counters (imported /
/// updated / removed) and a human-readable `error` string when the
/// attempt short-circuited (rate-limited, truncated, parse failure,
/// network error). A `None` error means the diff-apply ran and the
/// `provider_scope_runtime_state` row reflects a successful refresh.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct SubscriptionSyncResult {
    pub subscription_id: String,
    pub subscription_name: String,
    pub events_imported: i64,
    pub events_updated: i64,
    pub events_removed: i64,
    pub error: Option<String>,
}
