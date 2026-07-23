//! [`UpdateCalendarEventMutation`] descriptor + EXDATE
//! skeleton-preserve policy.
//!
//! Owns the rule that decides whether a recurrence patch keeps the
//! stored exception list: when the patch leaves the instance grid
//! (FREQ / INTERVAL / BYDAY / BYMONTHDAY / BYMONTH / BYSETPOS /
//! BYHOUR / BYMINUTE / BYSECOND / WKST) unchanged AND neither
//! anchor component (`start_date`, `start_time`) shifted, every
//! prior EXDATE still names a valid instance and survives.
//! Otherwise the exception list drops because the stored
//! timestamps may no longer correspond to any instance at all.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::{sync_timestamp_now, AllDayPatch, EventId, Patch};
use lorvex_store::repositories::calendar_event_write::{self, CalendarEventUpdatePatch};
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

use crate::calendar_normalization::{
    normalize_calendar_update, CalendarUpdateExisting, CalendarUpdateInput,
    NormalizedCalendarUpdate,
};
use crate::mutation::{Mutation, MutationOutput};

use super::attendees::materialize_attendees;
use super::load::load_calendar_event_json;
use super::recurrence_skeleton::recurrence_skeleton_matches;
use super::{AttendeeShadowInput, CalendarEventOpError, CalendarEventUpdateInput};

/// Mutation descriptor for updating a calendar event. Owns the
/// EXDATE skeleton-preserve policy: when a recurrence patch keeps
/// the instance-grid skeleton (FREQ / INTERVAL / BYDAY / BYMONTHDAY
/// / BYMONTH / BYSETPOS / WKST) unchanged, the stored exception
/// list survives because every prior EXDATE still names a valid
/// instance. When the skeleton shifts (or recurrence clears
/// outright), the exception list drops because the stored
/// timestamps may no longer point at any instance at all.
pub struct UpdateCalendarEventMutation {
    event_id: String,
    before: Value,
    before_recurrence: Option<String>,
    pub(super) before_start_time: Option<String>,
    pub(super) before_start_date: String,
    pub(super) normalized: NormalizedCalendarUpdate,
    attendees: Patch<Vec<AttendeeShadowInput>>,
}

impl UpdateCalendarEventMutation {
    /// Capture the pre-mutation row + normalize the inputs.
    /// Surfaces load `before` via their preferred reader; here we
    /// take the JSON value directly so this module doesn't need a
    /// per-surface row-shape dependency.
    ///
    /// `before_recurrence` is the raw RRULE/RDATE JSON of the
    /// existing row, used by the EXDATE skeleton-preserve check.
    pub fn new(
        input: CalendarEventUpdateInput,
        existing: CalendarUpdateExisting,
        before: Value,
        before_recurrence: Option<String>,
    ) -> Result<Self, CalendarEventOpError> {
        let attendees = input.attendees.clone();
        let event_id = input.id.clone();
        let before_start_time = existing.start_time.clone();
        let before_start_date = existing.start_date.clone();
        // `start_date` is `Patch<String>` on the input for surface
        // symmetry; the only meaningful states for the row are
        // `Unset` (leave as-is) and `Set` (re-anchor). `Clear` is
        // rejected here so the normalizer keeps consuming
        // `Option<String>`.
        let start_date = match input.start_date {
            Patch::Unset => None,
            Patch::Set(value) => Some(value),
            Patch::Clear => {
                return Err(CalendarEventOpError::Validation(
                    "start_date cannot be cleared (use Patch::Set to re-anchor, omit to leave alone)"
                        .to_string(),
                ));
            }
        };
        let normalized = normalize_calendar_update(
            CalendarUpdateInput {
                title: input.title,
                recurrence: input.recurrence,
                timezone: input.timezone,
                start_date,
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
            },
            existing,
        )
        .map_err(|e| CalendarEventOpError::Validation(e.to_string()))?;
        Ok(Self {
            event_id,
            before,
            before_recurrence,
            before_start_time,
            before_start_date,
            normalized,
            attendees,
        })
    }

    pub fn event_id(&self) -> &str {
        &self.event_id
    }

    pub const fn dst_guard(&self) -> &super::CalendarDstGuard {
        &self.normalized.dst_guard
    }

