//! Calendar ICS event input struct, typed errors, and non-fatal warnings.
//!
//! Pure data-shape module: the export pipeline ([`super::emit`],
//! [`super::recurrence`], [`super::validation`]) consumes
//! [`CalendarIcsEvent`] and surfaces [`CalendarIcsError`] /
//! [`CalendarIcsWarning`] without owning any of the rendering logic.

use std::error::Error;
use std::fmt;

use crate::calendar::CalendarEventTiming;
use crate::time::{Date, TimeOfDay};
use crate::validation::ValidationError;

/// Owned-borrow bundle accepted by [`CalendarIcsEvent::new`]. Keeps the
/// validating constructor's parameter list ergonomic — the underlying
/// struct has 14 fields once the `(start_date, start_time, end_date,
/// end_time, all_day)` quintuple is bundled into a single typed
/// [`CalendarEventTiming`]. Every fixture, SQL row mapper, and
/// `CalendarIcsEventRecord::as_ics_event` boundary continues to express
/// the five flat temporal fields and routes them through
/// [`CalendarEventTiming::from_flat_fields`] inside [`CalendarIcsEvent::new`].
#[derive(Debug, Clone, Copy)]
pub struct CalendarIcsEventFields<'a> {
    pub id: &'a str,
    pub title: &'a str,
    pub description: Option<&'a str>,
    pub recurrence: Option<&'a str>,
    pub recurrence_exceptions: Option<&'a str>,
    pub start_date: Date,
    pub start_time: Option<TimeOfDay>,
    pub end_date: Option<Date>,
    pub end_time: Option<TimeOfDay>,
    pub all_day: bool,
    pub location: Option<&'a str>,
    pub timezone: Option<&'a str>,
    pub created_at: &'a str,
    pub updated_at: &'a str,
    pub sequence: u32,
}

/// Typed event passed to the ICS emission pipeline.
///
/// # Invariants enforced at construction (#3287)
/// - The `(start_date, start_time, end_date, end_time, all_day)`
///   quintuple is bundled into a single typed [`CalendarEventTiming`]
///   so every illegal combination (e.g. `all_day = true` with a
///   non-`None` `start_time`, or `end_date < start_date`) is
///   non-representable, so the export pipeline does not need
///   defensive guards at every branch for invalid combinations.
///
/// Wire format byte-stable: there is no JSON envelope for this struct,
/// but the typed `timing` projects back to the flat five-field shape
/// via [`CalendarEventTiming::as_flat_fields`] which the ICS emitter
/// uses to render DTSTART/DTEND/EXDATE.
#[derive(Debug, Clone, Copy)]
pub struct CalendarIcsEvent<'a> {
    pub id: &'a str,
    pub title: &'a str,
    pub description: Option<&'a str>,
    pub recurrence: Option<&'a str>,
    pub recurrence_exceptions: Option<&'a str>,
    /// Typed temporal shape. The ICS emitter reads this through the
    /// `start_date()` / `start_time()` / `end_date()` / `end_time()` /
    /// `all_day()` accessors which delegate to the typed projection.
    pub timing: CalendarEventTiming,
    pub location: Option<&'a str>,
    /// Timezone the event's local clock-time is anchored to. When set,
    /// timed events are converted to UTC for ICS emission so external
    /// clients show the event at the author's intended wall-clock time.
    /// When `None`, the event is treated as already being in UTC.
    pub timezone: Option<&'a str>,
    pub created_at: &'a str,
    pub updated_at: &'a str,
    /// VEVENT `SEQUENCE` (RFC 5545 §3.8.7.4). Without a SEQUENCE line,
    /// downstream calendar clients cannot tell an "edit republish"
    /// apart from the original publication and silently keep their
    /// stale copy. Callers MUST supply a non-decreasing integer per
    /// (UID, RECURRENCE-ID); the canonical store-side derivation is
    /// "seconds elapsed between `created_at` and `updated_at`" which
    /// is monotonic across consecutive edits to the same row and
    /// survives a sync-side merge that bumps `updated_at` without an
    /// explicit edit counter.
    pub sequence: u32,
}

