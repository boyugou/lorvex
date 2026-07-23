//! Cross-surface primitives for `calendar_subscription` (.ics feed)
//! handling. Owns the pure, side-effect-free pieces that every
//! surface that touches subscription feeds needs to share:
//!
//! - [`tzid`] — TZID → IANA resolution, ICS DATE / DATE-TIME parsing,
//!   per-feed VTIMEZONE lookup via [`vtimezone::VTimezoneRegistry`],
//!   and unknown-TZID diagnostics surfaced through a caller-supplied
//!   [`tzid::UnknownTzidSink`].
//! - [`validation`] — URL safety + SSRF / DNS-rebinding defense,
//!   driven by the [`validation::HostResolver`] DI seam so tests can
//!   inject deterministic resolvers and production wires
//!   [`validation::DefaultHostResolver`].
//! - [`vtimezone`] — RFC 5545 `BEGIN:VTIMEZONE` parsing and per-feed
//!   wall-clock-to-UTC offset resolution for TZIDs that ship inside
//!   the feed body (Outlook display names, self-hosted calendar
//!   servers shipping invented identifiers, etc.).
//! - [`truncation`] — mid-stream truncation detection for fetched ICS
//!   bodies; consumed by the Tauri fetch layer (which runs the check
//!   on freshly-downloaded bodies) and by [`parse`] as
//!   defense-in-depth for in-memory test / offline-import callers.
//! - [`parse`] — VEVENT extraction from an ICS body into the
//!   [`parse::ParsedEvent`] shape every downstream surface upserts.
//!   Includes the RRULE → JSON encoding ([`parse::rrule_to_json`])
//!   that the recurrence engine consumes.
//!
//! The fetch and sync pipelines (HTTP transport, per-row DB
//! mutations, scheduler) still live in the Tauri crate — they require
//! HTTP, OS-native calendar bridges, and shared DB connection state
//! that does not belong in `lorvex-workflow`.

pub mod error;
pub mod mutations;
pub mod parse;
pub mod scheduling;
pub mod sync;
pub mod truncation;
pub mod tzid;
pub mod validation;
pub mod vtimezone;

pub use error::CalendarSubscriptionError;
pub use mutations::{
    add_response, calendar_subscription_exists, list_calendar_subscriptions,
    remove_payload_was_present, upsert_payload_matched, AddCalendarSubscriptionMutation,
    CalendarSubscription, CalendarSubscriptionSyncHealth, RemoveCalendarSubscriptionMutation,
    RemoveCalendarSubscriptionResult, ToggleCalendarSubscriptionMutation,
    ToggleCalendarSubscriptionResult, UpdateCalendarSubscriptionColorMutation,
    UpdateCalendarSubscriptionColorResult,
};
pub use parse::{
    parse_ics_events, parse_ics_events_with_diagnostics, rrule_to_json,
    rrule_to_json_with_warnings, IcsParseReport, IcsParseWarning, ParsedEvent,
    MAX_ATTENDEES_PER_EVENT,
};
pub use scheduling::{
    clear_subscription_next_retry, rate_limit_cooldown_until, record_subscription_failure,
    record_subscription_success, DEFAULT_RATE_LIMIT_COOLDOWN_SECS, MAX_RATE_LIMIT_COOLDOWN_SECS,
};
pub use sync::{
    record_ics_truncation_rejection, retry_calendar_subscription_now,
    sync_all_calendar_subscriptions, sync_calendar_subscription, sync_subscription_content,
    FetchBackend, FetchedIcs, FetchedIcsError, SubscriptionSyncResult, ICS_TRUNCATION_LOG_SOURCE,
};
pub use truncation::{detect_ics_truncation, IcsTruncationReason, ICS_TRUNCATION_MESSAGE};

#[cfg(test)]
mod tests;
