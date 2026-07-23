//! Shared output types for calendar-timeline queries.

use lorvex_domain::time::{Date, TimeOfDay};
use lorvex_domain::validation::ValidationError;
use lorvex_domain::{CalendarEventTiming, CanonicalCalendarEventType};
use serde::Serialize;

/// Owned-field bundle accepted by [`CalendarEventRow::new`]. Keeps the
/// constructor signature readable (the underlying struct has 18 fields
/// once the temporal quintuple is bundled into a single typed
/// [`CalendarEventTiming`], well past the ergonomic ceiling for a
/// positional `new(...)`). Fixtures, SQL row mappers, and ad-hoc
/// constructors continue to express the five flat temporal fields and
/// route them through [`CalendarEventTiming::from_flat_fields`] inside
/// [`CalendarEventRow::new`].
#[derive(Debug, Clone)]
pub struct CalendarEventRowFields {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub timezone: Option<String>,
    pub start_date: Date,
    pub start_time: Option<TimeOfDay>,
    pub end_date: Option<Date>,
    pub end_time: Option<TimeOfDay>,
    pub all_day: bool,
    pub location: Option<String>,
    pub color: Option<String>,
    pub event_type: CanonicalCalendarEventType,
    pub person_name: Option<String>,
    pub url: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

/// Whether the event originates from Lorvex's own calendar_events table
/// or from an external provider (e.g. Apple Calendar, Google Calendar).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum TimelineSource {
    Canonical,
    Provider,
}

/// A single occurrence on a calendar timeline (post-expansion).
///
/// This struct does NOT carry recurrence / recurrence_exceptions fields;
/// each recurring event is expanded into individual `CalendarTimelineItem`s
/// before reaching this layer.
///
/// # Invariants enforced at construction (#3287, #3289)
/// - The `(start_date, start_time, end_date, end_time, all_day)`
///   quintuple is bundled into a single typed [`CalendarEventTiming`]
///   so every illegal combination (e.g. `all_day = true` with a non-`None`
///   `start_time`, or `end_date < start_date`) is non-representable —
///   the renderer + scheduler treat all-day items differently from
///   time-of-day items, and a flat five-field carrier would let
///   schema-illegal combinations compile cleanly.
///
/// Fields are `pub(crate)` so the loaders inside `calendar_timeline/` can
/// build them with struct literals during query mapping. External readers
/// use the borrow accessors below; external writers go through
/// [`CalendarTimelineItem::new`].
///
/// Wire format: the `timing` field flattens at serialize time into
/// five top-level keys (`start_date`, `start_time`, `end_date`,
/// `end_time`, `all_day`), each always emitted (no
/// `skip_serializing_if`) so snapshots and the hand-rolled `json!`
/// envelopes in MCP / Tauri see byte-identical output.
#[derive(Debug, Clone, Serialize)]
pub struct CalendarTimelineItem {
    pub(crate) source: TimelineSource,
    pub(crate) editable: bool,
    /// Canonical UUID or composite `"kind:scope:key"` for provider events.
    pub(crate) id: String,
    pub(crate) title: String,
    /// Typed temporal shape. Flattened at serialize time so the JSON
    /// emits five flat top-level keys (`start_date`, `start_time`,
    /// `end_date`, `end_time`, `all_day`) directly on the carrier
    /// object.
    #[serde(flatten)]
    pub(crate) timing: CalendarEventTiming,
    pub(crate) location: Option<String>,
    pub(crate) color: Option<String>,
    pub(crate) event_type: String,
    pub(crate) person_name: Option<String>,
    pub(crate) timezone: Option<String>,
    /// `None` for canonical events; populated for provider events.
    pub(crate) provider_kind: Option<String>,
    /// `None` for canonical events; populated for provider events.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) provider_scope: Option<String>,
    /// Whether this occurrence is part of a recurring event series.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub(crate) is_recurring: bool,
    /// Original time kind from the provider event: `"floating"`, `"utc"`, or `"tzid"`.
    /// `None` for canonical events.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) source_time_kind: Option<String>,
    /// Original IANA timezone identifier when `source_time_kind == "tzid"`.
    /// `None` for canonical events or when the provider event is floating/UTC.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) source_tzid: Option<String>,
    /// URL associated with the event (e.g. a meeting link).
    /// `None` for provider events or when not set.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) url: Option<String>,
    /// JSON array of attendees for provider events.
    /// Format: `[{"email":"...","name":"...","status":"accepted"}]`.
    /// `None` for canonical events or when the provider has no attendee data.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) attendees_json: Option<String>,
}