impl<'a> CalendarIcsEvent<'a> {
    /// Build a [`CalendarIcsEvent`] from the flat-field input shape,
    /// enforcing temporal validity at construction via the typed
    /// [`CalendarEventTiming::from_flat_fields`] gate. Callers at the
    /// store / fixture boundary (`CalendarIcsEventRecord::as_ics_event`,
    /// test fixtures) build a [`CalendarIcsEventFields`] and route
    /// through here so the same validity rules apply uniformly.
    pub fn new(fields: CalendarIcsEventFields<'a>) -> Result<Self, ValidationError> {
        let timing = CalendarEventTiming::from_flat_fields(
            fields.start_date,
            fields.start_time,
            fields.end_date,
            fields.end_time,
            fields.all_day,
        )?;
        Ok(Self {
            id: fields.id,
            title: fields.title,
            description: fields.description,
            recurrence: fields.recurrence,
            recurrence_exceptions: fields.recurrence_exceptions,
            timing,
            location: fields.location,
            timezone: fields.timezone,
            created_at: fields.created_at,
            updated_at: fields.updated_at,
            sequence: fields.sequence,
        })
    }

    /// Borrow the typed temporal shape. Use this when you need to
    /// pattern-match on the `AllDay` / `TimedSingleDay` /
    /// `TimedMultiDay` variants directly.
    pub const fn timing(&self) -> &CalendarEventTiming {
        &self.timing
    }
    pub const fn start_date(&self) -> Date {
        self.timing.start_date()
    }
    pub const fn start_time(&self) -> Option<TimeOfDay> {
        self.timing.start_time()
    }
    pub const fn end_date(&self) -> Option<Date> {
        self.timing.end_date()
    }
    pub const fn end_time(&self) -> Option<TimeOfDay> {
        self.timing.end_time()
    }
    pub const fn all_day(&self) -> bool {
        self.timing.all_day()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CalendarIcsError {
    InvalidDate {
        field: &'static str,
        value: String,
    },
    InvalidTime {
        field: &'static str,
        value: String,
    },
    InvalidTimestamp {
        field: &'static str,
        value: String,
    },
    InvalidRange {
        from: String,
        to: String,
    },
    InvalidRecurrenceJson(String),
    InvalidRecurrenceRule(String),
    InvalidRecurrenceExceptionJson(String),
    InvalidRecurrenceExceptionDate(String),
    /// A date arithmetic step (e.g. `next_date` for a VEVENT all-day
    /// DTEND) overflowed chrono's representable range. Practically
    /// reachable only via crafted input near `9999-12-31`. The
    /// `next_date` helper uses `checked_add_days` so this surfaces as
    /// a typed error rather than panicking on `+ Duration::days(1)`.
    DateOverflow {
        field: &'static str,
        value: String,
    },
    /// The deduped EXDATE list for a single VEVENT exceeds
    /// `MAX_RECURRENCE_EXDATES` (366, mirroring
    /// `MAX_CALENDAR_RECURRENCE_COUNT = 365`). Without this cap a
    /// peer envelope with `recurrence_exceptions = ["..."]*10000`
    /// would produce 10k EXDATE lines per VEVENT — a parser / UI
    /// DOS for any external client that loads the `.ics`.
    RecurrenceExdateLimitExceeded {
        count: usize,
        limit: usize,
    },
    /// A legacy fallback timestamp (the two parsers in
    /// `format_ics_timestamp` that accept naive wall-clock strings)
    /// carried a year before 1900. RFC 5545 §3.3.5 mandates 4-digit
    /// Gregorian years and most calendar clients silently drop
    /// VEVENTs with pre-1900 timestamps; without this rejection,
    /// e.g. `created_at = "0099-01-01T00:00:00"` would produce
    /// `00990101T000000Z`, survive the export, and get eaten by the
    /// receiving client.
    PreGregorianTimestampYear {
        field: &'static str,
        year: i32,
    },
    /// an internal post-condition
    /// the export pipeline relies on did not hold at runtime. These
    /// post-conditions encode contracts that hold today (e.g. a
    /// `normalize_recurrence_rule` pass guarantees `FREQ` and
    /// `INTERVAL` are present and well-typed; `is_date_value_event`
    /// guarantees `start_time` is `Some` on the timed branch). Pre-
    /// fix the export panicked on a contract violation; post-fix the
    /// caller surfaces the typed error and the receiving sync
    /// pipeline routes it through the existing `Validation` lane
    /// alongside every other malformed-payload signal.
    InternalContractViolation {
        field: &'static str,
        detail: &'static str,
    },
}

/// non-fatal observations produced while building an
/// ICS export. Returned alongside the rendered string by
/// [`super::emit::export_calendar_ics_with_warnings`] so callers can surface
/// them in diagnostics, the conflict log, or a UI banner.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CalendarIcsWarning {
    /// re-export of [`crate::validation::RecurrenceWarning`]
    /// produced by the recurrence normalizer. Lifted into the calendar
    /// surface so callers don't have to import from the validation
    /// module just to interpret a calendar warning.
    Recurrence(crate::validation::RecurrenceWarning),
    /// a `created_at` / `updated_at` value did not
    /// parse as RFC 3339 and the legacy fallback parsers (which
    /// silently treat the wall-clock as UTC) accepted it instead.
    /// The receiving sync diagnostic / error log should surface this
    /// so a stuck-naive timestamp doesn't drift across timezones on
    /// every export.
    LegacyNaiveTimestamp { field: &'static str, value: String },
    /// a SUMMARY / DESCRIPTION / LOCATION value
    /// exceeded `MAX_VEVENT_TEXT_LENGTH` and was truncated at the
    /// export boundary. RFC 5545 doesn't specify a hard cap, but
    /// many calendar clients (Apple Calendar, Outlook) impose
    /// practical limits and either reject or silently truncate
    /// over-long lines. The write-time validators (`MAX_TITLE_LENGTH
    /// = 1000`) already enforce this for canonical events; this
    /// warning catches sync-imported or legacy rows that bypass
    /// those gates.
    TextTruncated {
        field: &'static str,
        original_chars: usize,
        truncated_to: usize,
    },
}

impl fmt::Display for CalendarIcsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidDate { field, value } => {
                write!(f, "invalid {field} date '{value}', expected YYYY-MM-DD")
            }
            Self::InvalidTime { field, value } => {
                write!(f, "invalid {field} time '{value}', expected HH:MM")
            }
            Self::InvalidTimestamp { field, value } => {
                write!(f, "invalid {field} timestamp '{value}'")
            }
            Self::InvalidRange { from, to } => {
                write!(f, "to ({to}) cannot be before from ({from})")
            }
            Self::InvalidRecurrenceJson(raw) => {
                write!(f, "invalid recurrence JSON: {raw}")
            }
            Self::InvalidRecurrenceRule(message) => write!(f, "invalid recurrence rule: {message}"),
            Self::InvalidRecurrenceExceptionJson(raw) => {
                write!(f, "invalid recurrence exceptions JSON: {raw}")
            }
            Self::InvalidRecurrenceExceptionDate(value) => {
                write!(
                    f,
                    "invalid recurrence exception date '{value}', expected YYYY-MM-DD"
                )
            }
            Self::DateOverflow { field, value } => {
                write!(
                    f,
                    "date overflow computing next day for {field}='{value}' (chrono representable range exceeded)"
                )
            }
            Self::RecurrenceExdateLimitExceeded { count, limit } => {
                write!(
                    f,
                    "recurrence_exceptions produced {count} EXDATE lines, exceeding the cap of {limit} per VEVENT"
                )
            }
            Self::PreGregorianTimestampYear { field, year } => {
                write!(
                    f,
                    "{field} year {year} is before 1900 (RFC 5545 §3.3.5 requires 4-digit Gregorian timestamps; many clients drop VEVENTs that violate this)"
                )
            }
            Self::InternalContractViolation { field, detail } => {
                write!(
                    f,
                    "internal export contract violation on '{field}': {detail}"
                )
            }
        }
    }
}

impl Error for CalendarIcsError {}
