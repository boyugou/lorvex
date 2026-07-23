use serde::{Deserialize, Serialize};

use crate::time::{Date, TimeOfDay};
use crate::validation::ValidationError;

pub const CANONICAL_CALENDAR_EVENT_TYPE_ALLOWED_VALUES: &[&str] =
    &["event", "birthday", "anniversary", "memorial"];
const CANONICAL_CALENDAR_EVENT_TYPE_ALLOWED_VALUES_DISPLAY: &str =
    "event, birthday, anniversary, memorial";

/// The canonical set of `calendar_events.event_type` values, enforced
/// at every layer (Tauri/MCP entry, sync apply, store repository,
/// schema CHECK). Closing #2942: pre-1.0 we own every peer build, so
/// there is no forward-compat horizon that justifies a tolerant
/// `Unknown` catch-all — every surface MUST agree on the same finite
/// set, and a payload with any other value is rejected at the trust
/// boundary it crossed. The previous `#[serde(other)] Unknown` arm
/// promised forward-compat the persistence layer never honored
/// (sync apply, repository, and SQL CHECK all reject non-canonical
/// values), so the variant was a documentation lie. Removing it
/// reunifies the contract.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CanonicalCalendarEventType {
    #[default]
    Event,
    Birthday,
    Anniversary,
    Memorial,
}

impl CanonicalCalendarEventType {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Event => "event",
            Self::Birthday => "birthday",
            Self::Anniversary => "anniversary",
            Self::Memorial => "memorial",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "event" => Some(Self::Event),
            "birthday" => Some(Self::Birthday),
            "anniversary" => Some(Self::Anniversary),
            "memorial" => Some(Self::Memorial),
            _ => None,
        }
    }

    /// Validate a free-text candidate against the canonical set.
    /// Returns the parsed enum on success, a clean error string on
    /// failure (suitable for direct embedding in user-facing
    /// validation messages). Centralized so every layer guarding
    /// `event_type` produces identical error wording.
    pub fn validate(value: &str) -> Result<Self, String> {
        Self::parse(value).ok_or_else(|| {
            format!(
                "event_type must be one of: {CANONICAL_CALENDAR_EVENT_TYPE_ALLOWED_VALUES_DISPLAY}"
            )
        })
    }
}

impl std::fmt::Display for CanonicalCalendarEventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl std::str::FromStr for CanonicalCalendarEventType {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::validate(s)
    }
}

/// Tri-state intent for a calendar event update patch's `all_day` flag.
///
/// `Some(true)` meant "set all-day = true", `Some(false)` meant
/// "set all-day = false (timed event)", and `None` meant "leave the
/// existing flag unchanged". Replacing it with this explicit enum
/// lets every downstream match site exhaustive-match on the three
/// valid intents and turns `args.all_day == Some(true)` checks
/// (semantically "the request asked to make this all-day") into
/// the more readable `args.all_day == AllDayPatch::SetAllDay`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum AllDayPatch {
    /// The patch did not specify an `all_day` intent. Leave the
    /// existing flag alone.
    #[default]
    NoChange,
    /// Set `all_day = true` (the event spans entire days; start_time
    /// / end_time must be cleared at the same time).
    SetAllDay,
    /// Set `all_day = false` (the event has a specific time-of-day).
    SetTimed,
}

impl AllDayPatch {
    /// Construct from the boundary `Option<bool>` shape that
    /// clap / serde produce at MCP, CLI, and IPC argument boundaries.
    /// `Some(true) → SetAllDay`, `Some(false) → SetTimed`,
    /// `None → NoChange`.
    pub const fn from_optional_bool(value: Option<bool>) -> Self {
        match value {
            None => Self::NoChange,
            Some(true) => Self::SetAllDay,
            Some(false) => Self::SetTimed,
        }
    }

    /// Returns the resulting `all_day` bool when the patch carries a
    /// change, or `None` when the patch leaves the flag alone. SQL
    /// bind sites that bind a bool only when the patch sets `all_day`
    /// can use this directly.
    pub const fn target_value(self) -> Option<bool> {
        match self {
            Self::NoChange => None,
            Self::SetAllDay => Some(true),
            Self::SetTimed => Some(false),
        }
    }

