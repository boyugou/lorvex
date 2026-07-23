//! VTIMEZONE block parsing and per-feed offset resolution.
//!
//! RFC 5545 lets an ICS feed ship its own
//! timezone definition by name: a `BEGIN:VTIMEZONE` block whose
//! `TZID` is referenced by event `DTSTART;TZID=...` lines. Outlook,
//! Exchange, and many self-hosted calendars exploit this to ship
//! Windows display names (`Eastern Standard Time`) or fully
//! invented zone IDs (`/example.com/Custom_Zone/Europe`) that
//! `chrono-tz` cannot resolve and that the Windows→IANA shim in
//! [`super::tzid::resolve_tzid_to_iana`] does not recognize.
//!
//! This module makes those feeds parse correctly. The VTIMEZONE
//! block carries the offsets we need, so we parse it during the
//! same scan that extracts events and produce a
//! [`VTimezoneRegistry`] that the datetime-resolver consults FIRST,
//! ahead of the IANA / Windows lookup. Without it, an unresolvable
//! TZID would silently fall back to UTC and shift the wall-clock
//! time by up to 12h.
//!
//! Resolution model
//! ─────────────────
//! A VTIMEZONE definition is a list of observances (STANDARD or
//! DAYLIGHT sub-components), each with:
//! - `DTSTART` — wall-clock start of this observance (in the
//!   `TZOFFSETFROM` offset, per RFC 5545 §3.6.5).
//! - `TZOFFSETFROM` / `TZOFFSETTO` — UTC offsets before and after
//!   this transition, e.g. `-0500` / `-0400`.
//! - `RRULE` (optional) — if present, this observance repeats
//!   yearly via a `BYDAY=<n>SU` / `BYMONTH=<m>` rule.
//!
//! For a given naive wall-clock instant, we walk every observance,
//! materialize the most recent transition before that instant
//! (either the `DTSTART` itself or the latest `RRULE` occurrence),
//! and return the `TZOFFSETTO` of the latest transition. That
//! offset defines the `wall → UTC` mapping the parser uses to emit
//! a `source_time_kind="utc"` value the projection layer can render
//! in any anchor zone.
//!
//! What we deliberately do NOT do
//! ──────────────────────────────
//! - We do not synthesize an IANA name for the zone. The downstream
//!   recurrence-expansion path needs a real `chrono_tz::Tz` to walk
//!   future occurrences correctly; if no IANA mapping exists we'd
//!   rather emit UTC instants (correct for the master DTSTART /
//!   DTEND we see) than guess at a zone identifier.
//! - We do not honour every RFC 5545 RRULE feature. Real-world
//!   VTIMEZONE blocks use `FREQ=YEARLY;BYMONTH=<m>;BYDAY=<n>SU`
//!   exclusively (DST start / end). Anything else falls back to
//!   the bare `DTSTART` of the observance.
//!
//! Module layout:
//!   * `types` — `Observance`, `TimezoneRrule`, `VTimezoneDefinition`, `VTimezoneRegistry`.
//!   * `calendrics` — `latest_transition_at_or_before`, `nth_weekday_of_month` date math.
//!   * `parse` — every `parse_*` function operating on the unfolded ICS line stream.
//!
//! Regression tests live in `super::tests::vtimezone` so they share the
//! crate-wide `#[cfg(test)]` test module rather than nesting under
//! this subtree.

mod calendrics;
mod parse;
mod types;

pub use parse::parse_vtimezone_blocks;
pub use types::VTimezoneRegistry;

#[cfg(test)]
pub(crate) use calendrics::nth_weekday_of_month;
#[cfg(test)]
pub(crate) use parse::{parse_timezone_rrule, parse_utc_offset_seconds};
