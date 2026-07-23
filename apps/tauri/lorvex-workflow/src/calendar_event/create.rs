//! [`CreateCalendarEventMutation`] descriptor.
//!
//! Captures the normalized create inputs + a freshly minted event
//! id, then on `apply` runs the row INSERT, materializes attendees,
//! and returns the persisted JSON row as the mutation's `after`
//! snapshot. Per-surface sync / audit / IPC concerns stay outside.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::{sync_timestamp_now, EventId};
use lorvex_store::repositories::calendar_event_write::{self, CalendarEventCreateParams};
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

use crate::calendar_normalization::{
    normalize_calendar_create, CalendarCreateInput, CalendarDstGuard, NormalizedCalendarCreate,
};
use crate::mutation::{Mutation, MutationOutput};

use super::attendees::materialize_attendees;
use super::load::load_calendar_event_json;
use super::{AttendeeShadowInput, CalendarEventCreateInput, CalendarEventOpError};

/// Mutation descriptor for creating a calendar event.
///
/// Construct via [`CreateCalendarEventMutation::new`], which captures
/// the normalized inputs and the to-be-minted `event_id`. The
/// descriptor inserts the row, materializes attendees, and returns
/// the persisted JSON row as the mutation's `after` snapshot.
pub struct CreateCalendarEventMutation {
    event_id: String,
    normalized: NormalizedCalendarCreate,
    attendees: Option<Vec<AttendeeShadowInput>>,
}

impl CreateCalendarEventMutation {
    /// Validate + normalize the inputs and stage a create against
    /// the supplied id. The descriptor is consumed by the surface's
    /// mutation executor (`execute_mcp_mutation`, etc.).
    pub fn new(
        event_id: impl Into<String>,
        input: CalendarEventCreateInput,
    ) -> Result<Self, CalendarEventOpError> {
        let attendees = input.attendees.clone();
        let normalized = normalize_calendar_create(CalendarCreateInput {
            title: input.title,
            recurrence: input.recurrence,
            timezone: input.timezone,
            start_date: input.start_date,
            start_time: input.start_time,
            end_date: input.end_date,
            end_time: input.end_time,
            all_day: input.all_day,
            description: input.description,
            location: input.location,
            url: input.url,
            color: input.color,
            event_type: input.event_type,
            person_name: input.person_name,
        })
        .map_err(|e| CalendarEventOpError::Validation(e.to_string()))?;
        Ok(Self {
            event_id: event_id.into(),
            normalized,
            attendees,
        })
    }

    /// The event id this mutation will write to.
    pub fn event_id(&self) -> &str {
        &self.event_id
    }

    /// The DST guard surfaced by normalization. Surfaces consult
    /// this after `apply` to optionally append a diagnostic
    /// `error_log` row when the wall clock landed on an ambiguous
    /// fall-back hour.
    pub const fn dst_guard(&self) -> &CalendarDstGuard {
        &self.normalized.dst_guard
    }
}

impl Mutation for CreateCalendarEventMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let now = sync_timestamp_now();
        // `recurrence_exceptions = '[]'` (recurring, no
        // exceptions) from `NULL` (non-recurring). The list now
        // lives in `calendar_event_recurrence_exceptions` and an
        // empty per-event registry is the natural representation
        // for "recurring with no exceptions" — the
        // `json_group_array` projection collapses an empty set
        // back to NULL on read. Callers that need to distinguish
        // "recurring" from "non-recurring" check `recurrence` (the
        // RRULE) directly; the exceptions column no longer
        // carries that bit.
        let recurrence_exceptions: Option<String> = None;
        let event_type = self.normalized.event_type.as_str();

        calendar_event_write::create_calendar_event(
            conn,
            &CalendarEventCreateParams {
                id: &self.event_id,
                title: &self.normalized.title,
                description: self.normalized.description.as_deref(),
                recurrence: self.normalized.recurrence.as_deref(),
                recurrence_exceptions: recurrence_exceptions.as_deref(),
                timezone: self.normalized.timezone.as_deref(),
                start_date: &self.normalized.start_date,
                start_time: self.normalized.start_time.as_deref(),
                end_date: self.normalized.end_date.as_deref(),
                end_time: self.normalized.end_time.as_deref(),
                all_day: self.normalized.all_day,
                location: self.normalized.location.as_deref(),
                url: self.normalized.url.as_deref(),
                color: self.normalized.color.as_deref(),
                event_type,
                person_name: self.normalized.person_name.as_deref(),
                version: &version,
                now: &now,
            },
        )?;

        if let Some(attendees) = &self.attendees {
            materialize_attendees(
                conn,
                &EventId::from_trusted(self.event_id.clone()),
                attendees,
            )
            .map_err(|e| match e {
                CalendarEventOpError::Validation(m) => StoreError::Validation(m),
                CalendarEventOpError::Store(s) => s,
            })?;
        }

        let event = load_calendar_event_json(conn, &self.event_id)?.ok_or_else(|| {
            StoreError::Invariant(format!(
                "calendar event {} disappeared after insert",
                self.event_id
            ))
        })?;
        let title = event
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_string();
        Ok(MutationOutput::new(
            event,
            format!("Created calendar event '{title}'"),
        ))
    }
}