    /// True iff the patch carries an `all_day` change of any kind.
    pub const fn is_present(self) -> bool {
        !matches!(self, Self::NoChange)
    }
}

// ---------------------------------------------------------------------------
// `CalendarEventTiming` — typed sum capturing the three valid temporal
// shapes for a calendar event row, replacing the implicit
// (start_date, start_time, end_date, end_time, all_day) quintuple.
// ---------------------------------------------------------------------------

/// The three legal temporal shapes a calendar event row can take.
///
/// Issue target #2:
/// (`CalendarTimelineItem`, `CalendarEventRow`, `CalendarIcsEventRecord`,
/// `CalendarIcsEvent`) held an implicit quintuple — `start_date: Date`,
/// `start_time: Option<TimeOfDay>`, `end_date: Option<Date>`,
/// `end_time: Option<TimeOfDay>`, `all_day: bool` — with the validity
/// rules ("if `all_day` then no times; if a time is set, both must be
/// set on a multi-day event") enforced only by ad-hoc `debug_assert!`
/// scattered across the construction sites. A `CalendarTimelineItem`
/// with `all_day = true` AND `start_time = Some("09:00".into())`
/// compiled cleanly and silently picked the time-of-day branch on top
/// of an all-day shell. This enum makes every illegal combination
/// non-representable.
///
/// Wire format is preserved: the [`CalendarEventTimingFlat`] adapter
/// (de)serializes the same five JSON keys (`start_date`, `start_time`,
/// `end_date`, `end_time`, `all_day`) the legacy quintuple emitted, so
/// every JSON envelope, sync payload, IPC response, and stored row keeps
/// its byte-stable shape across the migration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalendarEventTiming {
    /// `all_day = true`, no times. `end` is `None` for a single-day
    /// all-day event; `Some(date)` for a multi-day all-day span where
    /// `end >= start`.
    AllDay { start: Date, end: Option<Date> },
    /// `all_day = false`, single-day timed event: `end_date == start_date`
    /// is implied (and serialized as `end_date = None`, mirroring the
    /// legacy convention where same-day timed events leave `end_date`
    /// unset). `end` time is `None` for a point-in-time event,
    /// `Some(t)` for a duration where `end >= start`.
    TimedSingleDay {
        date: Date,
        start: TimeOfDay,
        end: Option<TimeOfDay>,
    },
    /// `all_day = false`, multi-day timed span. Both ends carry a time;
    /// `(end_date, end_time) >= (start_date, start_time)` lexicographically.
    TimedMultiDay {
        start_date: Date,
        start_time: TimeOfDay,
        end_date: Date,
        end_time: TimeOfDay,
    },
}

