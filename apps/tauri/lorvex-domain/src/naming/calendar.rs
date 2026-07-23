//! Calendar AI access mode — a device-local setting stored in
//! `device_state` under the key `calendar_ai_access_mode` (see
//! `preference_keys::DEV_CALENDAR_AI_ACCESS_MODE`) controlling what
//! provider calendar data AI/MCP read surfaces can see.

use serde::{Deserialize, Serialize};

/// Controls what provider calendar data AI/MCP read surfaces can see.
///
/// This is a device-local setting stored in `device_state` under the key
/// `calendar_ai_access_mode` (see `preference_keys::DEV_CALENDAR_AI_ACCESS_MODE`).
///
/// The three tiers:
/// - `Off` — provider data contributes nothing to AI/planning reads.
/// - `BusyOnly` — provider occupancy contributes to blocking/planning, but
///   detail fields (title, location, description) are redacted.
/// - `FullDetails` — provider detail fields are passed through unmodified.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CalendarAiAccessMode {
    Off,
    BusyOnly,
    FullDetails,
}

impl CalendarAiAccessMode {
    /// Strict parser used by writers that surface validation errors back to
    /// callers (CLI, MCP). Returns `None` for unrecognized values so each
    /// surface can wrap the failure in its own error type.
    pub fn parse_strict(s: &str) -> Option<Self> {
        match s.trim() {
            "off" => Some(Self::Off),
            "busy_only" => Some(Self::BusyOnly),
            "full_details" => Some(Self::FullDetails),
            _ => None,
        }
    }

    /// Serialize to the canonical string form.
    pub const fn as_str(&self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::BusyOnly => "busy_only",
            Self::FullDetails => "full_details",
        }
    }

    /// Whether provider events should be included at all (i.e. not `Off`).
    pub const fn includes_provider(&self) -> bool {
        !matches!(self, Self::Off)
    }

    /// Whether provider event detail fields (title, location, description,
    /// person_name) should be passed through unredacted.
    pub const fn includes_details(&self) -> bool {
        matches!(self, Self::FullDetails)
    }

    /// The spec-defined default: `BusyOnly`.
    pub const fn default_mode() -> Self {
        Self::BusyOnly
    }
}
