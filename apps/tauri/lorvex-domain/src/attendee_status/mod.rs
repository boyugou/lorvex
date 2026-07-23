//! Canonical RFC 5545 PARTSTAT subset for calendar event attendees.
//!
//! Every surface (Tauri, MCP, sync apply, import, store
//! repositories) accepts only the canonical hyphen form
//! `needs-action` (RFC 5545 spelling, matching the schema
//! description). Legacy underscore payloads such as `needs_action`
//! are rejected at trust boundaries instead of being normalized.
//!
//! The closed 4-value RFC 5545 PARTSTAT subset is a Rust enum
//! ([`AttendeeStatus`]) so every consumer can exhaustive-match
//! instead of dispatching on canonical strings, the schema CHECK is
//! the only string-side gate, and the "what's the canonical wording
//! for this variant" question collapses to a single `as_str()` call.

use std::str::FromStr;

/// RFC 5545 PARTSTAT subset rendered by Lorvex. Closed 4-value set
/// matching the schema CHECK on `calendar_event_attendees.status` in
/// `001_schema.sql`. Adding a new variant requires updating that CHECK
/// and the relevant UI affordances.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AttendeeStatus {
    Accepted,
    Declined,
    Tentative,
    NeedsAction,
}

impl AttendeeStatus {
    /// Canonical RFC 5545 PARTSTAT spelling. Matches the schema CHECK
    /// constraint on `calendar_event_attendees.status` byte-for-byte.
    pub const fn as_str(self) -> &'static str {
        match self {
            AttendeeStatus::Accepted => "accepted",
            AttendeeStatus::Declined => "declined",
            AttendeeStatus::Tentative => "tentative",
            AttendeeStatus::NeedsAction => "needs-action",
        }
    }

    /// Strict parse: only accepts the canonical RFC 5545 wording (the
    /// hyphen form for `needs-action`). The schema CHECK is the last
    /// gate, but every trust boundary uses this parser so
    /// non-canonical rows never round-trip back out to peers.
    pub fn parse_strict(raw: &str) -> Option<Self> {
        Some(match raw {
            "accepted" => AttendeeStatus::Accepted,
            "declined" => AttendeeStatus::Declined,
            "tentative" => AttendeeStatus::Tentative,
            "needs-action" => AttendeeStatus::NeedsAction,
            _ => return None,
        })
    }

    /// Iterate the canonical 4-value set in a stable order.
    pub const fn all() -> &'static [AttendeeStatus] {
        &[
            AttendeeStatus::Accepted,
            AttendeeStatus::Declined,
            AttendeeStatus::Tentative,
            AttendeeStatus::NeedsAction,
        ]
    }
}

impl std::fmt::Display for AttendeeStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for AttendeeStatus {
    type Err = UnknownAttendeeStatus;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse_strict(s).ok_or_else(|| UnknownAttendeeStatus(s.to_string()))
    }
}

/// Error returned by [`AttendeeStatus::from_str`] when the input is
/// not a canonical attendee status.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownAttendeeStatus(pub String);

impl std::fmt::Display for UnknownAttendeeStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "unknown attendee status: {}", self.0)
    }
}

impl std::error::Error for UnknownAttendeeStatus {}

/// Canonical attendee `status` values as raw strings. Matches RFC 5545
/// PARTSTAT (subset we render in the UI). Kept as a `&[&str]` purely
/// for the small number of surfaces that build a comma-joined error
/// message (`attendee_status_allowlist_display`); the closed set
/// itself lives on [`AttendeeStatus`].
pub const ATTENDEE_STATUS_ALLOWLIST: &[&str] = &[
    AttendeeStatus::Accepted.as_str(),
    AttendeeStatus::Declined.as_str(),
    AttendeeStatus::Tentative.as_str(),
    AttendeeStatus::NeedsAction.as_str(),
];

/// Render the allowlist as a stable comma-joined string for
/// validation error wording.
pub fn attendee_status_allowlist_display() -> String {
    ATTENDEE_STATUS_ALLOWLIST.join(", ")
}

#[cfg(test)]
mod tests;
