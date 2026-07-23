use crate::error::StoreError;
use lorvex_domain::calendar::CalendarEventTiming;
use lorvex_domain::calendar_ics::{CalendarIcsEvent, CalendarIcsEventFields};
use lorvex_domain::time::{Date, TimeOfDay};
use lorvex_domain::validation::ValidationError;
use rusqlite::{params, Connection};

/// Owned-field bundle accepted by [`CalendarIcsEventRecord::new`]. The
/// underlying record collapses the `(start_date, start_time, end_date,
/// end_time, all_day)` quintuple into a single typed
/// [`CalendarEventTiming`], so the SQL row mapper continues to express
/// the five flat fields and routes them through
/// [`CalendarEventTiming::from_flat_fields`] inside [`CalendarIcsEventRecord::new`].
#[derive(Debug, Clone)]
pub struct CalendarIcsEventRecordFields {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub start_date: Date,
    pub start_time: Option<TimeOfDay>,
    pub end_date: Option<Date>,
    pub end_time: Option<TimeOfDay>,
    pub all_day: bool,
    pub location: Option<String>,
    pub timezone: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// Wire-shape DB row that converts to a [`CalendarIcsEvent`] for ICS export.
///
/// # Invariants enforced at construction (#3287)
/// - The `(start_date, start_time, end_date, end_time, all_day)`
///   quintuple is bundled into a single typed [`CalendarEventTiming`]
///   so every illegal combination (e.g. `all_day = true` with a
///   non-`None` `start_time`, or `end_date < start_date`) is
///   non-representable, so the export pipeline does not need
///   defensive guards at every branch for invalid combinations.
#[derive(Debug, Clone)]
pub struct CalendarIcsEventRecord {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    /// Typed temporal shape. The `start_date()` / `start_time()` /
    /// `end_date()` / `end_time()` / `all_day()` accessors delegate to
    /// the typed projection.
    pub timing: CalendarEventTiming,
    pub location: Option<String>,
    pub timezone: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl CalendarIcsEventRecord {
    /// Build a [`CalendarIcsEventRecord`], enforcing temporal validity
    /// at construction via the typed [`CalendarEventTiming::from_flat_fields`]
    /// gate. The SQL row mapper converts a propagated `ValidationError`
    /// into a `FromSqlConversionFailure` so the per-row error shape
    /// stays consistent with the existing column-parse-failure paths.
    pub fn new(fields: CalendarIcsEventRecordFields) -> Result<Self, ValidationError> {
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
        })
    }

    /// Borrow the typed temporal shape.
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

    pub fn as_ics_event(&self) -> CalendarIcsEvent<'_> {
        let (start_date, start_time, end_date, end_time, all_day) = self.timing.as_flat_fields();
        CalendarIcsEvent::new(CalendarIcsEventFields {
            id: &self.id,
            title: &self.title,
            description: self.description.as_deref(),
            recurrence: self.recurrence.as_deref(),
            recurrence_exceptions: self.recurrence_exceptions.as_deref(),
            start_date,
            start_time,
            end_date,
            end_time,
            all_day,
            location: self.location.as_deref(),
            timezone: self.timezone.as_deref(),
            created_at: &self.created_at,
            updated_at: &self.updated_at,
            sequence: derive_sequence(&self.created_at, &self.updated_at),
        })
        // Construction is infallible here because the record's `timing`
        // already passed the same validity gate; the round-trip through
        // `as_flat_fields → from_flat_fields` is the identity on every
        // legal combination.
        .expect("record timing already validated at construction")
    }
}

/// derive an RFC 5545 §3.8.7.4 SEQUENCE value from
/// the gap between `created_at` and `updated_at`. The sequence MUST
/// be non-decreasing across consecutive edits to the same VEVENT;
/// using "seconds elapsed since creation" trivially preserves that
/// invariant for any sequence of normal edits to a single row, since
/// `updated_at` is bumped monotonically by every write surface (HLC
/// merge, MCP write, sync apply). Edge cases handled defensively:
///
/// - `created_at == updated_at` → 0 (matches the unedited case).
/// - Unparseable timestamps → 0 (no false-positive edit signal — the
///   downstream client will treat the row as a fresh publication).
/// - Negative gap (clock skew or peer-merged HLC bump that lowered
///   `updated_at` below `created_at`) → 0; the next legitimate edit
///   still increases the value monotonically.
/// - Gap exceeding `u32::MAX` seconds (~136 years) → saturate to
///   `u32::MAX` so the type can't wrap.
fn derive_sequence(created_at: &str, updated_at: &str) -> u32 {
    let parse = |s: &str| {
        chrono::DateTime::parse_from_rfc3339(s)
            .map(|t| t.timestamp())
            .ok()
    };
    let (Some(created), Some(updated)) = (parse(created_at), parse(updated_at)) else {
        return 0;
    };
    let diff = updated.saturating_sub(created);
    if diff <= 0 {
        return 0;
    }
    u32::try_from(diff).unwrap_or(u32::MAX)
}

