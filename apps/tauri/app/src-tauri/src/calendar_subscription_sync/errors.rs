//! Typed error shapes for the ICS fetch pipeline.
//!
//! `fetch_ics_content` distinguishes HTTP 429 rate-limiting and
//! mid-stream truncation from generic failures so callers can preserve
//! the existing cache and let the retry scheduler pick up the next
//! cycle. `IcsBodyReadError` separates size-cap and idle-timeout
//! responses so the caller can add the sanitized URL to the
//! user-facing message exactly once.
//!
//! The pure truncation-detection primitive (`detect_ics_truncation`,
//! [`IcsTruncationReason`], [`ICS_TRUNCATION_MESSAGE`]) lives in
//! [`lorvex_workflow::calendar_subscription::truncation`]; the
//! `IcsFetchError::Truncated` variant carries those workflow types
//! verbatim.

use lorvex_workflow::calendar_subscription::truncation::{
    IcsTruncationReason, ICS_TRUNCATION_MESSAGE,
};
use lorvex_workflow::calendar_subscription::CalendarSubscriptionError;

use crate::error::AppError;

/// Bridge from the workflow-side primitive error enum into the
/// Tauri-side `AppError`. `validate_ics_url_safety` (lifted into
/// `lorvex-workflow` for cross-surface reuse) returns
/// `CalendarSubscriptionError`; this `From` impl keeps the existing
/// `?` chains in `fetch.rs` / `sync.rs` working unchanged.
impl From<CalendarSubscriptionError> for AppError {
    fn from(err: CalendarSubscriptionError) -> Self {
        match err {
            CalendarSubscriptionError::Validation(msg) => AppError::Validation(msg),
            // Preserve the typed `StoreError` discriminant so the
            // disk-full / stale-version / not-found envelopes render
            // their actionable shape on the frontend instead of
            // collapsing to a generic `Internal` toast.
            CalendarSubscriptionError::Store(store) => AppError::Store(Box::new(store)),
            CalendarSubscriptionError::Db(sql) => AppError::Sql(Box::new(sql)),
            CalendarSubscriptionError::Internal(msg) => AppError::Internal(msg),
        }
    }
}

/// Typed error for `fetch_ics_content` so the caller can distinguish an
/// HTTP 429 (with optional server-provided Retry-After seconds) from any
/// other failure. Non-rate-limit errors still flow through `AppError`
/// untouched.
#[derive(Debug)]
pub(crate) enum IcsFetchError {
    RateLimited {
        retry_after_secs: Option<u64>,
        safe_url: String,
    },
    /// the response body looks like a VCALENDAR prefix but
    /// does not terminate with `END:VCALENDAR` (missing end marker), or
    /// the `BEGIN:VEVENT` / `END:VEVENT` counts do not balance. Both
    /// signatures indicate the HTTP connection closed mid-stream — the
    /// size-cap reader delivered a partial body that would otherwise
    /// silently skip every truncated event (the parser is gated on
    /// `END:VEVENT`). Surfacing this as a distinct variant lets the
    /// caller preserve the existing cache and let the retry scheduler
    /// pick it up on the next cycle.
    Truncated {
        reason: IcsTruncationReason,
        safe_url: String,
    },
    Other(AppError),
}

impl std::fmt::Display for IcsFetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IcsFetchError::RateLimited {
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
            IcsFetchError::Truncated { reason, safe_url } => {
                write!(f, "{ICS_TRUNCATION_MESSAGE} ({reason}): {safe_url}")
            }
            IcsFetchError::Other(err) => write!(f, "{err}"),
        }
    }
}

impl From<AppError> for IcsFetchError {
    fn from(err: AppError) -> Self {
        IcsFetchError::Other(err)
    }
}

impl From<CalendarSubscriptionError> for IcsFetchError {
    fn from(err: CalendarSubscriptionError) -> Self {
        IcsFetchError::Other(AppError::from(err))
    }
}

/// outcome of reading a response body with the running
/// size cap + mid-stream idle timeout. Separated from `AppError` so
/// the caller can add the sanitized URL to the user-facing message
/// exactly once, and so we can unit-test the reader against
/// synthetic streams without having to fabricate a real
/// `reqwest::Response`.
#[derive(Debug)]
pub(crate) enum IcsBodyReadError {
    /// Total bytes read exceeded the cap (`MAX_ICS_RESPONSE_BYTES`).
    /// The cap is enforced mid-stream — we stop reading as soon as
    /// the limit is crossed, so a gigabyte feed never lands in
    /// memory.
    SizeCapExceeded { limit: usize },
    /// No progress (zero bytes delivered) within the idle window.
    /// Distinct from `Io` so the caller can tag this as a connection
    /// health problem rather than a generic socket error.
    IdleTimeout { window_secs: u64 },
    /// The underlying reader returned an I/O error.
    Io(std::io::Error),
}

impl IcsBodyReadError {
    pub(super) fn into_app_error(self, safe_url: &str) -> AppError {
        match self {
            IcsBodyReadError::SizeCapExceeded { limit } => AppError::Validation(format!(
                "Calendar feed exceeds maximum size ({limit} bytes): {safe_url}"
            )),
            IcsBodyReadError::IdleTimeout { window_secs } => AppError::Internal(format!(
                "Calendar feed stalled mid-stream (no data for {window_secs}s) from {safe_url}. The connection may be throttled or the server may have hung; try again shortly."
            )),
            IcsBodyReadError::Io(err) => AppError::Internal(format!(
                "Failed to read calendar feed response from {safe_url}: {err}"
            )),
        }
    }
}
