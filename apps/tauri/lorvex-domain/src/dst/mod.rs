//! DST-aware local-wall-clock resolution.
//!
//! scattered `from_local_datetime(...).earliest()` /
//! `.single()` call sites silently snap a spring-forward-skipped wall
//! clock (e.g. 2:30 AM on the DST transition day) to an adjacent
//! hour, with no signal to the caller. That turns "schedule at 2:30
//! AM" into "schedule at 1:00 AM or 3:00 AM" invisibly.
//!
//! [`resolve_local_datetime`] is the single source of truth for
//! mapping a user-supplied (timezone, naive local datetime) pair to a
//! concrete `DateTime<Tz>`. The three shapes are surfaced as distinct
//! [`DstResolution`] variants so each caller gets to pick its own
//! policy:
//!
//! - `Valid(dt)` — unambiguous, proceed.
//! - `Ambiguous { earlier, later }` — fall-back hour (e.g. 01:30 on
//!   the US fall-back day). The two variants represent the two UTC
//!   moments that share the same wall-clock; callers usually pick
//!   `earlier` (matching `lorvex-store::calendar_timeline::temporal`)
//!   but may log/prompt.
//! - `Skipped { requested, snapped_to }` — spring-forward gap. The
//!   wall clock never existed; `snapped_to` is the earliest valid
//!   instant after the gap so callers that need a "best-effort"
//!   timestamp still have one, but validation-sensitive callers
//!   (create/update event forms) should treat this as an error.

use chrono::{DateTime, Duration, LocalResult, NaiveDateTime, TimeZone};
use chrono_tz::Tz;

/// Outcome of resolving a naive local wall clock against an IANA zone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DstResolution {
    /// Unambiguous — the wall clock maps to exactly one UTC instant.
    Valid(DateTime<Tz>),
    /// Fall-back ambiguity — the wall clock occurs twice (e.g. 01:30
    /// during a US "fall back" transition). `earlier` is the first
    /// occurrence (pre-transition offset), `later` the second.
    Ambiguous {
        earlier: DateTime<Tz>,
        later: DateTime<Tz>,
    },
    /// Spring-forward gap — the wall clock was skipped entirely. The
    /// `snapped_to` field is the earliest valid instant AFTER the gap,
    /// provided as a best-effort fallback for callers that need a
    /// timestamp even in the error case.
    Skipped {
        requested: NaiveDateTime,
        snapped_to: DateTime<Tz>,
    },
}

/// Resolve a naive local wall clock against an IANA timezone, reporting
/// the DST shape explicitly.
///
/// This is the single entry point for timed calendar events, recurring
/// time-of-day jobs, and any other write path where a user-supplied
/// wall clock must be converted to UTC. See the module docs for the
/// policy each caller should apply per variant.
pub fn resolve_local_datetime(tz: Tz, local: NaiveDateTime) -> DstResolution {
    match tz.from_local_datetime(&local) {
        LocalResult::Single(dt) => DstResolution::Valid(dt),
        LocalResult::Ambiguous(earlier, later) => DstResolution::Ambiguous { earlier, later },
        LocalResult::None => DstResolution::Skipped {
            requested: local,
            snapped_to: snap_forward_out_of_gap(tz, local),
        },
    }
}

/// Probe forward in 15-minute steps until we land on a valid wall
/// clock. Real DST transitions never skip more than ~2 hours, so the
/// cap of 120 steps = 30 hours is generous safety margin. The cap is
/// defense against exotic zone data where a naive recursive probe
/// could otherwise loop indefinitely.
fn snap_forward_out_of_gap(tz: Tz, local: NaiveDateTime) -> DateTime<Tz> {
    let mut candidate = local;
    for _ in 0..120 {
        candidate += Duration::minutes(15);
        match tz.from_local_datetime(&candidate) {
            LocalResult::Single(dt) => return dt,
            LocalResult::Ambiguous(earlier, _) => return earlier,
            LocalResult::None => (),
        }
    }
    // Extremely defensive fallback: `from_local_datetime` for the
    // original input returned `None`, so `.earliest()` here also
    // returns `None`. We fall back to a UTC-interpretation of the
    // naive value to avoid panicking. No real IANA zone reaches this
    // branch.
    tz.from_utc_datetime(&local)
}

#[cfg(test)]
mod tests;
