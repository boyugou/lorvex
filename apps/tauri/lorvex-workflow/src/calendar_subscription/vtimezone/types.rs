//! Data types for the VTIMEZONE registry: per-observance metadata,
//! the per-TZID definition (`VTimezoneDefinition`), and the per-feed
//! lookup table (`VTimezoneRegistry`). The resolver entry point —
//! `VTimezoneDefinition::offset_seconds_at` — also lives here so the
//! type owns its own offset-resolution method; it delegates to
//! `super::calendrics::latest_transition_at_or_before` for the
//! per-observance walk.

use std::collections::HashMap;

use chrono::{NaiveDateTime, Weekday};

use super::calendrics::latest_transition_at_or_before;

/// One STANDARD or DAYLIGHT observance inside a VTIMEZONE.
#[derive(Debug, Clone)]
pub(super) struct Observance {
    /// Wall-clock start of this observance, expressed in the
    /// `TZOFFSETFROM` offset per RFC 5545. The from-offset itself
    /// is NOT stored — Lorvex only ever consumes `offset_to` (the
    /// offset DURING the observance, which is what the resolver
    /// applies to the query instant). Parsing still validates that
    /// TZOFFSETFROM is present and well-formed in the feed: a
    /// malformed observance is dropped at parse time.
    pub(super) dtstart: NaiveDateTime,
    /// UTC offset (in seconds) after this transition. The value the
    /// resolver returns when this observance is the most recent one
    /// before the query instant.
    pub(super) offset_to: i32,
    /// Yearly RRULE for the recurring transition, if any. Real
    /// VTIMEZONE feeds use a single yearly rule per observance.
    pub(super) rrule: Option<TimezoneRrule>,
}

/// Subset of RRULE features we recognize for VTIMEZONE
/// transitions. Anything else (`FREQ` other than `YEARLY`,
/// `BYMONTHDAY`, `INTERVAL > 1`, etc.) is silently ignored — the
/// observance falls back to its bare `DTSTART`.
#[derive(Debug, Clone)]
pub(crate) struct TimezoneRrule {
    /// Month (1-12) — required.
    pub(crate) by_month: u32,
    /// Weekday and ordinal: e.g. `(Sunday, 2)` for "second Sunday",
    /// `(Sunday, -1)` for "last Sunday". `BYDAY=2SU` / `BYDAY=-1SU`.
    pub(crate) by_day: (Weekday, i32),
    /// Optional UNTIL (inclusive) — a feed that retired a DST rule
    /// in the past sets this so future years stop recurring.
    pub(crate) until: Option<NaiveDateTime>,
}

/// Parsed VTIMEZONE definition: every observance keyed by its
/// `BEGIN:STANDARD` / `BEGIN:DAYLIGHT` block. Lookup walks all of
/// them and picks the most recent transition before the query
/// instant.
#[derive(Debug, Clone, Default)]
pub(super) struct VTimezoneDefinition {
    pub(super) observances: Vec<Observance>,
}

impl VTimezoneDefinition {
    /// Compute the wall-clock → UTC offset that applies at
    /// `naive_local`. Returns the `TZOFFSETTO` of the most recent
    /// transition at or before `naive_local`. If `naive_local`
    /// precedes the earliest transition (e.g., a 2026 query against
    /// a feed whose only DTSTARTs are dated 1601 — the Outlook
    /// sentinel), we still return the earliest observance's
    /// `offset_to` because its RRULE generates all later transitions.
    pub(super) fn offset_seconds_at(&self, naive_local: NaiveDateTime) -> Option<i32> {
        if self.observances.is_empty() {
            return None;
        }

        // For every observance, find its most recent transition <= naive_local.
        // The greatest such transition wins.
        let mut best: Option<(NaiveDateTime, i32)> = None;
        for obs in &self.observances {
            let candidate = latest_transition_at_or_before(obs, naive_local);
            if let Some(at) = candidate {
                if best.is_none_or(|(t, _)| at > t) {
                    best = Some((at, obs.offset_to));
                }
            }
        }

        if let Some((_, offset)) = best {
            return Some(offset);
        }

        // `naive_local` is before every observance's DTSTART. Pick
        // the observance whose first known transition is earliest;
        // its `offset_to` is the historical baseline.
        self.observances
            .iter()
            .min_by_key(|o| o.dtstart)
            .map(|o| o.offset_to)
    }
}

/// Per-feed registry of VTIMEZONE definitions, keyed by TZID.
/// Built once during the ICS scan and consulted by
/// [`super::super::tzid::parse_ics_datetime_with_registry`] before
/// the IANA / Windows fallback.
#[derive(Debug, Clone, Default)]
pub struct VTimezoneRegistry {
    pub(super) by_tzid: HashMap<String, VTimezoneDefinition>,
}

impl VTimezoneRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.by_tzid.is_empty()
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.by_tzid.len()
    }

    /// Return the wall-clock → UTC offset (in seconds) for `tzid`
    /// at the given naive local time, or `None` if the registry has
    /// no definition for that TZID.
    pub fn offset_seconds_at(&self, tzid: &str, naive_local: NaiveDateTime) -> Option<i32> {
        let def = self.by_tzid.get(tzid)?;
        def.offset_seconds_at(naive_local)
    }

    /// Convenience for tests: was this TZID defined in the feed?
    #[cfg(test)]
    pub fn contains(&self, tzid: &str) -> bool {
        self.by_tzid.contains_key(tzid)
    }
}
