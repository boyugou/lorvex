//! Canonical `provider_kind` allowlist for calendar provider links.
//!
//! Centralizing the allowlist here keeps the four surfaces that need
//! it (Tauri IPC, MCP server, native-clear command, and several
//! `provider_scope_runtime_state` SQL writers) on a single set.
//! Without this domain anchor those surfaces drift into incompatible
//! sets — each surface ships with its own ad-hoc allowlist:
//!
//! | Surface              | Old allowlist                                                |
//! |----------------------|--------------------------------------------------------------|
//! | Tauri command        | `eventkit, google_calendar, outlook, ics`                    |
//! | MCP server           | `eventkit, google_calendar, outlook, ics`                    |
//! | Linux platform write | `linux_ics`                                                  |
//! | Windows platform     | `windows_appointments`                                       |
//! | iCal subscription    | `ical_subscription`                                          |
//!
//! Platform-layer writes bypassed IPC validation, so rows landed in
//! SQLite carrying `linux_ics` / `windows_appointments` /
//! `ical_subscription` while the canonical Tauri/MCP allowlist
//! refused them — a peer's MCP write that touched the same row
//! would fail validation against the legacy stored kind.
//!
//! The fix is a single canonical allowlist that covers every real
//! producer (#2954 acceptance criterion): every surface — Tauri IPC,
//! MCP IPC, platform-direct writers, store-read paths, schema CHECK,
//! sync apply — imports the same const from this module.

/// Schemes accepted for `provider_kind` across every persistence
/// surface that touches calendar provider links and provider scope
/// runtime state.
///
/// Adding a new provider integration requires editing this constant
/// AND any read-side resolution dispatch that maps the kind to a
/// reader. The schema CHECK constraint on `task_provider_event_links`,
/// `provider_calendar_events`, and `provider_scope_runtime_state`
/// must be updated in lockstep — see `001_schema.sql`.
///
/// Order is alphabetic to keep diffs small when adding new kinds.
pub const PROVIDER_KIND_EVENTKIT: &str = "eventkit";
pub const PROVIDER_KIND_GOOGLE_CALENDAR: &str = "google_calendar";
pub const PROVIDER_KIND_ICAL_SUBSCRIPTION: &str = "ical_subscription";
pub const PROVIDER_KIND_ICS: &str = "ics";
pub const PROVIDER_KIND_LINUX_ICS: &str = "linux_ics";
pub const PROVIDER_KIND_OUTLOOK: &str = "outlook";
pub const PROVIDER_KIND_WINDOWS_APPOINTMENTS: &str = "windows_appointments";

pub const PROVIDER_KIND_ALLOWLIST: &[&str] = &[
    PROVIDER_KIND_EVENTKIT,
    PROVIDER_KIND_GOOGLE_CALENDAR,
    PROVIDER_KIND_ICAL_SUBSCRIPTION,
    PROVIDER_KIND_ICS,
    PROVIDER_KIND_LINUX_ICS,
    PROVIDER_KIND_OUTLOOK,
    PROVIDER_KIND_WINDOWS_APPOINTMENTS,
];

/// Returns `true` if `kind` is in the canonical
/// [`PROVIDER_KIND_ALLOWLIST`]. Matches case-sensitively because
/// every kind is fully ASCII-lowercase by convention; a case-folded
/// match would mask a forked builder that uppercases the value.
pub fn is_allowed_provider_kind(kind: &str) -> bool {
    PROVIDER_KIND_ALLOWLIST.contains(&kind)
}

/// Render the allowlist as a stable comma-joined string for use in
/// validation error messages. Returns the SAME ordering as the
/// constant so error wording is deterministic across surfaces.
pub fn provider_kind_allowlist_display() -> String {
    PROVIDER_KIND_ALLOWLIST.join(", ")
}

#[cfg(test)]
mod tests;