impl CalendarEventTiming {
    /// Construct a [`CalendarEventTiming`] from the legacy five-field
    /// shape that flows through SQL row reads, JSON envelope deserialize,
    /// and MCP / Tauri / CLI argument boundaries. Centralizing the
    /// validity rules here means every entry seam produces the same
    /// typed errors with the same field labels.
    ///
    /// Validation rules:
    /// - `all_day = true` → `start_time` and `end_time` must both be
    ///   `None`. `start_date` is required; `end_date` is optional and
    ///   must be `>= start_date` when present.
    /// - `all_day = false` → `start_time` is required. If `end_date`
    ///   is `None` (or equals `start_date`), this is a single-day
    ///   timed event and `end_time` may be `None` (point-in-time) or
    ///   `Some(t)` with `t >= start_time`. If `end_date > start_date`,
    ///   both `start_time` and `end_time` must be `Some` and the
    ///   `(date, time)` pair must satisfy `end >= start`.
    pub fn from_flat_fields(
        start_date: Date,
        start_time: Option<TimeOfDay>,
        end_date: Option<Date>,
        end_time: Option<TimeOfDay>,
        all_day: bool,
    ) -> Result<Self, ValidationError> {
        if all_day {
            if start_time.is_some() || end_time.is_some() {
                return Err(ValidationError::Message(
                    "all_day events must not carry start_time or end_time".to_string(),
                ));
            }
            if let Some(end) = end_date {
                if end < start_date {
                    return Err(ValidationError::Message(format!(
                        "calendar event end_date ({}) is before start_date ({})",
                        end.as_string(),
                        start_date.as_string()
                    )));
                }
            }
            return Ok(Self::AllDay {
                start: start_date,
                end: end_date,
            });
        }

        let start = start_time.ok_or_else(|| {
            ValidationError::Message(
                "timed (non-all-day) calendar event must carry start_time".to_string(),
            )
        })?;

        // Multi-day vs single-day branch. `end_date == None` and
        // `end_date == Some(start_date)` are both treated as "single-day"
        // — the legacy callers stored `None` for same-day events but
        // some carriers explicitly pass `Some(start_date)`.
        let single_day = match end_date {
            None => true,
            Some(end) if end == start_date => true,
            Some(end) if end < start_date => {
                return Err(ValidationError::Message(format!(
                    "calendar event end_date ({}) is before start_date ({})",
                    end.as_string(),
                    start_date.as_string()
                )));
            }
            Some(_) => false,
        };

        if single_day {
            if let Some(end) = end_time {
                if end < start {
                    return Err(ValidationError::Message(format!(
                        "calendar event end_time ({}) is before start_time ({})",
                        end.as_string(),
                        start.as_string()
                    )));
                }
            }
            Ok(Self::TimedSingleDay {
                date: start_date,
                start,
                end: end_time,
            })
        } else {
            let end_d = end_date.expect("multi-day branch requires end_date");
            let end_t = end_time.ok_or_else(|| {
                ValidationError::Message(
                    "multi-day timed calendar event must carry end_time".to_string(),
                )
            })?;
            // Lexicographic (date, time) compare — multi-day means
            // end_d > start_date so this is automatically satisfied,
            // but we double-check for completeness.
            if (end_d, end_t) < (start_date, start) {
                return Err(ValidationError::Message(format!(
                    "calendar event end ({} {}) is before start ({} {})",
                    end_d.as_string(),
                    end_t.as_string(),
                    start_date.as_string(),
                    start.as_string()
                )));
            }
            Ok(Self::TimedMultiDay {
                start_date,
                start_time: start,
                end_date: end_d,
                end_time: end_t,
            })
        }
    }

    /// `start_date` accessor — present on every variant.
    pub const fn start_date(&self) -> Date {
        match self {
            Self::AllDay { start, .. } => *start,
            Self::TimedSingleDay { date, .. } => *date,
            Self::TimedMultiDay { start_date, .. } => *start_date,
        }
    }

    /// `start_time` accessor in the legacy `Option<TimeOfDay>` shape.
    /// `AllDay` returns `None`; timed variants return the start time.
    pub const fn start_time(&self) -> Option<TimeOfDay> {
        match self {
            Self::AllDay { .. } => None,
            Self::TimedSingleDay { start, .. } => Some(*start),
            Self::TimedMultiDay { start_time, .. } => Some(*start_time),
        }
    }

    /// `end_date` accessor in the legacy `Option<Date>` shape.
    /// Single-day variants (both all-day and timed) return `None`
    /// when no explicit end was carried (matching the legacy storage
    /// convention where same-day events left `end_date` unset).
    pub const fn end_date(&self) -> Option<Date> {
        match self {
            Self::AllDay { end, .. } => *end,
            Self::TimedSingleDay { .. } => None,
            Self::TimedMultiDay { end_date, .. } => Some(*end_date),
        }
    }

    /// `end_time` accessor in the legacy `Option<TimeOfDay>` shape.
    pub const fn end_time(&self) -> Option<TimeOfDay> {
        match self {
            Self::AllDay { .. } => None,
            Self::TimedSingleDay { end, .. } => *end,
            Self::TimedMultiDay { end_time, .. } => Some(*end_time),
        }
    }

    /// `all_day` accessor — `true` only for the `AllDay` variant.
    pub const fn all_day(&self) -> bool {
        matches!(self, Self::AllDay { .. })
    }

