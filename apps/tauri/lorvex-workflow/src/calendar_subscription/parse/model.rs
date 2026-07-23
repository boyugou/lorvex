/// Cap on EXDATE entries per VEVENT — the recurrence engine has to
/// scan this list per occurrence, and a hostile feed could otherwise
/// emit megabytes of bogus exception dates.
pub(super) const MAX_EXDATES_PER_EVENT: usize = 5_000;

/// Cap on total VEVENTs accepted from a single ICS feed body. A 10MB
/// body can decode to 80-120k events with a handful
/// of bytes per skeletal `BEGIN:VEVENT/END:VEVENT` pair, blowing up
/// memory inside the writer transaction and the upsert pipeline.
/// 5,000 covers any realistic personal/team feed (a year of every
/// 15-minute slot is ~35k, well past anything a human curates) while
/// still bounding the worst case to a few MB of `ParsedEvent` state.
/// Excess events are dropped with a persisted parser diagnostic —
/// failing the entire feed would be worse UX than importing the
/// prefix that fits.
pub(super) const MAX_VEVENTS_PER_FEED: usize = 5_000;

pub struct IcsParseReport {
    pub events: Vec<ParsedEvent>,
    pub warnings: Vec<IcsParseWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IcsParseWarning {
    pub source: &'static str,
    pub message: String,
    pub details: Option<String>,
}

impl IcsParseWarning {
    pub(super) fn new(message: impl Into<String>, details: impl Into<String>) -> Self {
        Self {
            source: "sync.ics.parser_warning",
            message: message.into(),
            details: Some(details.into()),
        }
    }
}

/// One VEVENT, normalized for the upsert pass in
/// the subscription sync writer. All fields are already validated and
/// bounded — no caller needs to re-check lengths or escape rules.
#[derive(Debug)]
pub struct ParsedEvent {
    pub uid: String,
    pub summary: String,
    pub description: Option<String>,
    pub start_date: String,         // YYYY-MM-DD
    pub start_time: Option<String>, // HH:MM
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub location: Option<String>,
    pub organizer: Option<String>,
    /// For detached overrides: UID + RECURRENCE-ID composite key.
    /// None for master events (use bare UID as provider_event_key).
    pub recurrence_id: Option<String>,
    pub source_time_kind: String,    // "floating" | "utc" | "tzid"
    pub source_tzid: Option<String>, // e.g. "America/New_York"
    /// Raw RRULE value from the ICS feed (e.g., "FREQ=WEEKLY;BYDAY=MO").
    /// Stored in provider_calendar_events.recurrence for expansion.
    pub rrule: Option<String>,
    /// JSON array of EXDATE values as YYYY-MM-DD strings: `["2026-04-05","2026-04-12"]`.
    pub exdates_json: Option<String>,
    /// JSON array of attendees: `[{"email":"...","name":"...","rsvp":"..."}]`.
    pub attendees_json: Option<String>,
    /// URL property from the VEVENT (generic event URL or video call link).
    /// when no URL is present, falls back to the
    /// first ATTACH;FMTTYPE=… line whose value is a URI (binary inline
    /// ATTACH payloads are skipped — see `EventBuilder::parse_line`).
    pub url: Option<String>,
    /// VEVENT `SEQUENCE` (RFC 5545 §3.8.7.4). Breaks ties when
    /// the same UID/RECURRENCE-ID composite key appears more than once
    /// in a feed (multi-VEVENT same-UID merge). Defaults to 0 per spec.
    pub sequence: i64,
    /// VEVENT `DTSTAMP` (RFC 5545 §3.8.7.2). Tertiary tie-breaker for
    /// duplicate composite keys when SEQUENCE matches; later DTSTAMP
    /// wins. Stored as the raw ICS string (sortable lexicographically
    /// because both `YYYYMMDDTHHMMSSZ` and `YYYYMMDDTHHMMSS` collate
    /// chronologically when the format is consistent within a feed).
    pub dtstamp: Option<String>,
}
