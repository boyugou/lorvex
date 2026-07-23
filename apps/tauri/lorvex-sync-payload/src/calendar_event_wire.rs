//! Canonical serde wire shape for calendar-event update + create
//! payloads.
//!
//! The same field bundle was declared once per surface
//! (Tauri IPC, MCP tool args, CLI dispatch), each carrying its own
//! `Patch<T>` annotations and risking field-name drift on every new
//! nullable column. This module owns the single source of truth so
//! every renderer/JSON tool/CLI flag set deserialize through the same
//! struct.
//!
//! ## Trust-boundary parses left to the surface
//!
//! - **PARTSTAT validation.** [`AttendeeWire::status`] carries the raw
//!   RFC 5545 string; surfaces strict-parse it into the canonical
//!   `AttendeeStatus` enum when lifting to the workflow input. The
//!   wire shape stays surface-agnostic.
//! - **UUID / id shape.** [`CalendarEventUpdateWire::id`] is a bare
//!   `String`; surfaces (e.g. Tauri's `validate_uuid_id`) enforce the
//!   id format before the workflow call.
//! - **CLI-only borrowed lifetimes.** The CLI's dispatch path holds
//!   string slices on the clap argv allocation; it builds its own
//!   `CalendarEventUpdateFields<'a>` for that one path and routes
//!   through the same workflow input.
//!
//! ## start_date is `Patch<String>` with `Patch::Clear` rejected
//!
//! `start_date` is a required column on every calendar event row; a
//! patch can re-anchor it (`Set`) or leave it alone (`Unset`), but
//! "clear to null" is not a meaningful row state. The wire still uses
//! `Patch<String>` so the field-shape stays homogeneous with its
//! siblings (`start_time`, `end_date`, `end_time`); the
//! [`CalendarEventUpdateWire::into_start_date_option`] lifter rejects
//! `Patch::Clear` with a typed validation error string at the surface
//! boundary.

use lorvex_domain::Patch;
use serde::{Deserialize, Serialize};

#[cfg(feature = "schemars")]
use schemars::JsonSchema;

/// Wire shape for a single attendee on the calendar-event update +
/// create surfaces.
///
/// `status` is the raw PARTSTAT string; surfaces strict-parse it into
/// [`lorvex_domain::AttendeeStatus`] before handing the lifted struct
/// to the workflow layer (see the module docs).
#[derive(Debug, Clone, Deserialize, Serialize)]
#[cfg_attr(feature = "schemars", derive(JsonSchema))]
pub struct AttendeeWire {
    #[cfg_attr(feature = "schemars", schemars(description = "Attendee email address"))]
    pub email: String,
    #[cfg_attr(feature = "schemars", schemars(description = "Attendee display name"))]
    #[serde(default)]
    pub name: Option<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "RSVP status: accepted, declined, tentative, needs-action")
    )]
    #[serde(default)]
    pub status: Option<String>,
}

/// Canonical wire shape for `update_calendar_event` across every
/// destination (Tauri IPC, MCP tool args, CLI JSON dispatch).
///
/// Every nullable column uses `Patch<T>` so an absent JSON key is
/// `Patch::Unset` ("don't touch"), an explicit JSON `null` is
/// `Patch::Clear` ("nullify"), and any value is `Patch::Set(value)`.
///
/// `attendees: Patch<Vec<AttendeeWire>>` carries replace-set
/// semantics: `Unset` leaves existing rows alone, `Clear` deletes all
/// attendees, `Set([...])` replaces with the supplied list.
///
/// See the module docs for `start_date`'s asymmetric handling and the
/// PARTSTAT / id trust boundaries left to each surface.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[cfg_attr(feature = "schemars", derive(JsonSchema))]
pub struct CalendarEventUpdateWire {
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Calendar event ID to update")
    )]
    pub id: String,
    #[cfg_attr(feature = "schemars", schemars(description = "New event title"))]
    #[serde(default)]
    pub title: Option<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Patch the recurrence rule as a JSON string. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub recurrence: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(
            description = "Patch timezone with an IANA timezone like America/Los_Angeles. Use null to clear."
        )
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub timezone: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "New start date in YYYY-MM-DD")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub start_date: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "New start time in HH:MM. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub start_time: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "New end date in YYYY-MM-DD. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub end_date: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "New end time in HH:MM. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub end_time: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Whether the event is all-day")
    )]
    #[serde(default)]
    pub all_day: Option<bool>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Event description. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub description: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Event location. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub location: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(
            description = "URL associated with the event (e.g. meeting link, ticket URL). Use null to clear."
        )
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub url: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Hex color. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub color: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(
            description = "Event type: event, birthday, anniversary, memorial. Use null to clear."
        )
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub event_type: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(description = "Person name. Use null to clear.")
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub person_name: Patch<String>,
    #[cfg_attr(
        feature = "schemars",
        schemars(
            description = "Replace attendees list. Use null to clear all attendees; omit to leave the existing list alone; pass [] to clear; pass a non-empty array to replace."
        )
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub attendees: Patch<Vec<AttendeeWire>>,
}

impl CalendarEventUpdateWire {
    /// Lift `start_date` from the wire's `Patch<String>` into the
    /// workflow input's `Option<String>` shape. Rejects `Patch::Clear`
    /// — `start_date` is a required column, so "clear to null" is not
    /// a representable row state. Surfaces map the returned error
    /// string into their typed validation error.
    pub fn into_start_date_option(start_date: Patch<String>) -> Result<Option<String>, String> {
        match start_date {
            Patch::Unset => Ok(None),
            Patch::Set(value) => Ok(Some(value)),
            Patch::Clear => Err(
                "start_date cannot be cleared (use Patch::Set to re-anchor, omit to leave alone)"
                    .to_string(),
            ),
        }
    }
}