    /// Project this typed timing back into the five legacy fields,
    /// for SQL bind sites and any wire shape that still emits them
    /// flat. Returns a tuple in the canonical column / JSON-key order:
    /// `(start_date, start_time, end_date, end_time, all_day)`.
    pub const fn as_flat_fields(
        &self,
    ) -> (
        Date,
        Option<TimeOfDay>,
        Option<Date>,
        Option<TimeOfDay>,
        bool,
    ) {
        (
            self.start_date(),
            self.start_time(),
            self.end_date(),
            self.end_time(),
            self.all_day(),
        )
    }

    /// Borrow this typed timing as the wire-stable flat shape — used
    /// at every JSON serialize site so envelopes / IPC responses /
    /// sync payloads keep emitting the historical five-key shape.
    pub const fn to_flat(&self) -> CalendarEventTimingFlat {
        let (start_date, start_time, end_date, end_time, all_day) = self.as_flat_fields();
        CalendarEventTimingFlat {
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
        }
    }
}

/// Wire-stable flat-fields adapter for [`CalendarEventTiming`].
///
/// Serializes / deserializes as the historical five-key JSON shape —
/// `{ "start_date": ..., "start_time": ..., "end_date": ...,
/// "end_time": ..., "all_day": ... }` — so every existing envelope,
/// IPC response, and sync payload keeps byte-identical wire format
/// after the typed-enum migration. Construct via [`CalendarEventTiming::to_flat`]
/// to serialize an existing typed timing; round-trip back through
/// [`CalendarEventTimingFlat::into_typed`] to validate on deserialize.
///
/// Same-day timed events serialize with `end_date = null` (matching the
/// legacy convention where same-day timed rows left `end_date` unset);
/// `end_time = null` is preserved for point-in-time events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarEventTimingFlat {
    pub start_date: Date,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub start_time: Option<TimeOfDay>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub end_date: Option<Date>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub end_time: Option<TimeOfDay>,
    pub all_day: bool,
}

impl CalendarEventTimingFlat {
    /// Validate the deserialized flat-fields shape and convert to the
    /// typed [`CalendarEventTiming`]. Centralized so every JSON entry
    /// boundary produces identical error wording.
    pub fn into_typed(self) -> Result<CalendarEventTiming, ValidationError> {
        CalendarEventTiming::from_flat_fields(
            self.start_date,
            self.start_time,
            self.end_date,
            self.end_time,
            self.all_day,
        )
    }
}

impl From<CalendarEventTiming> for CalendarEventTimingFlat {
    fn from(timing: CalendarEventTiming) -> Self {
        timing.to_flat()
    }
}

impl TryFrom<CalendarEventTimingFlat> for CalendarEventTiming {
    type Error = ValidationError;

    fn try_from(flat: CalendarEventTimingFlat) -> Result<Self, Self::Error> {
        flat.into_typed()
    }
}

/// Manual `Serialize` for [`CalendarEventTiming`] that emits the
/// historical five-key shape *without* `skip_serializing_if`. This is
/// the wire-stable shape every carrier struct (`CalendarTimelineItem`,
/// the various JSON envelopes, snapshot goldens) has emitted since
/// before the typed-enum migration: each of `start_date`, `start_time`,
/// `end_date`, `end_time`, `all_day` is always present, with `null`
/// reserved for unset optional values.
///
/// This intentionally does NOT reuse [`CalendarEventTimingFlat`]'s
/// `Serialize` derive — that adapter SKIPS `null` keys (it's used at
/// envelope boundaries that prefer terse JSON). Carriers that pin
/// snapshot wire output would byte-shift if a `null` key disappeared,
/// so we serialize through this map-based path that always names every
/// key. Combined with `#[serde(flatten)] timing: CalendarEventTiming`
/// on the carrier struct, the final JSON inlines the same five keys
/// the legacy quintuple emitted.
impl Serialize for CalendarEventTiming {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeMap;
        let (start_date, start_time, end_date, end_time, all_day) = self.as_flat_fields();
        let mut map = serializer.serialize_map(Some(5))?;
        map.serialize_entry("start_date", &start_date)?;
        map.serialize_entry("start_time", &start_time)?;
        map.serialize_entry("end_date", &end_date)?;
        map.serialize_entry("end_time", &end_time)?;
        map.serialize_entry("all_day", &all_day)?;
        map.end()
    }
}

#[cfg(test)]
mod tests;