/// Owned-field bundle accepted by [`CalendarTimelineItem::new`]. Kept as a
/// dedicated input shape so the constructor parameter list stays readable
/// (the underlying struct has 22 fields, well past the point where a
/// positional `new(...)` becomes hostile).
///
/// The carrier struct stores a typed [`CalendarEventTiming`] enum so
/// illegal `(all_day, start_time, end_time)` combinations are
/// non-representable. This Fields shape accepts the flat five-field
/// input quintuple for ergonomics — fixtures, MCP / Tauri / sync
/// entry seams, and SQL row reads all produce the flat shape — and
/// routes it through [`CalendarEventTiming::from_flat_fields`] inside
/// [`new`].
#[derive(Debug, Clone)]
pub struct CalendarTimelineItemFields {
    pub source: TimelineSource,
    pub editable: bool,
    pub id: String,
    pub title: String,
    pub start_date: Date,
    pub start_time: Option<TimeOfDay>,
    pub end_date: Option<Date>,
    pub end_time: Option<TimeOfDay>,
    pub all_day: bool,
    pub location: Option<String>,
    pub color: Option<String>,
    pub event_type: String,
    pub person_name: Option<String>,
    pub timezone: Option<String>,
    pub provider_kind: Option<String>,
    pub provider_scope: Option<String>,
    pub is_recurring: bool,
    pub source_time_kind: Option<String>,
    pub source_tzid: Option<String>,
    pub url: Option<String>,
    pub attendees_json: Option<String>,
}

impl CalendarTimelineItem {
    /// Build a [`CalendarTimelineItem`], enforcing the temporal
    /// validity rules at construction time via the typed
    /// [`CalendarEventTiming::from_flat_fields`] gate. A flat
    /// five-column carrier (`start_date, start_time, end_date,
    /// end_time, all_day`) would let
    /// `CalendarTimelineItem { all_day: true,
    /// start_time: Some("09:00".into()), .. }` compile cleanly even
    /// though no production loader produces such a row — and
    /// downstream renderers would silently pick the time-of-day
    /// branch on top of an all-day shell. The typed enum makes
    /// every illegal
    /// combination non-representable.
    ///
    /// Returns the propagated `ValidationError` from the typed gate;
    /// callers at the SQL row-read layer use the per-row try-block
    /// fallback to log + skip the offending row instead of aborting
    /// the entire query.
    pub fn new(fields: CalendarTimelineItemFields) -> Result<Self, ValidationError> {
        let timing = CalendarEventTiming::from_flat_fields(
            fields.start_date,
            fields.start_time,
            fields.end_date,
            fields.end_time,
            fields.all_day,
        )?;
        Ok(Self {
            source: fields.source,
            editable: fields.editable,
            id: fields.id,
            title: fields.title,
            timing,
            location: fields.location,
            color: fields.color,
            event_type: fields.event_type,
            person_name: fields.person_name,
            timezone: fields.timezone,
            provider_kind: fields.provider_kind,
            provider_scope: fields.provider_scope,
            is_recurring: fields.is_recurring,
            source_time_kind: fields.source_time_kind,
            source_tzid: fields.source_tzid,
            url: fields.url,
            attendees_json: fields.attendees_json,
        })
    }