    /// True when the patch shifts the event anchor (start_date or
    /// start_time) to a different wall-clock value. EXDATE entries
    /// name exact instance timestamps (date + time); a shift in
    /// either component moves every instance to a new grid, so any
    /// preserved EXDATE no longer refers to a real occurrence.
    ///
    /// `Patch::Set` with the same value is a no-op (round-tripping
    /// the field while editing something else, see) and is
    /// not flagged as a shift. A `start_date` re-anchor (Monday →
    /// Wednesday) is treated identically to a `start_time` shift
    pub(super) fn is_anchor_shift(&self) -> bool {
        let start_time_shifted = match &self.normalized.start_time {
            Patch::Set(value) => self.before_start_time.as_deref() != Some(value.as_str()),
            Patch::Clear => self.before_start_time.is_some(),
            Patch::Unset => false,
        };
        let start_date_shifted = match &self.normalized.start_date {
            Some(value) => value.as_str() != self.before_start_date.as_str(),
            None => false,
        };
        start_time_shifted || start_date_shifted
    }
}

impl Mutation for UpdateCalendarEventMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let now = sync_timestamp_now();

        // EXDATE entries name exact recurrence-instance timestamps
        // (date + time). Any anchor shift — either a `start_date`
        // re-anchor (Monday → Wednesday) or a `start_time`
        // time-of-day edit (9 AM → 10 AM) — moves every instance
        // onto a new grid, so any preserved EXDATE no longer
        // refers to a real occurrence. Treat anchor shifts as a
        // "skeleton differs" signal even when the RRULE itself is
        // unchanged — this catches editors that shift the anchor
        // via DTSTART rather than via BYHOUR/BYDAY. See,
        let anchor_shifted = self.is_anchor_shift();
        let recurrence_exceptions_patch: Patch<&str> = match &self.normalized.recurrence {
            Patch::Unset => {
                // RRULE not edited this patch, but if the anchor
                // shifted we still must drop EXDATE.
                if anchor_shifted {
                    Patch::Clear
                } else {
                    Patch::Unset
                }
            }
            Patch::Clear => Patch::Clear,
            Patch::Set(new_rec) => {
                let preserve = !anchor_shifted
                    && self
                        .before_recurrence
                        .as_deref()
                        .is_some_and(|old| recurrence_skeleton_matches(old, new_rec));
                if preserve {
                    Patch::Unset
                } else {
                    Patch::Clear
                }
            }
        };

        let patch = CalendarEventUpdatePatch {
            event_id: &self.event_id,
            title: self.normalized.title.as_deref(),
            description: self.normalized.description.as_deref(),
            recurrence: self.normalized.recurrence.as_deref(),
            recurrence_exceptions: recurrence_exceptions_patch,
            timezone: self.normalized.timezone.as_deref(),
            start_date: self.normalized.start_date.as_deref(),
            start_time: self.normalized.start_time.as_deref(),
            end_date: self.normalized.end_date.as_deref(),
            end_time: self.normalized.end_time.as_deref(),
            all_day: AllDayPatch::from_optional_bool(self.normalized.all_day),
            location: self.normalized.location.as_deref(),
            url: self.normalized.url.as_deref(),
            color: self.normalized.color.as_deref(),
            event_type: match &self.normalized.event_type {
                Patch::Unset => Patch::Unset,
                Patch::Clear => Patch::Clear,
                Patch::Set(value) => Patch::Set(value.as_str()),
            },
            person_name: self.normalized.person_name.as_deref(),
            version: &version,
            now: &now,
        };
        calendar_event_write::apply_calendar_event_update(conn, &patch)?;

        // `attendees` is replace-set semantics:
        //   - `Unset` — leave existing rows alone.
        //   - `Clear` — drop every attendee row (collapses to an empty
        //     slice so the same `materialize_attendees` hygiene path
        //     runs).
        //   - `Set(list)` — replace with the supplied list (empty list
        //     behaves like `Clear`).
        let attendees_slice: Option<&[AttendeeShadowInput]> = match &self.attendees {
            Patch::Unset => None,
            Patch::Clear => Some(&[]),
            Patch::Set(list) => Some(list.as_slice()),
        };
        if let Some(attendees) = attendees_slice {
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
                "calendar event {} disappeared after update",
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
            format!("Updated calendar event '{title}'"),
        ))
    }
}