pub fn list_calendar_events_for_ics(
    conn: &Connection,
    from: &str,
    to: &str,
) -> Result<Vec<CalendarIcsEventRecord>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, title, description, recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id) \
                AS recurrence_exceptions, \
                start_date, start_time, end_date, end_time, all_day, location, timezone, \
                created_at, updated_at \
         FROM calendar_events \
         WHERE start_date <= ?2 AND COALESCE(end_date, start_date) >= ?1 \
         ORDER BY start_date ASC, start_time ASC, id ASC",
    )?;

    let rows = stmt.query_map(params![from, to], |row| {
        let fields = CalendarIcsEventRecordFields {
            id: row.get("id")?,
            title: row.get("title")?,
            description: row.get("description")?,
            recurrence: row.get("recurrence")?,
            recurrence_exceptions: row.get("recurrence_exceptions")?,
            start_date: row.get("start_date")?,
            start_time: row.get("start_time")?,
            end_date: row.get("end_date")?,
            end_time: row.get("end_time")?,
            all_day: row.get("all_day")?,
            location: row.get("location")?,
            timezone: row.get("timezone")?,
            created_at: row.get("created_at")?,
            updated_at: row.get("updated_at")?,
        };
        // Lift a typed-timing ValidationError into the rusqlite
        // per-row error shape so the existing tolerant collection
        // path (or any caller's per-row skip) handles it the same as
        // a column-parse failure.
        CalendarIcsEventRecord::new(fields).map_err(|err| {
            rusqlite::Error::FromSqlConversionFailure(
                0,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    err.to_string(),
                )),
            )
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(StoreError::from)
}

#[cfg(test)]
mod sequence_tests {
    use super::derive_sequence;

    #[test]
    fn derive_sequence_is_zero_when_unedited() {
        assert_eq!(
            derive_sequence("2026-03-17T08:00:00Z", "2026-03-17T08:00:00Z"),
            0
        );
    }

    #[test]
    fn derive_sequence_counts_seconds_between_create_and_update() {
        assert_eq!(
            derive_sequence("2026-03-17T08:00:00Z", "2026-03-17T08:01:30Z"),
            90
        );
    }

    #[test]
    fn derive_sequence_is_zero_for_negative_gap() {
        // Peer HLC merge could lower updated_at below created_at; the
        // export must not panic or wrap and the SEQUENCE stays 0
        // until the next legitimate edit.
        assert_eq!(
            derive_sequence("2026-03-17T08:00:00Z", "2026-03-16T08:00:00Z"),
            0
        );
    }

    #[test]
    fn derive_sequence_is_zero_on_unparseable_input() {
        assert_eq!(
            derive_sequence("not-a-timestamp", "2026-03-17T08:00:00Z"),
            0
        );
        assert_eq!(
            derive_sequence("2026-03-17T08:00:00Z", "not-a-timestamp"),
            0
        );
    }

    #[test]
    fn derive_sequence_is_monotonic_across_consecutive_edits() {
        // Three sequential edits to the same row produce a strictly
        // non-decreasing SEQUENCE — the RFC 5545 §3.8.7.4 invariant.
        let s1 = derive_sequence("2026-03-17T08:00:00Z", "2026-03-17T08:01:00Z");
        let s2 = derive_sequence("2026-03-17T08:00:00Z", "2026-03-17T08:02:00Z");
        let s3 = derive_sequence("2026-03-17T08:00:00Z", "2026-03-17T08:03:00Z");
        assert!(
            s1 < s2 && s2 < s3,
            "sequence must be monotonic: {s1} < {s2} < {s3}"
        );
    }
}