    pub const fn source(&self) -> &TimelineSource {
        &self.source
    }
    pub const fn editable(&self) -> bool {
        self.editable
    }
    pub fn id(&self) -> &str {
        &self.id
    }
    pub fn title(&self) -> &str {
        &self.title
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
    pub fn location(&self) -> Option<&str> {
        self.location.as_deref()
    }
    pub fn color(&self) -> Option<&str> {
        self.color.as_deref()
    }
    pub fn event_type(&self) -> &str {
        &self.event_type
    }
    pub fn person_name(&self) -> Option<&str> {
        self.person_name.as_deref()
    }
    pub fn timezone(&self) -> Option<&str> {
        self.timezone.as_deref()
    }
    pub fn provider_kind(&self) -> Option<&str> {
        self.provider_kind.as_deref()
    }
    pub fn provider_scope(&self) -> Option<&str> {
        self.provider_scope.as_deref()
    }
    pub const fn is_recurring(&self) -> bool {
        self.is_recurring
    }
    pub fn source_time_kind(&self) -> Option<&str> {
        self.source_time_kind.as_deref()
    }
    pub fn source_tzid(&self) -> Option<&str> {
        self.source_tzid.as_deref()
    }
    pub fn url(&self) -> Option<&str> {
        self.url.as_deref()
    }
    pub fn attendees_json(&self) -> Option<&str> {
        self.attendees_json.as_deref()
    }
}

/// A time range that blocks scheduling within a single day.
#[derive(Debug, Clone, Serialize)]
pub struct BlockingEventRange {
    pub source: TimelineSource,
    /// `Some(id)` only for canonical events.
    pub canonical_event_id: Option<String>,
    pub title: String,
    /// Minutes from midnight (start of the blocking window).
    pub start_minutes: i64,
    /// Minutes from midnight (end of the blocking window).
    pub end_minutes: i64,
    /// True if the provider data backing this range may be stale.
    /// Planning consumers should treat stale ranges conservatively
    /// (still block the time) but may surface a staleness indicator.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub stale: bool,
}

/// A row read directly from the `calendar_events` table (no expansion).
///
/// Used by text-search queries that return canonical events as stored,
/// without recurrence expansion or timezone projection.
///
/// # Invariants enforced at construction (#3287, #3289)
/// - The `(start_date, start_time, end_date, end_time, all_day)`
///   quintuple is bundled into a single typed [`CalendarEventTiming`]
///   so every illegal combination (e.g. `all_day = true` with a non-`None`
///   `start_time`, or `end_date < start_date`) is non-representable —
///   the renderer + scheduler treat all-day rows differently from
///   time-of-day rows, and a flat five-field carrier would let
///   schema-illegal combinations compile cleanly.
///
/// Wire format: the `timing` field flattens at serialize time into
/// five top-level keys (`start_date`, `start_time`, `end_date`,
/// `end_time`, `all_day`), each always emitted (no
/// `skip_serializing_if`) so snapshots, CLI changelog payloads, and
/// any MCP / Tauri envelope holding a `CalendarEventRow` see
/// byte-identical output.
#[derive(Debug, Clone, Serialize)]
pub struct CalendarEventRow {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub timezone: Option<String>,
    /// Typed temporal shape. Flattened at serialize time so the JSON
    /// emits five flat top-level keys (`start_date`, `start_time`,
    /// `end_date`, `end_time`, `all_day`) directly on the carrier
    /// object.
    #[serde(flatten)]
    pub timing: CalendarEventTiming,
    pub location: Option<String>,
    pub color: Option<String>,
    pub event_type: CanonicalCalendarEventType,
    pub person_name: Option<String>,
    pub url: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub version: String,
}

impl CalendarEventRow {
    /// Build a [`CalendarEventRow`], enforcing temporal validity at
    /// construction via the typed [`CalendarEventTiming::from_flat_fields`]
    /// gate. A flat five-column carrier (`start_date, start_time,
    /// end_date, end_time, all_day`) would let
    /// `CalendarEventRow { all_day: true, start_time: Some(...), .. }`
    /// compile cleanly even though no production loader produces
    /// such a row. The typed enum makes every illegal combination
    /// non-representable.
    ///
    /// Returns the propagated `ValidationError` from the typed gate;
    /// SQL row-mapper callers convert it into a `FromSqlConversionFailure`
    /// so the per-row error shape stays consistent with the existing
    /// `event_type` parse-failure path.
    pub fn new(fields: CalendarEventRowFields) -> Result<Self, ValidationError> {
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
            timezone: fields.timezone,
            timing,
            location: fields.location,
            color: fields.color,
            event_type: fields.event_type,
            person_name: fields.person_name,
            url: fields.url,
            created_at: fields.created_at,
            updated_at: fields.updated_at,
            version: fields.version,
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
